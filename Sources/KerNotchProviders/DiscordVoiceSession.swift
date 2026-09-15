import Foundation
import KerNotchCore
import os

/// What the RPC connection knows about the user's voice call.
public struct DiscordVoiceState: Equatable, Sendable {
    public static let unknown = DiscordVoiceState(channel: nil, isMuted: nil)

    public let channel: DiscordVoiceChannel?
    public let isMuted: Bool?

    public init(channel: DiscordVoiceChannel?, isMuted: Bool?) {
        self.channel = channel
        self.isMuted = isMuted
    }
}

/// A one-shot delayed action, behind a protocol so reconnection is testable
/// without waiting.
@MainActor
public protocol DiscordReconnectScheduling: AnyObject {
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
public final class TaskDiscordReconnectScheduler: DiscordReconnectScheduling {
    private var task: Task<Void, Never>?

    public init() {}

    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard Task.isCancelled == false else { return }
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Everything the session reaches outside itself.
struct DiscordVoiceSessionDependencies {
    var transport: any DiscordIPCTransport
    var socketPaths: @MainActor () -> [String]
    var tokens: any DiscordTokenExchanging
    var credentials: any DiscordCredentialStoring
    var reconnect: any DiscordReconnectScheduling
    var now: @MainActor () -> Date
}

/// The connection to the local Discord client, from handshake to the voice
/// state the island draws.
///
/// Cheap by construction. The socket is parked between messages; the only
/// subscriptions are the channel selection and the voice settings, which change
/// when the user does something; server names are fetched once per server; and
/// reconnection is a short, bounded backoff that gives up until Discord is
/// launched again rather than a timer that runs for as long as Discord is quit.
@MainActor
public final class DiscordVoiceSession: DiscordVoiceChannelLeaving {
    /// A socket appears a few seconds after Discord launches, and disappears for
    /// a moment while it updates itself. Five attempts span about a minute.
    static let reconnectDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32)]

    private static let logger = Logger(subsystem: "com.kernotch.KerNotch", category: "discord-session")

    public var onStatusChange: (@MainActor (DiscordConnectionStatus) -> Void)?
    public var onVoiceStateChange: (@MainActor (DiscordVoiceState) -> Void)?

    public private(set) var status = DiscordConnectionStatus.inactive {
        didSet {
            guard status != oldValue else { return }
            onStatusChange?(status)
        }
    }

    public private(set) var voiceState = DiscordVoiceState.unknown {
        didSet {
            guard voiceState != oldValue else { return }
            onVoiceStateChange?(voiceState)
        }
    }

    private let dependencies: DiscordVoiceSessionDependencies
    private let client: DiscordRPCClient

    private var clientID: DiscordClientID?
    private var username: String?
    private var untriedSocketPaths: [String] = []
    private var hasReceivedReady = false
    private var reconnectAttempt = 0
    /// Bumped on every new connection and every stop, so a reply that arrives
    /// for a connection that is already gone changes nothing.
    private var generation = 0
    private var serverNames: [String: String] = [:]
    /// Bumped on every channel change Discord reports, so a lookup started for
    /// one channel cannot land after the user has already moved on — or left.
    private var channelRevision = 0

    public convenience init() {
        self.init(
            dependencies: DiscordVoiceSessionDependencies(
                transport: UnixSocketDiscordIPCTransport(),
                socketPaths: { DiscordIPCSocketLocator.existingSocketPaths() },
                tokens: URLSessionDiscordTokenExchange(),
                credentials: FileDiscordCredentialStore(),
                reconnect: TaskDiscordReconnectScheduler(),
                now: Date.init
            )
        )
    }

    init(dependencies: DiscordVoiceSessionDependencies) {
        self.dependencies = dependencies
        client = DiscordRPCClient(transport: dependencies.transport)
    }

    /// Connects with `clientID`, reusing a connection already made with it.
    public func start(clientID: DiscordClientID) {
        guard self.clientID != clientID || status == .inactive else { return }

        stop()
        self.clientID = clientID
        connect()
    }

    public func stop() {
        generation += 1
        dependencies.reconnect.cancel()
        client.disconnect()
        clientID = nil
        username = nil
        reconnectAttempt = 0
        status = .inactive
        voiceState = .unknown
    }

