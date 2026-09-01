import Foundation

public protocol Activity: Sendable {
    var identity: ActivityIdentity { get }
    var compactGroupIdentity: ActivityIdentity { get }
    var compactRepresentationPriority: CompactRepresentationPriority { get }
    var kind: ActivityKind { get }
    var priority: ActivityPriority { get }
    var autoDismiss: AutoDismissDescriptor? { get }
    var primaryAction: PrimaryAction? { get }
}

extension Activity {
    public var compactGroupIdentity: ActivityIdentity { identity }
    public var compactRepresentationPriority: CompactRepresentationPriority { .active }
    public var autoDismiss: AutoDismissDescriptor? { nil }

    /// An activity with no primary action is inert to clicks beyond the panel's
    /// own expand and collapse, per `docs/05-activity-model.md`.
    public var primaryAction: PrimaryAction? { nil }
}

public enum CompactRepresentationPriority: Int, Comparable, Sendable {
    case passive
    case active
    case attention
    case failure

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
