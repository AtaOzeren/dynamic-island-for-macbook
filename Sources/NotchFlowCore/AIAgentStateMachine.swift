import Foundation

public enum AIAgentState: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case idle
    case thinking
    case working
    case usingTool
    case waitingForUser
    case completed
    case error
}

public enum AIAgentTransitionOutcome: Equatable, Sendable {
    case applied
    case coalesced
    case rejected
}

public struct AIAgentStateMachine: Equatable, Sendable {
    public private(set) var state: AIAgentState
    public private(set) var lastTransitionAt: Date?
    public private(set) var autoDismissAt: Date?

    private let duplicateCoalescingInterval: TimeInterval
    private let completedAutoDismissAfter: TimeInterval

    public init(
        initialState: AIAgentState = .idle,
        duplicateCoalescingInterval: TimeInterval = 1,
        completedAutoDismissAfter: TimeInterval = 5
    ) {
        precondition(duplicateCoalescingInterval >= 0)
        precondition(completedAutoDismissAfter >= 0)
        state = initialState
        lastTransitionAt = nil
        autoDismissAt = nil
        self.duplicateCoalescingInterval = duplicateCoalescingInterval
        self.completedAutoDismissAfter = completedAutoDismissAfter
    }

    @discardableResult
    public mutating func transition(to destination: AIAgentState, at date: Date) -> AIAgentTransitionOutcome {
        if destination == state {
            return applyDuplicateUpdate(at: date)
        }
        guard state.canTransition(to: destination) else {
            return .rejected
        }

        state = destination
        lastTransitionAt = date
        autoDismissAt = destination == .completed
            ? date.addingTimeInterval(completedAutoDismissAfter)
            : nil
        return .applied
    }

    @discardableResult
    public mutating func expire(at date: Date) -> Bool {
        guard let autoDismissAt, date >= autoDismissAt else {
            return false
        }

        state = .idle
        lastTransitionAt = date
        self.autoDismissAt = nil
        return true
    }

    private mutating func applyDuplicateUpdate(at date: Date) -> AIAgentTransitionOutcome {
        guard let lastTransitionAt,
              date.timeIntervalSince(lastTransitionAt) < duplicateCoalescingInterval else {
            self.lastTransitionAt = date
            if state == .completed {
                autoDismissAt = date.addingTimeInterval(completedAutoDismissAfter)
            }
            return .applied
        }
        return .coalesced
    }
}

private extension AIAgentState {
    func canTransition(to destination: AIAgentState) -> Bool {
        switch self {
        case .idle:
            destination == .thinking
        case .thinking:
            [.working, .usingTool, .waitingForUser, .completed, .error].contains(destination)
        case .working:
            [.thinking, .usingTool, .waitingForUser, .completed, .error].contains(destination)
        case .usingTool:
            [.thinking, .working, .waitingForUser, .completed, .error].contains(destination)
        case .waitingForUser:
            [.thinking, .completed, .error].contains(destination)
        case .completed, .error:
            [.idle, .thinking].contains(destination)
        }
    }
}