    /// Discord was launched, or took the microphone: its socket is there or
    /// about to be, so a session that had given up tries again from the start
    /// of its backoff.
    public func discordBecameActive() {
        guard clientID != nil, status == .discordUnavailable else { return }

        reconnectAttempt = 0
        scheduleReconnect()
    }

    /// Starts the connection over. The way out of a state waiting on something
    /// that may never answer — an ignored prompt, a handshake Discord dropped,
    /// a backoff that ran out while Discord was busy.
    public func reconnect() {
        guard let clientID, status.canReconnect else { return }

        stop()
        start(clientID: clientID)
    }

    /// Raises Discord's authorization prompt. The user's action, never
    /// automatic: the prompt appears inside Discord, in front of whatever the
    /// user is doing.
    public func authorize() {
        guard let clientID, status.canAuthorize else { return }

        let generation = self.generation
        let pkce = DiscordPKCE.generate()
        status = .awaitingApproval

        Task { [weak self] in
            await self?.authorize(clientID: clientID, pkce: pkce, generation: generation)
        }
    }

    /// Deletes the stored authorization and reconnects without it.
    public func forgetAuthorization() {
        guard let clientID else { return }

        stop()
        let generation = self.generation
        Task { [weak self] in
            guard let self else { return }
            await dependencies.credentials.deleteCredentials(for: clientID)
            // Anything that stopped or started the session meanwhile — the
            // switch turned off, a new Client ID — has the last word.
            guard generation == self.generation else { return }
            start(clientID: clientID)
        }
    }

