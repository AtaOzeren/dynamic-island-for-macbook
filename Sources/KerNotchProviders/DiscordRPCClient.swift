import Foundation
import KerNotchCore

/// What the RPC connection reports outside of command replies.
enum DiscordRPCClientEvent: Sendable {
    /// The handshake was accepted. Commands can be sent from here on.
    case ready(username: String?)
    /// An event KerNotch subscribed to, with its raw message for the subscriber
    /// to decode.
    case dispatch(DiscordRPCEvent, Data)
    /// The connection ended, with Discord's reason when it gave one. Terminal.
    case closed(DiscordRPCError?)
}

/// Discord's RPC protocol over one IPC connection: the handshake, answering
/// pings, matching replies to the commands that asked for them, and handing
/// subscribed events on.
///
/// Commands are `async` and correlate by nonce. There are no timeouts: a reply
/// can legitimately take as long as the user takes to answer an authorization
/// prompt, and a connection that dies fails every pending command at once, so
/// nothing is left waiting on a timer that would only add wakeups.
@MainActor
final class DiscordRPCClient {
    private static let protocolVersion = 1

    static let connectionClosed = DiscordRPCError(code: -1, message: "The Discord connection closed.")
    /// Discord answered with an error KerNotch could not read. Kept apart from
    /// `connectionClosed`, which callers treat as "nothing to report".
    static let malformedReply = DiscordRPCError(code: -2, message: "Discord sent a reply that could not be read.")

    private let transport: any DiscordIPCTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var pending: [String: CheckedContinuation<Data, any Error>] = [:]
    private var lastNonce: UInt64 = 0
    private var closeReason: DiscordRPCError?
    private var onEvent: (@MainActor (DiscordRPCClientEvent) -> Void)?

    init(transport: any DiscordIPCTransport) {
        self.transport = transport
    }

    func connect(
        socketPath: String,
        clientID: DiscordClientID,
        onEvent: @escaping @MainActor (DiscordRPCClientEvent) -> Void
    ) {
        disconnect()
        self.onEvent = onEvent
        closeReason = nil

        transport.open(socketPath: socketPath) { [weak self] event in
            self?.handle(event, clientID: clientID)
        }
    }

    /// Ends the connection without reporting `closed`: whoever disconnects
    /// already knows. Pending commands fail.
    func disconnect() {
        onEvent = nil
        transport.close()
        failPendingCommands()
    }

    /// Sends a command and returns its reply's `data`, decoded.
    func request<Body: Decodable>(
        _ command: DiscordRPCCommand,
        arguments: some Encodable & Sendable = DiscordNoArguments(),
        event: DiscordRPCEvent? = nil,
        returning _: Body.Type
    ) async throws -> Body {
        let reply = try await send(command, arguments: arguments, event: event)
        return try decoder.decode(DiscordRPCPayload<Body>.self, from: reply).data
    }

    /// Sends a command whose reply carries nothing KerNotch reads.
    func perform(
        _ command: DiscordRPCCommand,
        arguments: some Encodable & Sendable = DiscordNoArguments(),
        event: DiscordRPCEvent? = nil
    ) async throws {
        _ = try await send(command, arguments: arguments, event: event)
    }

    private func send(
        _ command: DiscordRPCCommand,
        arguments: some Encodable & Sendable,
        event: DiscordRPCEvent?
    ) async throws -> Data {
        guard onEvent != nil else { throw Self.connectionClosed }

        lastNonce += 1
        let nonce = "kernotch-\(lastNonce)"
        let message = DiscordOutgoingCommand(
            cmd: command.rawValue,
            args: arguments,
            evt: event?.rawValue,
            nonce: nonce
        )
        let payload = try encoder.encode(message)

        return try await withCheckedThrowingContinuation { continuation in
            pending[nonce] = continuation
            transport.send(DiscordIPCFrame(opcode: .frame, payload: payload))
        }
    }

    private func handle(_ event: DiscordIPCTransportEvent, clientID: DiscordClientID) {
        switch event {
        case .opened:
            sendHandshake(clientID: clientID)
        case .received(let frame):
            handle(frame)
        case .closed:
            reportClosed()
        }
    }

    private func reportClosed() {
        let onEvent = self.onEvent
        self.onEvent = nil
        failPendingCommands()
        onEvent?(.closed(closeReason))
    }

    private func sendHandshake(clientID: DiscordClientID) {
        guard let payload = try? encoder.encode(DiscordHandshake(v: Self.protocolVersion, clientID: clientID.rawValue))
        else { return }
        transport.send(DiscordIPCFrame(opcode: .handshake, payload: payload))
    }

    private func handle(_ frame: DiscordIPCFrame) {
        switch frame.opcode {
        case .ping:
            transport.send(DiscordIPCFrame(opcode: .pong, payload: frame.payload))
        case .close:
            closeReason = try? decoder.decode(DiscordRPCErrorBody.self, from: frame.payload).asError
            transport.close()
            reportClosed()
        case .frame:
            handleMessage(frame.payload)
        case .handshake, .pong:
            break
        }
    }

    private func handleMessage(_ payload: Data) {
        guard let envelope = try? decoder.decode(DiscordRPCEnvelope.self, from: payload) else { return }

        if let nonce = envelope.nonce, let continuation = pending.removeValue(forKey: nonce) {
            if envelope.evt == DiscordRPCEvent.error.rawValue {
                let error = (try? decoder.decode(DiscordRPCPayload<DiscordRPCErrorBody>.self, from: payload))?.data
                continuation.resume(throwing: error?.asError ?? Self.malformedReply)
            } else {
                continuation.resume(returning: payload)
            }
            return
        }

        guard
            envelope.cmd == DiscordRPCCommand.dispatch.rawValue,
            let name = envelope.evt,
            let event = DiscordRPCEvent(rawValue: name)
        else { return }

        if event == .ready {
            let ready = try? decoder.decode(DiscordRPCPayload<DiscordReadyBody>.self, from: payload)
            onEvent?(.ready(username: ready?.data.user?.username))
        } else {
            onEvent?(.dispatch(event, payload))
        }
    }

    private func failPendingCommands() {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: Self.connectionClosed)
        }
    }
}

struct DiscordNoArguments: Encodable, Sendable {}

private struct DiscordHandshake: Encodable {
    let v: Int
    let clientID: String

    private enum CodingKeys: String, CodingKey {
        case v
        case clientID = "client_id"
    }
}

private struct DiscordOutgoingCommand<Arguments: Encodable>: Encodable {
    let cmd: String
    let args: Arguments
    let evt: String?
    let nonce: String
}

extension DiscordRPCErrorBody {
    fileprivate var asError: DiscordRPCError {
        DiscordRPCError(code: code, message: message)
    }
}
