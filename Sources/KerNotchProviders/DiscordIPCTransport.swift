import Foundation
import Network
import os

/// What happened on an IPC connection, delivered on the main actor.
enum DiscordIPCTransportEvent: Equatable, Sendable {
    case opened
    case received(DiscordIPCFrame)
    /// The connection is gone, or never came up. Terminal: nothing more is
    /// delivered after it.
    case closed
}

/// A byte pipe to one Discord IPC socket, behind a protocol so the RPC client's
/// handshake and correlation logic is testable without Discord running.
@MainActor
protocol DiscordIPCTransport: AnyObject {
    func open(socketPath: String, onEvent: @escaping @MainActor (DiscordIPCTransportEvent) -> Void)
    func send(_ frame: DiscordIPCFrame)
    func close()
}

/// Where a running Discord client listens, per Discord's IPC convention:
/// `discord-ipc-0` through `discord-ipc-9` in the first of the runtime or
/// temporary directories the environment names.
enum DiscordIPCSocketLocator {
    private static let socketIndexes = 0...9
    private static let directoryVariables = ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"]
    private static let fallbackDirectory = "/tmp"

    /// Every path worth trying, most likely first. KerNotch is unsandboxed, so
    /// its `TMPDIR` is the same per-user directory Discord's is.
    static func candidatePaths(environment: [String: String]) -> [String] {
        var directories: [String] = []
        for variable in directoryVariables {
            guard let directory = environment[variable], directory.isEmpty == false else { continue }
            directories.append(directory)
        }
        directories.append(fallbackDirectory)

        var seen = Set<String>()
        let uniqueDirectories = directories.filter { seen.insert(standardized($0)).inserted }

        return uniqueDirectories.flatMap { directory in
            socketIndexes.map { (directory as NSString).appendingPathComponent("discord-ipc-\($0)") }
        }
    }

    /// The candidates that exist right now. A missing file is not a socket, and
    /// skipping it avoids a connection attempt per absent path.
    static func existingSocketPaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [String] {
        candidatePaths(environment: environment).filter(fileExists)
    }

    private static func standardized(_ directory: String) -> String {
        (directory as NSString).standardizingPath
    }
}

/// The production transport: a Network.framework stream connection to a Unix
/// domain socket.
///
/// Reads are a chain of one-shot receives, each armed by the previous one's
/// completion, so an idle connection costs a parked socket and no wakeups.
@MainActor
final class UnixSocketDiscordIPCTransport: DiscordIPCTransport {
    private static let logger = Logger(subsystem: "com.kernotch.KerNotch", category: "discord-ipc")
    private static let maximumReadLength = 64 * 1024

    private let queue = DispatchQueue(label: "com.kernotch.discord-ipc")
    private var connection: NWConnection?
    private var decoder = DiscordIPCFrameDecoder()
    private var onEvent: (@MainActor (DiscordIPCTransportEvent) -> Void)?

    func open(socketPath: String, onEvent: @escaping @MainActor (DiscordIPCTransportEvent) -> Void) {
        close()
        self.onEvent = onEvent
        decoder = DiscordIPCFrameDecoder()

        let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                self.handle(state, of: connection)
            }
        }
        connection.start(queue: queue)
    }

    func send(_ frame: DiscordIPCFrame) {
        connection?.send(content: frame.encoded, completion: .idempotent)
    }

    func close() {
        onEvent = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func handle(_ state: NWConnection.State, of connection: NWConnection) {
        switch state {
        case .ready:
            onEvent?(.opened)
            receive(on: connection)
        // `waiting` is Network.framework offering to retry on its own when the
        // path changes. For a local socket that is not there, that retry is a
        // hidden loop; the caller decides when to try again instead.
        case .waiting(let error), .failed(let error):
            Self.logger.debug("Discord IPC connection ended: \(error.localizedDescription, privacy: .public)")
            finish()
        case .cancelled:
            finish()
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumReadLength) {
            [weak self, weak connection] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                self.handleReceive(data: data, isComplete: isComplete, failed: error != nil, on: connection)
            }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, failed: Bool, on connection: NWConnection) {
        if let data, data.isEmpty == false {
            do {
                for frame in try decoder.append(data) {
                    // A frame handler can close this connection and open the
                    // next one before the loop ends. Whatever is left belongs
                    // to the closed connection, and must not reach — or tear
                    // down — its replacement.
                    guard self.connection === connection else { return }
                    onEvent?(.received(frame))
                }
            } catch {
                let reason = String(describing: error)
                Self.logger.error("Discarding a Discord IPC stream that failed to decode: \(reason, privacy: .public)")
                finish()
                return
            }
        }

        guard self.connection === connection else { return }
        guard isComplete == false, failed == false else {
            finish()
            return
        }
        receive(on: connection)
    }

    private func finish() {
        let onEvent = self.onEvent
        close()
        onEvent?(.closed)
    }
}
