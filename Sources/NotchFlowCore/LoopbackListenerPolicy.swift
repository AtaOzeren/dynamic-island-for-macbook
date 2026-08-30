import Foundation

public struct LoopbackListenerPolicyConfiguration: Sendable {
    public let minimumInterval: TimeInterval
    public let now: @Sendable () -> Date

    public init(
        minimumInterval: TimeInterval = 0.1,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.minimumInterval = max(0, minimumInterval)
        self.now = now
    }
}

public enum LoopbackListenerRejection: Equatable, Sendable {
    case routeNotFound
    case methodNotAllowed
    case payloadTooLarge
    case invalidPayload
    case rateLimited
}

public enum LoopbackListenerDecision: Equatable, Sendable {
    case accepted(IPCMessage)
    case ignored
    case rejected(LoopbackListenerRejection)

    public var isAccepted: Bool {
        if case .accepted = self {
            return true
        }
        return false
    }
}

public struct LoopbackListenerPolicy: Sendable {
    private var preferences: AIIntegrationPreferences
    private let configuration: LoopbackListenerPolicyConfiguration
    private var lastAcceptedAtBySessionID: [UUID: Date] = [:]

    public init(
        preferences: AIIntegrationPreferences = .default,
        configuration: LoopbackListenerPolicyConfiguration = .init()
    ) {
        self.preferences = preferences
        self.configuration = configuration
    }

    public mutating func updatePreferences(_ preferences: AIIntegrationPreferences) {
        self.preferences = preferences
    }

    public func rejection(method: String, path: String) -> LoopbackListenerRejection? {
        guard path == "/ai-status" else {
            return .routeNotFound
        }
        guard method == "POST" else {
            return .methodNotAllowed
        }
        return nil
    }

    public mutating func evaluate(_ body: Data) -> LoopbackListenerDecision {
        guard body.count <= IPCMessageValidator.maximumPayloadByteCount else {
            return .rejected(.payloadTooLarge)
        }

        let message: IPCMessage
        do {
            message = try IPCMessageValidator().decode(body)
        } catch IPCMessageValidationError.disallowedAgentId {
            return .ignored
        } catch {
            return .rejected(.invalidPayload)
        }

        // Ahead of the rate limiter on purpose: a silenced event must not
        // consume its session's budget, or a stream of `usingTool` messages
        // would starve the `completed` message the user did ask to see.
        guard preferences.allows(message) else {
            return .ignored
        }
        let now = configuration.now()
        if let lastAcceptedAt = lastAcceptedAtBySessionID[message.sessionId],
            now.timeIntervalSince(lastAcceptedAt) < configuration.minimumInterval
        {
            return .rejected(.rateLimited)
        }

        lastAcceptedAtBySessionID[message.sessionId] = now
        return .accepted(message)
    }
}
