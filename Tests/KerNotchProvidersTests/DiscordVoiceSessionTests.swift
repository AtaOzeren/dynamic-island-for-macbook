import Foundation
import KerNotchCore
import Testing

@testable import KerNotchProviders

/// The session against a scripted Discord: connecting, authorizing without ever
/// prompting on its own, keeping a token alive, reading the call, and staying
/// cheap — a bounded reconnect, and only the two subscriptions the island needs.
@Suite("DiscordVoiceSession")
@MainActor
struct DiscordVoiceSessionTests {
    private static let socket = "/var/folders/xy/T/discord-ipc-0"
    private static let now = Date(timeIntervalSinceReferenceDate: 0)

    @MainActor
    private final class Fixture {
        let transport = FakeDiscordIPCTransport()
        let tokens = FakeDiscordTokenExchange()
        let credentials = FakeDiscordCredentialStore()
        let reconnect = FakeDiscordReconnectScheduler()
        var socketPaths = [socket]
        var guildReads = 0
        var selectedChannel: [String: Any]? = ["id": "10", "name": "Lobby", "guild_id": "20"]
        var isMuted = false
        var statuses: [DiscordConnectionStatus] = []

        lazy var session: DiscordVoiceSession = {
            let session = DiscordVoiceSession(
                dependencies: DiscordVoiceSessionDependencies(
                    transport: transport,
                    socketPaths: { [unowned self] in socketPaths },
                    tokens: tokens,
                    credentials: credentials,
                    reconnect: reconnect,
                    now: { now }
                )
            )
            session.onStatusChange = { [unowned self] in statuses.append($0) }
            return session
        }()

        init() {
            transport.respond = { [unowned self] sent in reply(to: sent) }
        }

        /// A Discord that accepts the fresh token and knows one call.
        func reply(to sent: FakeDiscordIPCTransport.SentCommand) -> FakeDiscordIPCTransport.Reply {
            switch sent.command {
            case "AUTHENTICATE":
                let token = sent.arguments["access_token"] as? String
                return token == "stale-access"
                    ? .error(code: DiscordRPCError.invalidTokenCode, message: "Invalid token") : .data(["scopes": []])
            case "AUTHORIZE":
                return .data(["code": "authorization-code"])
            case "GET_SELECTED_VOICE_CHANNEL":
                return .data(selectedChannel)
            case "GET_CHANNEL":
                return .data(["id": sent.arguments["channel_id"] as Any, "name": "Room 102", "guild_id": "20"])
            case "GET_GUILD":
                guildReads += 1
                return .data(["id": "20", "name": "Ocean View Hotel"])
            case "GET_VOICE_SETTINGS":
                return .data(["mute": isMuted, "deaf": false])
            default:
                return .data(nil)
            }
        }

        func startWithStoredToken(_ stored: DiscordCredentials = .fresh) async {
            credentials.stored[.testApplication] = stored
            session.start(clientID: .testApplication)
            await settleDiscordTasks()
        }
    }