    public func leaveVoiceChannel() {
        guard case .connected = status else { return }

        let generation = self.generation
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.perform(.selectVoiceChannel, arguments: DiscordLeaveVoiceChannelArguments())
                guard generation == self.generation else { return }
                channelRevision += 1
                voiceState = DiscordVoiceState(channel: nil, isMuted: voiceState.isMuted)
            } catch {
                let reason = String(describing: error)
                Self.logger.error("Leaving the Discord voice channel failed: \(reason, privacy: .public)")
            }
        }
    }

    // MARK: - Connection

    private func connect() {
        untriedSocketPaths = dependencies.socketPaths()
        connectToNextSocket()
    }

    /// Several Discord clients — Stable beside PTB, or a stale socket left by a
    /// crash — can each hold a path, so a path that closes before the handshake
    /// completes hands over to the next one.
    private func connectToNextSocket() {
        guard let clientID, untriedSocketPaths.isEmpty == false else {
            becomeUnavailable()
            return
        }

        generation += 1
        let generation = self.generation
        hasReceivedReady = false
        status = .connecting

        client.connect(socketPath: untriedSocketPaths.removeFirst(), clientID: clientID) { [weak self] event in
            guard let self, generation == self.generation else { return }
            handle(event)
        }
    }

    private func handle(_ event: DiscordRPCClientEvent) {
        switch event {
        case .ready(let username):
            // The backoff is not reset here: a Discord that accepts the
            // handshake and then hangs up would otherwise be retried forever.
            hasReceivedReady = true
            self.username = username
            authenticateWithStoredCredentials()
        case .dispatch(let event, let payload):
            handleDispatch(event, payload: payload)
        case .closed(let reason):
            handleClosed(reason)
        }
    }

    private func handleClosed(_ reason: DiscordRPCError?) {
        voiceState = .unknown

        if reason?.code == DiscordRPCError.invalidClientIDCode {
            status = .failed(.invalidClientID)
            return
        }
        if hasReceivedReady == false, untriedSocketPaths.isEmpty == false {
            connectToNextSocket()
            return
        }
        becomeUnavailable()
    }

    private func becomeUnavailable() {
        status = .discordUnavailable
        voiceState = .unknown
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectAttempt < Self.reconnectDelays.count else { return }

        let delay = Self.reconnectDelays[reconnectAttempt]
        reconnectAttempt += 1
        dependencies.reconnect.schedule(after: delay) { [weak self] in
            guard let self, clientID != nil, status == .discordUnavailable else { return }
            connect()
        }
    }

    // MARK: - Authorization

    /// The stored credentials are read off the main actor, so file I/O never
    /// holds the island still.
    private func authenticateWithStoredCredentials() {
        guard let clientID else { return }

        let generation = self.generation
        Task { [weak self] in
            guard let self else { return }
            guard let stored = await dependencies.credentials.credentials(for: clientID) else {
                guard generation == self.generation else { return }
                status = .needsAuthorization
                return
            }
            await authenticate(stored, clientID: clientID, generation: generation)
        }
    }

    private enum AuthenticationOutcome {
        case authenticated
        case tokenRejected
        case interrupted
    }

    private enum Renewal {
        case renewed(DiscordCredentials)
        /// Discord refused the refresh token, or there is none: the stored
        /// authorization is spent.
        case rejected
        /// The refresh could not be attempted — offline, most likely. The stored
        /// authorization may still be good next time.
        case unavailable
    }

    /// Uses the stored token, renewing it first when it is about to lapse and
    /// once more if Discord rejects it.
    ///
    /// The stored authorization is deleted only when Discord itself refuses to
    /// renew it. A Mac that wakes offline keeps its token and connects on the
    /// next attempt instead of asking the user to approve KerNotch again.
    private func authenticate(_ stored: DiscordCredentials, clientID: DiscordClientID, generation: Int) async {
        var credentials = stored
        var hasRenewed = false

        if stored.isExpiring(at: dependencies.now()) {
            switch await renew(stored, clientID: clientID) {
            case .renewed(let renewed):
                credentials = renewed
                hasRenewed = true
            case .rejected:
                await requireAuthorization(forgetting: clientID, generation: generation)
                return
            case .unavailable:
                break
            }
        }

        guard await authenticate(with: credentials, generation: generation) == .tokenRejected else { return }
        guard hasRenewed == false else {
            await requireAuthorization(forgetting: clientID, generation: generation)
            return
        }

        switch await renew(credentials, clientID: clientID) {
        case .renewed(let renewed):
            if await authenticate(with: renewed, generation: generation) == .tokenRejected {
                await requireAuthorization(forgetting: clientID, generation: generation)
            }
        case .rejected:
            await requireAuthorization(forgetting: clientID, generation: generation)
        case .unavailable:
            guard generation == self.generation else { return }
            status = .needsAuthorization
        }
    }

    private func authenticate(with credentials: DiscordCredentials, generation: Int) async -> AuthenticationOutcome {
        do {
            try await client.perform(
                .authenticate,
                arguments: DiscordAuthenticateArguments(accessToken: credentials.accessToken)
            )
        } catch let error as DiscordRPCError where error != DiscordRPCClient.connectionClosed {
            return .tokenRejected
        } catch {
            return .interrupted
        }

        guard generation == self.generation else { return .interrupted }
        didAuthenticate()
        return .authenticated
    }

    private func renew(_ credentials: DiscordCredentials, clientID: DiscordClientID) async -> Renewal {
        guard let refreshToken = credentials.refreshToken else { return .rejected }

        do {
            let response = try await dependencies.tokens.refresh(refreshToken, clientID: clientID)
            // A renewal that names no new refresh token leaves the old one in
            // force; dropping it would make this the last renewal ever possible.
            let renewed = DiscordCredentials(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken ?? refreshToken,
                expiresAt: response.expiresAt
            )
            await dependencies.credentials.save(renewed, for: clientID)
            return .renewed(renewed)
        } catch is DiscordTokenExchangeError {
            return .rejected
        } catch {
            Self.logger.error("Refreshing the Discord token failed: \(String(describing: error), privacy: .public)")
            return .unavailable
        }
    }

    private func requireAuthorization(forgetting clientID: DiscordClientID, generation: Int) async {
        guard generation == self.generation else { return }
        await dependencies.credentials.deleteCredentials(for: clientID)
        guard generation == self.generation else { return }
        status = .needsAuthorization
    }

    private func authorize(clientID: DiscordClientID, pkce: DiscordPKCE, generation: Int) async {
        do {
            let authorization = try await client.request(
                .authorize,
                arguments: DiscordAuthorizeArguments(
                    clientID: clientID.rawValue,
                    scopes: DiscordAuthorizeArguments.scopes,
                    codeChallenge: pkce.challenge
                ),
                returning: DiscordAuthorizeBody.self
            )
            let credentials = try await dependencies.tokens.redeem(
                code: authorization.code,
                verifier: pkce.verifier,
                clientID: clientID
            )
            guard generation == self.generation else { return }
            await dependencies.credentials.save(credentials, for: clientID)

            let outcome = await authenticate(with: credentials, generation: generation)
            if outcome == .tokenRejected, generation == self.generation {
                status = .failed(.authorizationFailed)
            }
        } catch let error as DiscordRPCError where error == DiscordRPCClient.connectionClosed {
            return
        } catch let error as DiscordRPCError where error.code == DiscordRPCError.oauth2ErrorCode {
            guard generation == self.generation else { return }
            status = .failed(.authorizationDenied)
        } catch {
            guard generation == self.generation else { return }
            Self.logger.error("Authorizing with Discord failed: \(String(describing: error), privacy: .public)")
            status = .failed(.authorizationFailed)
        }
    }

    // MARK: - Voice state

    private func didAuthenticate() {
        reconnectAttempt = 0
        status = .connected(username: username)

        let generation = self.generation
        Task { [weak self] in
            await self?.loadVoiceState(generation: generation)
        }
    }

    /// Subscribes to the call's changes, then reads it as it stands.
    ///
    /// Subscribing first means a change between the read and the subscription
    /// is not lost, and a read that fails costs only its own value: the
    /// subscriptions are already in place for everything after it. Reading at
    /// all is what makes a call already in progress show at once rather than on
    /// the user's next move.
    private func loadVoiceState(generation: Int) async {
        do {
            try await client.perform(.subscribe, event: .voiceChannelSelect)
            try await client.perform(.subscribe, event: .voiceSettingsUpdate)
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Subscribing to Discord voice events failed: \(reason, privacy: .public)")
            return
        }

        if let settings = try? await client.request(.getVoiceSettings, returning: DiscordVoiceSettingsBody.self),
            generation == self.generation
        {
            voiceState = DiscordVoiceState(channel: voiceState.channel, isMuted: settings.mute)
        }

        let revision = channelRevision
        do {
            let channel = try await client.request(.getSelectedVoiceChannel, returning: DiscordChannelBody?.self)
            let voiceChannel = await voiceChannel(for: channel)
            guard generation == self.generation, revision == channelRevision else { return }
            voiceState = DiscordVoiceState(channel: voiceChannel, isMuted: voiceState.isMuted)
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Reading the Discord voice channel failed: \(reason, privacy: .public)")
        }
    }

    private func handleDispatch(_ event: DiscordRPCEvent, payload: Data) {
        let decoder = JSONDecoder()
        switch event {
        case .voiceChannelSelect:
            let body = DiscordRPCPayload<DiscordVoiceChannelSelectBody>.self
            guard let selection = try? decoder.decode(body, from: payload) else { return }
            channelDidChange(to: selection.data.channelID)
        case .voiceSettingsUpdate:
            guard let settings = try? decoder.decode(DiscordRPCPayload<DiscordVoiceSettingsBody>.self, from: payload)
            else { return }
            voiceState = DiscordVoiceState(channel: voiceState.channel, isMuted: settings.data.mute)
        case .ready, .error:
            break
        }
    }

    private func channelDidChange(to channelID: String?) {
        channelRevision += 1
        guard let channelID else {
            voiceState = DiscordVoiceState(channel: nil, isMuted: voiceState.isMuted)
            return
        }

        let generation = self.generation
        let revision = channelRevision
        Task { [weak self] in
            guard let self else { return }
            do {
                let channel = try await client.request(
                    .getChannel,
                    arguments: DiscordChannelArguments(channelID: channelID),
                    returning: DiscordChannelBody?.self
                )
                let voiceChannel = await voiceChannel(for: channel)
                guard generation == self.generation, revision == channelRevision else { return }
                voiceState = DiscordVoiceState(channel: voiceChannel, isMuted: voiceState.isMuted)
            } catch {
                Self.logger.error("Reading the Discord channel failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func voiceChannel(for channel: DiscordChannelBody?) async -> DiscordVoiceChannel? {
        guard let channel else { return nil }

        return DiscordVoiceChannel(
            name: channel.name ?? "",
            serverName: await serverName(for: channel.guildID)
        )
    }

    /// A server name that cannot be read is left out rather than failing the
    /// channel it belongs to, and is not cached, so the next change tries again.
    private func serverName(for guildID: String?) async -> String? {
        guard let guildID else { return nil }
        if let cached = serverNames[guildID] {
            return cached
        }

        guard
            let guild = try? await client.request(
                .getGuild,
                arguments: DiscordGuildArguments(guildID: guildID),
                returning: DiscordGuildBody.self
            )
        else { return nil }
        serverNames[guildID] = guild.name
        return guild.name
    }
}
