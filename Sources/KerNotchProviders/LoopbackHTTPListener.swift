import Foundation
import KerNotchCore
import Network
import os

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
            .appendingPathComponent("Library/Application Support/KerNotch", isDirectory: true)
            .appendingPathComponent("ipc-port")
    }
}

public enum LoopbackHTTPListenerError: Error, Equatable, Sendable {
    case missingBoundPort
    case failedToStart(String)
    case startupTimedOut
}

public actor LoopbackHTTPListener {
    private static let ownerOnlyFilePermissions = 0o600
    private static let ownerOnlyDirectoryPermissions = 0o700

    /// How long a listener may take to become ready before startup gives up.
    /// Binding loopback is immediate in practice; the bound exists so a listener
    /// that never reports ready cannot hold every later preference change
    /// queued behind it.
    private static let startupTimeout: DispatchTimeInterval = .seconds(5)
    private static let logger = Logger(
        subsystem: "com.kernotch.KerNotch",
        category: "loopback-listener"
    )

    private let configuration: LoopbackHTTPListenerConfiguration
    private let sink: LoopbackMessageSink
    private let queue = DispatchQueue(label: "com.kernotch.loopback-listener")
    private var policy: LoopbackListenerPolicy
    private var listener: NWListener?
    private var boundPort: UInt16?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    /// The most recently requested preference update, which the next request
    /// waits behind.
    private var latestUpdate: Task<UInt16?, any Error>?

    /// How many updates have been requested, so an update can tell whether a
    /// newer one is queued behind it.
    private var requestedUpdateCount = 0

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
    ///
    /// Updates run one at a time, in the order they were requested. Starting a
    /// listener suspends the actor until the socket is ready, and turning an
    /// agent on in Settings requests two updates at once — one for the switch,
    /// one for the hook it installs. Interleaved, the second started a second
    /// listener, the first then cancelled it while failing its own ownership
    /// check, both reported an error, and nothing was left listening.
    ///
    /// The policy follows the newest preferences immediately, so a message that
    /// arrives while an update waits its turn is judged by what the user chose
    /// last rather than by what the socket is still catching up to.
    @discardableResult
    public func updatePreferences(_ preferences: AIIntegrationPreferences) async throws -> UInt16? {
        policy.updatePreferences(preferences)
        requestedUpdateCount += 1

        let request = requestedUpdateCount
        let previousUpdate = latestUpdate
        let update = Task {
            _ = await previousUpdate?.result
            return try await apply(preferences, request: request)
        }
        latestUpdate = update
        return try await update.value
    }

    /// A startup failure is only worth reporting when no newer update is queued:
    /// the newer one either stops the socket or tries to start it again, so the
    /// failure it supersedes describes a state the user has already left.
    private func apply(_ preferences: AIIntegrationPreferences, request: Int) async throws -> UInt16? {
        guard !preferences.enabledAgentIDs.isEmpty else {
            await stop()
            return nil
        }
        if let boundPort {
            return boundPort
        }
        do {
            return try await start()
        } catch {
            guard request == requestedUpdateCount else { return nil }
            throw error
        }
    }

    public func stop() async {
        let publishedPort = boundPort

        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        boundPort = nil

        let openConnections = connections.values
        connections.removeAll()
        for connection in openConnections {
            connection.cancel()
        }

        let discoveryFileURL = configuration.discoveryFileURL
        guard FileManager.default.fileExists(atPath: discoveryFileURL.path) else {
            return
        }

        // During a relaunch the replacement instance publishes its port
        // before the old instance's terminate hook runs, so the file on
        // disk can address a live socket that must keep receiving hook
        // traffic. Removal is ownership-guarded: only a file that still
        // names this instance's port is deleted, and anything else — a
        // foreign port, unparseable bytes, or a file this instance never
        // wrote — is left for its owner.
        let fileContents = try? String(contentsOf: discoveryFileURL, encoding: .utf8)
        let filePort = fileContents.flatMap {
            UInt16($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let publishedPort, filePort == publishedPort else {
            Self.logger.notice(
                "IPC discovery file at \(discoveryFileURL.path, privacy: .public) was not published by this instance; leaving it for its owner"
            )
            return
        }

        // Read-then-remove is not atomic: a replacement could overwrite the
        // file in the microseconds between the ownership read above and the
        // removal below, and its port file would be lost. The window is
        // tiny, occurs only during relaunch, and its worst case is one
        // launch without a port file — the same damage this guard already
        // prevents in the common ordering — so a cross-process lock to close
        // it would cost more complexity than the race can ever cause.
        do {
            try FileManager.default.removeItem(at: discoveryFileURL)
        } catch let removalError {
            // Best-effort cleanup that must not derail shutdown — but a file
            // left behind keeps hooks posting to a port nothing answers, so
            // the failure is logged rather than swallowed without a trace.
            Self.logger.error(
                "Removing IPC discovery file at \(discoveryFileURL.path, privacy: .public) failed: \(String(describing: removalError), privacy: .public)"
            )
        }
    }

    /// Every failure is logged here, the listener's own creation included: the
    /// launch path discards the error, and the alert the Settings path shows
    /// deliberately names no cause, so the log is the only place a reason lands.
    private func start() async throws -> UInt16 {
        do {
            let listener = try makeListener()
            let port = try await waitUntilReady(listener)
            // Updates are serialised, so only `stop()` — termination or a
            // watchdog restart — can have replaced the listener meanwhile.
            guard self.listener === listener else {
                throw LoopbackHTTPListenerError.failedToStart(
                    "Listener was stopped before startup completed"
                )
            }
            try publish(port)
            boundPort = port
            return port
        } catch {
            Self.logger.error(
                "Loopback listener failed to start: \(String(describing: error), privacy: .public)"
            )
            await stop()
            throw error
        }
    }

    private func makeListener() throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        return listener
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
                case .waiting(let error):
                    // Network documents waiting as recoverable, so it is logged
                    // and left to either become ready or run into the timeout.
                    Self.logger.notice(
                        "Loopback listener is waiting: \(error.localizedDescription, privacy: .public)"
                    )
                default:
                    break
                }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + Self.startupTimeout) {
                startup.fail(.startupTimedOut)
            }
        }
    }

    /// Writes the bound port where a hook can find it, owner-readable only.
    ///
    /// The port is the address of a socket that accepts messages the island
    /// renders, so telling every account on the machine where it is would hand
    /// them the one thing they need to drive the notch. `.atomic` replaces the
    /// file by rename, which carries the temporary file's mode rather than any
    /// mode set on a previous copy — so the permissions are applied after the
    /// write, every write, not once at creation.
    private func publish(_ port: UInt16) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: configuration.discoveryFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.ownerOnlyDirectoryPermissions]
        )
        try Data("\(port)\n".utf8).write(
            to: configuration.discoveryFileURL,
            options: .atomic
        )
        try fileManager.setAttributes(
            [.posixPermissions: Self.ownerOnlyFilePermissions],
            ofItemAtPath: configuration.discoveryFileURL.path
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

private final class ListenerStartup: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<UInt16, Error>?>

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = OSAllocatedUnfairLock(initialState: continuation)
    }

    func succeed(_ port: UInt16) {
        resume(with: .success(port))
    }

    func fail(_ error: LoopbackHTTPListenerError) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<UInt16, Error>) {
        let continuation = continuation.withLock { continuation in
            defer { continuation = nil }
            return continuation
        }
        continuation?.resume(with: result)
    }
}

private struct ConnectionRead: Sendable {
    let connection: NWConnection
    let parser: LoopbackHTTPRequestParser
    let data: Data?
    let isComplete: Bool
    let error: NWError?
}