    private static let stale = DiscordCredentials(
        accessToken: "stale-access",
        refreshToken: "stale-refresh",
        expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60)
    )

    // MARK: Connecting

    @Test("says Discord is unavailable when no socket exists, and schedules a retry")
    func unavailableWithoutSocket() {
        let fixture = Fixture()
        fixture.socketPaths = []

        fixture.session.start(clientID: .testApplication)

        #expect(fixture.session.status == .discordUnavailable)
        #expect(fixture.reconnect.scheduledDelays == [.seconds(2)])
    }

    /// Discord quit for the day must not become a timer that runs until
    /// KerNotch quits too.
    @Test("gives up after a bounded backoff, and starts over when Discord launches")
    func boundedReconnect() {
        let fixture = Fixture()
        fixture.socketPaths = []
        fixture.session.start(clientID: .testApplication)

        for _ in 0..<10 {
            fixture.reconnect.fire()
        }

        #expect(fixture.reconnect.scheduledDelays == DiscordVoiceSession.reconnectDelays)
        #expect(fixture.reconnect.hasPendingAttempt == false)

        fixture.session.discordBecameActive()
        #expect(fixture.reconnect.hasPendingAttempt)
    }

    @Test("moves on to the next socket when one closes before the handshake")
    func triesNextSocket() async {
        let fixture = Fixture()
        fixture.socketPaths = ["/tmp/discord-ipc-0", "/tmp/discord-ipc-1"]
        fixture.transport.refusedPaths = ["/tmp/discord-ipc-0"]

        await fixture.startWithStoredToken()

        #expect(fixture.transport.openedPaths == ["/tmp/discord-ipc-0", "/tmp/discord-ipc-1"])
        #expect(fixture.session.status == .connected(username: "webh0sta"))
    }

    @Test("stops for good on an invalid Client ID instead of retrying")
    func invalidClientIDIsFinal() {
        let fixture = Fixture()
        fixture.transport.answersHandshake = false
        fixture.session.start(clientID: .testApplication)

        fixture.transport.closeFromDiscord(code: 4000, message: "Invalid Client ID")

        #expect(fixture.session.status == .failed(.invalidClientID))
        #expect(fixture.reconnect.hasPendingAttempt == false)
    }

    @Test("reconnects after Discord quits mid-session, and forgets the call")
    func reconnectsAfterDrop() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.transport.dropConnection()

        #expect(fixture.session.status == .discordUnavailable)
        #expect(fixture.session.voiceState == .unknown)
        #expect(fixture.reconnect.hasPendingAttempt)
    }

    // MARK: Authorization

    /// The prompt appears inside Discord, in front of whatever the user is
    /// doing, so it is only ever raised by a press of Connect.
    @Test("never raises Discord's prompt on its own")
    func neverAuthorizesAutomatically() async {
        let fixture = Fixture()

        fixture.session.start(clientID: .testApplication)
        await settleDiscordTasks()

        #expect(fixture.session.status == .needsAuthorization)
        #expect(fixture.transport.commands(named: "AUTHORIZE").isEmpty)
    }

    @Test("authorizes with a PKCE challenge, redeems the code, and keeps the token")
    func authorizesWithPKCE() async throws {
        let fixture = Fixture()
        fixture.session.start(clientID: .testApplication)
        await settleDiscordTasks()

        fixture.session.authorize()
        #expect(fixture.session.status == .awaitingApproval)
        await settleDiscordTasks()

        let authorize = try #require(fixture.transport.commands(named: "AUTHORIZE").first)
        let redeemed = try #require(fixture.tokens.redeemedCodes.first)
        #expect(authorize.arguments["code_challenge_method"] as? String == "S256")
        #expect(authorize.arguments["scopes"] as? [String] == ["rpc", "rpc.voice.read"])
        #expect(authorize.arguments["code_challenge"] as? String == DiscordPKCE(verifier: redeemed.verifier).challenge)
        #expect(authorize.arguments["client_secret"] == nil)
        #expect(redeemed.code == "authorization-code")
        #expect(fixture.credentials.stored[.testApplication] == .fresh)
        #expect(fixture.session.status == .connected(username: "webh0sta"))
    }

    @Test("reports a declined prompt, and lets the user try again")
    func reportsDeclinedPrompt() async {
        let fixture = Fixture()
        fixture.transport.respond = { sent in
            sent.command == "AUTHORIZE" ? .error(code: 5000, message: "OAuth2 Error: access_denied") : .data(nil)
        }
        fixture.session.start(clientID: .testApplication)
        await settleDiscordTasks()

        fixture.session.authorize()
        await settleDiscordTasks()

        #expect(fixture.session.status == .failed(.authorizationDenied))
        #expect(fixture.session.status.canAuthorize)
    }

    @Test("reports a code Discord would not exchange — a private application")
    func reportsFailedExchange() async {
        let fixture = Fixture()
        fixture.tokens.redeemOutcome = .rejected
        fixture.session.start(clientID: .testApplication)
        await settleDiscordTasks()

        fixture.session.authorize()
        await settleDiscordTasks()

        #expect(fixture.session.status == .failed(.authorizationFailed))
        #expect(fixture.credentials.stored.isEmpty)
    }

    @Test("connects with a stored token without asking again")
    func usesStoredToken() async {
        let fixture = Fixture()

        await fixture.startWithStoredToken()

        #expect(fixture.session.status == .connected(username: "webh0sta"))
        #expect(fixture.transport.commands(named: "AUTHORIZE").isEmpty)
        #expect(fixture.tokens.refreshedTokens.isEmpty)
    }

    @Test("renews a rejected token once and connects with the renewal")
    func renewsRejectedToken() async {
        let fixture = Fixture()

        await fixture.startWithStoredToken(Self.stale)

        #expect(fixture.tokens.refreshedTokens == ["stale-refresh"])
        #expect(fixture.credentials.stored[.testApplication] == .renewed)
        #expect(fixture.session.status == .connected(username: "webh0sta"))
    }

    @Test("renews a token about to lapse before spending a handshake on it")
    func renewsExpiringToken() async {
        let fixture = Fixture()
        let expiring = DiscordCredentials(
            accessToken: "fresh-access",
            refreshToken: "expiring-refresh",
            expiresAt: Self.now.addingTimeInterval(60)
        )

        await fixture.startWithStoredToken(expiring)

        #expect(fixture.tokens.refreshedTokens == ["expiring-refresh"])
        let authenticate = fixture.transport.commands(named: "AUTHENTICATE").first
        #expect(authenticate?.arguments["access_token"] as? String == "renewed-access")
    }

    @Test("forgets an authorization Discord will not renew")
    func forgetsSpentAuthorization() async {
        let fixture = Fixture()
        fixture.tokens.refreshOutcome = .rejected

        await fixture.startWithStoredToken(Self.stale)

        #expect(fixture.credentials.stored.isEmpty)
        #expect(fixture.session.status == .needsAuthorization)
    }

    /// A Mac that wakes offline must not lose an authorization that is still
    /// good once the network is back.
    @Test("keeps the token when renewal fails for want of a network")
    func keepsTokenWhenOffline() async {
        let fixture = Fixture()
        fixture.tokens.refreshOutcome = .offline

        await fixture.startWithStoredToken(Self.stale)

        #expect(fixture.credentials.stored[.testApplication] == Self.stale)
        #expect(fixture.credentials.deletions == 0)
    }

    @Test("forgetting deletes the token and reconnects without one")
    func forgetAuthorization() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.session.forgetAuthorization()
        await settleDiscordTasks()

        #expect(fixture.credentials.stored.isEmpty)
        #expect(fixture.session.status == .needsAuthorization)
    }

    // MARK: Voice state

    @Test("reads a call already in progress when it connects")
    func readsCallInProgress() async {
        let fixture = Fixture()
        fixture.isMuted = true

        await fixture.startWithStoredToken()

        #expect(
            fixture.session.voiceState
                == DiscordVoiceState(
                    channel: DiscordVoiceChannel(name: "Lobby", serverName: "Ocean View Hotel"),
                    isMuted: true,
                    isDeafened: false
                )
        )
    }

    @Test("subscribes to the channel and the mute state, and nothing chattier")
    func subscribesSparingly() async {
        let fixture = Fixture()

        await fixture.startWithStoredToken()

        let events = fixture.transport.commands(named: "SUBSCRIBE").compactMap(\.event)
        #expect(events == ["VOICE_CHANNEL_SELECT", "VOICE_SETTINGS_UPDATE"])
    }

    @Test("follows the call into another channel, reading its server name only once")
    func followsChannelChanges() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.transport.dispatch("VOICE_CHANNEL_SELECT", data: ["channel_id": "11", "guild_id": "20"])
        await settleDiscordTasks()

        let room = DiscordVoiceChannel(name: "Room 102", serverName: "Ocean View Hotel")
        #expect(fixture.session.voiceState.channel == room)
        #expect(fixture.guildReads == 1)
    }

    @Test("clears the channel when the user leaves it from Discord")
    func clearsChannelOnLeave() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.transport.dispatch("VOICE_CHANNEL_SELECT", data: ["channel_id": NSNull(), "guild_id": NSNull()])

        #expect(fixture.session.voiceState.channel == nil)
    }

    @Test("follows the mute switch")
    func followsMute() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.transport.dispatch("VOICE_SETTINGS_UPDATE", data: ["mute": true, "deaf": false])

        #expect(fixture.session.voiceState.isMuted == true)
    }

    /// The reported defect: deafening switches the microphone off as well, but
    /// Discord leaves `mute` alone — so a session that read only `mute` kept
    /// reporting a live microphone.
    @Test("follows the deafen switch, which mute alone does not report")
    func followsDeafen() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.transport.dispatch("VOICE_SETTINGS_UPDATE", data: ["mute": false, "deaf": true])

        #expect(fixture.session.voiceState.isDeafened == true)
        #expect(fixture.session.voiceState.isMuted == false, "Discord's own flags are reported as they arrive")
    }

    /// Discord serialises these flags as numbers in some builds, and a call
    /// must not read as "unknown" for its whole length because of it.
    @Test("reads numeric voice flags")
    func numericVoiceFlags() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.transport.dispatch("VOICE_SETTINGS_UPDATE", data: ["mute": 0, "deaf": 1])

        #expect(fixture.session.voiceState.isDeafened == true)
        #expect(fixture.session.voiceState.isMuted == false)
    }

    @Test("a payload without the deafen flag reads as not deafened")
    func missingDeafenFlag() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.transport.dispatch("VOICE_SETTINGS_UPDATE", data: ["mute": true])

        #expect(fixture.session.voiceState.isMuted == true)
        #expect(fixture.session.voiceState.isDeafened == false)
    }

    @Test("leaves the channel with an explicit null, and clears it once Discord agrees")
    func leavesChannel() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.session.leaveVoiceChannel()
        await settleDiscordTasks()

        let leave = fixture.transport.commands(named: "SELECT_VOICE_CHANNEL").first
        #expect(leave?.arguments["channel_id"] is NSNull)
        #expect(fixture.session.voiceState.channel == nil)
    }

    @Test("does not try to leave without an authorized connection")
    func leaveNeedsConnection() async {
        let fixture = Fixture()
        fixture.session.start(clientID: .testApplication)
        await settleDiscordTasks()

        fixture.session.leaveVoiceChannel()
        await settleDiscordTasks()

        #expect(fixture.transport.commands(named: "SELECT_VOICE_CHANNEL").isEmpty)
    }

    @Test("stopping forgets the call and ignores whatever arrives late")
    func stopIgnoresLateReplies() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.session.stop()
        fixture.transport.dispatch("VOICE_SETTINGS_UPDATE", data: ["mute": true])

        #expect(fixture.session.status == .inactive)
        #expect(fixture.session.voiceState == .unknown)
        #expect(fixture.transport.isOpen == false)
    }

    /// Both orders are real: a join that fails at once, or a leave pressed
    /// while the joined channel's name is still being read.
    @Test("a lookup for a channel the user already left never brings it back")
    func staleChannelLookupIsDropped() async throws {
        let fixture = Fixture()
        fixture.selectedChannel = nil
        await fixture.startWithStoredToken()
        let answer = fixture.transport.respond
        fixture.transport.respond = { sent in sent.command == "GET_CHANNEL" ? .silence : answer(sent) }

        fixture.transport.dispatch("VOICE_CHANNEL_SELECT", data: ["channel_id": "11", "guild_id": "20"])
        await settleDiscordTasks()
        fixture.transport.dispatch("VOICE_CHANNEL_SELECT", data: ["channel_id": NSNull(), "guild_id": NSNull()])
        let lookup = try #require(fixture.transport.commands(named: "GET_CHANNEL").first)
        fixture.transport.deliver([
            "cmd": "GET_CHANNEL", "nonce": lookup.nonce,
            "data": ["id": "11", "name": "Room 102", "guild_id": "20"],
        ])
        await settleDiscordTasks()

        #expect(fixture.session.voiceState.channel == nil)
    }

    @Test("subscribes before reading, so a change during the read is not lost")
    func subscribesBeforeReading() async {
        let fixture = Fixture()

        await fixture.startWithStoredToken()

        let order = fixture.transport.sentCommands.map(\.command).filter { $0 != "AUTHENTICATE" }
        #expect(Array(order.prefix(2)) == ["SUBSCRIBE", "SUBSCRIBE"])
    }

    /// A server that cannot be read costs only its name: the channel still
    /// shows, and the subscriptions are in place for everything after it.
    @Test("an unreadable server name leaves the channel and its subscriptions intact")
    func serverFailureIsContained() async {
        let fixture = Fixture()
        let answer = fixture.transport.respond
        fixture.transport.respond = { sent in
            sent.command == "GET_GUILD" ? .error(code: 4006, message: "Not allowed") : answer(sent)
        }

        await fixture.startWithStoredToken()

        #expect(fixture.session.voiceState.channel == DiscordVoiceChannel(name: "Lobby", serverName: nil))
        #expect(fixture.transport.commands(named: "SUBSCRIBE").count == 2)
    }

    @Test("an unanswered prompt can be abandoned by starting over")
    func reconnectsFromUnansweredPrompt() async {
        let fixture = Fixture()
        let answer = fixture.transport.respond
        fixture.transport.respond = { sent in sent.command == "AUTHORIZE" ? .silence : answer(sent) }
        fixture.session.start(clientID: .testApplication)
        await settleDiscordTasks()
        fixture.session.authorize()
        await settleDiscordTasks()
        #expect(fixture.session.status.canReconnect)

        fixture.session.reconnect()
        await settleDiscordTasks()

        #expect(fixture.transport.openedPaths.count == 2)
        #expect(fixture.session.status == .needsAuthorization)
    }

    @Test("an error reply that cannot be read fails authorization instead of stranding it")
    func unreadableAuthorizeErrorFails() async throws {
        let fixture = Fixture()
        let answer = fixture.transport.respond
        fixture.transport.respond = { sent in sent.command == "AUTHORIZE" ? .silence : answer(sent) }
        fixture.session.start(clientID: .testApplication)
        await settleDiscordTasks()
        fixture.session.authorize()
        await settleDiscordTasks()

        let authorize = try #require(fixture.transport.commands(named: "AUTHORIZE").first)
        fixture.transport.deliver([
            "cmd": "AUTHORIZE", "evt": "ERROR", "nonce": authorize.nonce, "data": ["unexpected": 1],
        ])
        await settleDiscordTasks()

        #expect(fixture.session.status == .failed(.authorizationFailed))
    }

    /// A Discord that accepts the handshake and then hangs up must not be
    /// retried forever.
    @Test("a handshake alone does not reset the backoff")
    func readyDoesNotResetBackoff() async {
        let fixture = Fixture()
        fixture.session.start(clientID: .testApplication)
        await settleDiscordTasks()

        fixture.transport.dropConnection()
        fixture.reconnect.fire()
        await settleDiscordTasks()
        fixture.transport.dropConnection()

        #expect(fixture.reconnect.scheduledDelays == [.seconds(2), .seconds(4)])
    }

    @Test("a renewal without a new refresh token keeps the one it had")
    func renewalKeepsRefreshToken() async {
        let fixture = Fixture()
        fixture.tokens.refreshOutcome = .credentials(
            DiscordCredentials(
                accessToken: "renewed-access",
                refreshToken: nil,
                expiresAt: Self.now.addingTimeInterval(3600 * 24)
            )
        )

        await fixture.startWithStoredToken(Self.stale)

        #expect(fixture.credentials.stored[.testApplication]?.refreshToken == "stale-refresh")
        #expect(fixture.session.status == .connected(username: "webh0sta"))
    }

    @Test("switching off while forgetting does not reconnect behind the user's back")
    func forgetThenStopStaysStopped() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()
        let opened = fixture.transport.openedPaths.count

        fixture.session.forgetAuthorization()
        fixture.session.stop()
        await settleDiscordTasks()

        #expect(fixture.session.status == .inactive)
        #expect(fixture.transport.openedPaths.count == opened)
    }

    @Test("starting again with the same Client ID keeps the connection it has")
    func restartWithSameIDIsANoOp() async {
        let fixture = Fixture()
        await fixture.startWithStoredToken()

        fixture.session.start(clientID: .testApplication)

        #expect(fixture.transport.openedPaths.count == 1)
    }
}
