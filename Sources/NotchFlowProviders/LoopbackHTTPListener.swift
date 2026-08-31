import Foundation
import Network
import NotchFlowCore

public typealias LoopbackMessageSink = @MainActor @Sendable (IPCMessage) -> Void

public struct LoopbackHTTPListenerConfiguration: Sendable {
    public let discoveryFileURL: URL
    public let policyConfiguration: LoopbackListenerPolicyConfiguration

    public init(
        discoveryFileURL: URL = Self.defaultDiscoveryFileURL,
        policyConfiguration: LoopbackListenerPolicyConfiguration = .init()
    ) {
        self.discoveryFileURL = discoveryFileURL
        self.policyConfiguration = policyConfiguration
    }

    public static var defaultDiscoveryFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchFlow", isDirectory: true)
            .appendingPathComponent("ipc-port")
    }
}

public enum LoopbackHTTPListenerError: Error, Equatable, Sendable {
    case missingBoundPort
    case failedToStart(String)
}

public actor LoopbackHTTPListener {
    private let configuration: LoopbackHTTPListenerConfiguration
    private let sink: LoopbackMessageSink
    private let queue = DispatchQueue(label: "com.notchflow.loopback-listener")
    private var policy: LoopbackListenerPolicy
    private var listener: NWListener?
    private var boundPort: UInt16?
    private var preferences: AIIntegrationPreferences = .default
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    public init(
        configuration: LoopbackHTTPListenerConfiguration = .init(),
        sink: @escaping LoopbackMessageSink
    ) {
        self.configuration = configuration
        self.sink = sink
        self.policy = LoopbackListenerPolicy(
            configuration: configuration.policyConfiguration
        )
    }

    /// The socket's lifetime tracks the enabled *agents* only. Event-class
    /// switches change what the policy accepts, never whether the port exists:
    /// a user who silences every event class still has agents enabled, and
    /// tearing the socket down under them would break the hooks they installed.
    @discardableResult
    public func updatePreferences(_ preferences: AIIntegrationPreferences) async throws -> UInt16? {
        self.preferences = preferences
        policy.updatePreferences(preferences)
        guard !preferences.enabledAgentIDs.isEmpty else {
            await stop()
            return nil
        }
        if let boundPort {
            return boundPort
        }
        return try await start()
    }

    public func stop() async {
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        boundPort = nil

        let openConnections = connections.values
        connections.removeAll()
        for connection in openConnections {
            connection.cancel()
        }

        try? FileManager.default.removeItem(at: configuration.discoveryFileURL)
    }

    private func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }

        do {
            let port = try await waitUntilReady(listener)
            guard !preferences.enabledAgentIDs.isEmpty, self.listener === listener else {
                throw LoopbackHTTPListenerError.failedToStart(
                    "Listener was disabled before startup completed"
                )
            }
            try publish(port)
            boundPort = port
            return port
        } catch {
            await stop()
            throw error
        }
    }

    private func waitUntilReady(_ listener: NWListener) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let startup = ListenerStartup(continuation)
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    guard let port = listener?.port else {
                        startup.fail(.missingBoundPort)
                        return
                    }
                    startup.succeed(port.rawValue)
                case .failed(let error):
                    startup.fail(.failedToStart(error.localizedDescription))
                case .cancelled:
                    startup.fail(.failedToStart("Listener was cancelled before becoming ready"))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func publish(_ port: UInt16) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: configuration.discoveryFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("\(port)\n".utf8).write(
            to: configuration.discoveryFileURL,
            options: .atomic
        )
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else {
            connection.cancel()
            return
        }
        connections[ObjectIdentifier(connection)] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard case .failed = state, let connection else { return }
            Task { await self?.close(connection) }
        }
        connection.start(queue: queue)
        receive(on: connection, parser: LoopbackHTTPRequestParser())
    }

    private func receive(on connection: NWConnection, parser: LoopbackHTTPRequestParser) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) {
            [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            Task {
                await self.received(
                    ConnectionRead(
                        connection: connection,
                        parser: parser,
                        data: data,
                        isComplete: isComplete,
                        error: error
                    )
                )
            }
        }
    }

    private func received(_ read: ConnectionRead) async {
        guard read.error == nil else {
            close(read.connection)
            return
        }

        var parser = read.parser
        let result = parser.append(read.data ?? Data())
        switch result {
        case .incomplete where !read.isComplete:
            receive(on: read.connection, parser: parser)
        case .incomplete:
            respond(status: 400, on: read.connection)
        case .rejected(let reason):
            respond(status: Self.status(for: reason), on: read.connection)
        case .request(let request):
            await handle(request, on: read.connection)
        }
    }

    private func handle(_ request: LoopbackHTTPRequest, on connection: NWConnection) async {
        if let rejection = policy.rejection(method: request.method, path: request.path) {
            respond(status: Self.status(for: rejection), on: connection)
            return
        }

        switch policy.evaluate(request.body) {
        case .accepted(let message):
            await sink(message)
            respond(status: 204, on: connection)
        case .ignored:
            respond(status: 204, on: connection)
        case .rejected(let rejection):
            respond(status: Self.status(for: rejection), on: connection)
        }
    }

    private func respond(status: Int, on connection: NWConnection) {
        let reason = Self.reasonPhrase(for: status)
        let response = Data(
            "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8
        )
        connection.send(
            content: response,
            completion: .contentProcessed { [weak self, weak connection] _ in
                guard let self, let connection else { return }
                Task { await self.close(connection) }
            })
    }

    private func close(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    private static func status(for rejection: LoopbackListenerRejection) -> Int {
        switch rejection {
        case .routeNotFound: 404
        case .methodNotAllowed: 405
        case .payloadTooLarge: 413
        case .invalidPayload: 400
        case .rateLimited: 429
        }
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 204: "No Content"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Content Too Large"
        case 429: "Too Many Requests"
        default: "Error"
        }
    }
}

private final class ListenerStartup: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func succeed(_ port: UInt16) {
        resume(with: .success(port))
    }

    func fail(_ error: LoopbackHTTPListenerError) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<UInt16, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private struct ConnectionRead: @unchecked Sendable {
    let connection: NWConnection
    let parser: LoopbackHTTPRequestParser
    let data: Data?
    let isComplete: Bool
    let error: NWError?
}
