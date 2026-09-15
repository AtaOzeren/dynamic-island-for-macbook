import Foundation
import KerNotchCore

@testable import KerNotchProviders

/// A Discord client on the other end of the IPC socket, faked closely enough to
/// drive the RPC client and the session: it answers the handshake, replies to
/// commands through `respond`, and can push events or hang up on demand.
///
/// Everything happens synchronously on the main actor, so a test controls the
/// exact order of every message.
@MainActor
final class FakeDiscordIPCTransport: DiscordIPCTransport {
    enum Reply {
        case data(Any?)
        case error(code: Int, message: String)
        /// No reply at all — a command still pending, like an unanswered prompt.
        case silence
    }

    struct SentCommand {
        let command: String
        let arguments: [String: Any]
        let event: String?
        let nonce: String
    }

    var openedPaths: [String] = []
    var sentFrames: [DiscordIPCFrame] = []
    var sentCommands: [SentCommand] = []

    /// Paths whose connection fails before it opens, as a missing socket does.
    var refusedPaths: Set<String> = []
    var readyUsername: String? = "webh0sta"
    var answersHandshake = true
    var respond: (SentCommand) -> Reply = { _ in .data(nil) }

    private var onEvent: (@MainActor (DiscordIPCTransportEvent) -> Void)?

    var isOpen: Bool { onEvent != nil }

    func open(socketPath: String, onEvent: @escaping @MainActor (DiscordIPCTransportEvent) -> Void) {
        openedPaths.append(socketPath)
        guard refusedPaths.contains(socketPath) == false else {
            onEvent(.closed)
            return
        }
        self.onEvent = onEvent
        onEvent(.opened)
    }

    func send(_ frame: DiscordIPCFrame) {
        sentFrames.append(frame)
        switch frame.opcode {
        case .handshake where answersHandshake:
            deliver(["cmd": "DISPATCH", "evt": "READY", "data": ["v": 1, "user": ["username": readyUsername as Any]]])
        case .frame:
            handleCommand(frame.payload)
        case .handshake, .close, .ping, .pong:
            break
        }
    }

    func close() {
        onEvent = nil
    }

    func commands(named name: String) -> [SentCommand] {
        sentCommands.filter { $0.command == name }
    }

    func dispatch(_ event: String, data: [String: Any]) {
        deliver(["cmd": "DISPATCH", "evt": event, "data": data])
    }

    func sendPing() {
        onEvent?(.received(DiscordIPCFrame(opcode: .ping, payload: Data("{}".utf8))))
    }

    /// Discord closing the connection with a reason, as it does for a bad
    /// Client ID.
    func closeFromDiscord(code: Int, message: String) {
        let payload = (try? JSONSerialization.data(withJSONObject: ["code": code, "message": message])) ?? Data()
        onEvent?(.received(DiscordIPCFrame(opcode: .close, payload: payload)))
    }

    /// The socket going away with no reason given — Discord quitting.
    func dropConnection() {
        let onEvent = self.onEvent
        self.onEvent = nil
        onEvent?(.closed)
    }

    func deliver(_ message: [String: Any]) {
        guard let payload = try? JSONSerialization.data(withJSONObject: message) else { return }
        onEvent?(.received(DiscordIPCFrame(opcode: .frame, payload: payload)))
    }

    private func handleCommand(_ payload: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let command = object["cmd"] as? String,
            let nonce = object["nonce"] as? String
        else { return }

        let sent = SentCommand(
            command: command,
            arguments: object["args"] as? [String: Any] ?? [:],
            event: object["evt"] as? String,
            nonce: nonce
        )
        sentCommands.append(sent)

        switch respond(sent) {
        case .data(let data):
            deliver(["cmd": command, "nonce": nonce, "data": data ?? NSNull()])
        case .error(let code, let message):
            deliver(["cmd": command, "evt": "ERROR", "nonce": nonce, "data": ["code": code, "message": message]])
        case .silence:
            break
        }
    }
}

final class FakeDiscordTokenExchange: DiscordTokenExchanging, @unchecked Sendable {
    enum Outcome {
        case credentials(DiscordCredentials)
        case rejected
        case offline
    }

    var redeemOutcome: Outcome
    var refreshOutcome: Outcome
    private(set) var redeemedCodes: [(code: String, verifier: String)] = []
    private(set) var refreshedTokens: [String] = []

    init(redeem: Outcome = .credentials(.fresh), refresh: Outcome = .credentials(.renewed)) {
        redeemOutcome = redeem
        refreshOutcome = refresh
    }

    func redeem(code: String, verifier: String, clientID: DiscordClientID) async throws -> DiscordCredentials {
        redeemedCodes.append((code, verifier))
        return try Self.resolve(redeemOutcome)
    }

    func refresh(_ refreshToken: String, clientID: DiscordClientID) async throws -> DiscordCredentials {
        refreshedTokens.append(refreshToken)
        return try Self.resolve(refreshOutcome)
    }

    private static func resolve(_ outcome: Outcome) throws -> DiscordCredentials {
        switch outcome {
        case .credentials(let credentials): return credentials
        case .rejected: throw DiscordTokenExchangeError.rejected(status: 400, reason: "invalid_grant")
        case .offline: throw URLError(.notConnectedToInternet)
        }
    }
}

@MainActor
final class FakeDiscordCredentialStore: DiscordCredentialStoring {
    var stored: [DiscordClientID: DiscordCredentials] = [:]
    private(set) var deletions = 0

    func credentials(for clientID: DiscordClientID) async -> DiscordCredentials? {
        stored[clientID]
    }

    func save(_ credentials: DiscordCredentials, for clientID: DiscordClientID) async {
        stored[clientID] = credentials
    }

    func deleteCredentials(for clientID: DiscordClientID) async {
        deletions += 1
        stored[clientID] = nil
    }
}

@MainActor
final class FakeDiscordReconnectScheduler: DiscordReconnectScheduling {
    private(set) var scheduledDelays: [Duration] = []
    private var pending: (@MainActor () -> Void)?

    var hasPendingAttempt: Bool { pending != nil }

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        scheduledDelays.append(delay)
        pending = action
    }

    func cancel() {
        pending = nil
    }

    func fire() {
        let action = pending
        pending = nil
        action?()
    }
}

@MainActor
final class FakeDiscordWorkspace: DiscordWorkspaceObserving {
    var isDiscordInstalled = true
    private var onLaunch: (@MainActor () -> Void)?

    var isObservingLaunches: Bool { onLaunch != nil }

    func startObservingLaunches(_ onLaunch: @escaping @MainActor () -> Void) {
        self.onLaunch = onLaunch
    }

    func stopObservingLaunches() {
        onLaunch = nil
    }

    func launchDiscord() {
        onLaunch?()
    }
}

extension DiscordCredentials {
    static let fresh = DiscordCredentials(
        accessToken: "fresh-access",
        refreshToken: "fresh-refresh",
        expiresAt: Date(timeIntervalSinceReferenceDate: 7 * 24 * 60 * 60)
    )
    static let renewed = DiscordCredentials(
        accessToken: "renewed-access",
        refreshToken: "renewed-refresh",
        expiresAt: Date(timeIntervalSinceReferenceDate: 14 * 24 * 60 * 60)
    )
}

extension DiscordClientID {
    static let testApplication = DiscordClientID(rawValue: "1549389234912239636")!
}

/// Lets every task the session started on the main actor run to its next
/// suspension. The fakes answer synchronously, so a handful of turns drains any
/// chain of commands without a timer.
@MainActor
func settleDiscordTasks() async {
    for _ in 0..<50 {
        await Task.yield()
    }
}
