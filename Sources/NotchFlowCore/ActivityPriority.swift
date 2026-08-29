import Foundation

public enum ActivityPriority: Int, CaseIterable, Sendable {
    case critical = 3
    case high = 2
    case normal = 1
    case low = 0
}

extension ActivityPriority: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue > rhs.rawValue
    }
}

public struct ActivityOrderingKey: Equatable, Sendable {
    public let priority: ActivityPriority
    public let startTime: Date

    public init(priority: ActivityPriority, startTime: Date) {
        self.priority = priority
        self.startTime = startTime
    }
}

extension ActivityOrderingKey: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }

        return lhs.startTime < rhs.startTime
    }
}
