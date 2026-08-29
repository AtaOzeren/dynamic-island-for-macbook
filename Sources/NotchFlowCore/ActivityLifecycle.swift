import Foundation

public enum ActivityLifecycleState: Equatable, Sendable {
    case inactive
    case active
    case ended
}

public enum ActivityLifecycleEvent: Equatable, Sendable {
    case start(at: Date)
    case update(at: Date)
    case end(at: Date)
    case autoDismissExpired(at: Date, descriptor: AutoDismissDescriptor?)
}

public struct ActivityLifecycle: Equatable, Sendable {
    public private(set) var state: ActivityLifecycleState = .inactive
    private var lastActivityAt: Date?

    public init() {}

    @discardableResult
    public mutating func apply(_ event: ActivityLifecycleEvent) -> Bool {
        switch (state, event) {
        case (.inactive, .start(let date)):
            state = .active
            lastActivityAt = date
            return true
        case (.active, .update(let date)):
            lastActivityAt = date
            return true
        case (.active, .end):
            state = .ended
            return true
        case (.active, .autoDismissExpired(let date, let descriptor)):
            return expire(at: date, descriptor: descriptor)
        default:
            return false
        }
    }

    private mutating func expire(at date: Date, descriptor: AutoDismissDescriptor?) -> Bool {
        guard let descriptor, let lastActivityAt else {
            return false
        }

        let elapsed = Duration.seconds(date.timeIntervalSince(lastActivityAt))
        guard elapsed >= descriptor.after else {
            return false
        }

        state = .ended
        return true
    }
}
