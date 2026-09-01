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
    private struct Acceptance {
        let state: AIAgentState
        let date: Date
    }

    private var preferences: AIIntegrationPreferences
    private let configuration: LoopbackListenerPolicyConfiguration
    private var lastAcceptanceBySessionID: [UUID: Acceptance] = [:]

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
        // The limiter exists to absorb a chatty agent repeating one state, not to
        // thin out a session's timeline. A *changed* state is never dropped: a
        // fast tool call can put `completed` within a few milliseconds of the
        // `working` before it, and dropping that leaves the island showing an
        // agent that finished minutes ago as still running.
        let now = configuration.now()
        if let last = lastAcceptanceBySessionID[message.sessionId],
            last.state == message.state,
            now.timeIntervalSince(last.date) < configuration.minimumInterval
        {
            return .rejected(.rateLimited)
        }

        lastAcceptanceBySessionID[message.sessionId] = Acceptance(
            state: message.state,
            date: now
        )
        return .accepted(message)
    }
}
