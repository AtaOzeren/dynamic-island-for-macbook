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

/// Which block of the list an activity belongs to, before priority is consulted.
///
/// Distinct from `ActivityPriority`, which answers "how urgent is this" and
/// decides whether the panel may open itself. This answers "where does it sit",
/// and it is the stronger of the two: what is playing and what is recording stay
/// at the top of the island however long an agent has been running underneath
/// them. Sorting those by urgency alone put a finished agent above the track the
/// user was listening to, because the agent was the more urgent thing to say and
/// the list had no way to express "and yet, not first".
public enum ActivityOrderBand: Int, CaseIterable, Sendable {
    /// Media and capture: the now-playing track, the screen or microphone
    /// recording. Always above everything else.
    case pinned = 1
    case standard = 0
}

extension ActivityOrderBand: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue > rhs.rawValue
    }
}

public struct ActivityOrderingKey: Equatable, Sendable {
    public let band: ActivityOrderBand
    public let priority: ActivityPriority
    public let startTime: Date

    public init(
        band: ActivityOrderBand = .standard,
        priority: ActivityPriority,
        startTime: Date
    ) {
        self.band = band
        self.priority = priority
        self.startTime = startTime
    }
}

extension ActivityOrderingKey: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.band != rhs.band {
            return lhs.band < rhs.band
        }
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }

        return lhs.startTime < rhs.startTime
    }
}
