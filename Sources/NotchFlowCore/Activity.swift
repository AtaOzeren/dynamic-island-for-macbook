import Foundation

public protocol Activity: Sendable {
    var identity: ActivityIdentity { get }
    var compactGroupIdentity: ActivityIdentity { get }
    /// What the compact group's count badge tallies. Activities sharing one
    /// count once.
    ///
    /// Separate from `compactGroupIdentity` because a group's icon and a group's
    /// count answer different questions. An AI agent's icon covers every session
    /// of that agent, but the number beside it has to be the number of *things
    /// the user started* — a session an agent spawned to delegate work is not a
    /// second agent running, and counting it as one turns "OpenCode ×1" into
    /// "OpenCode ×5" the moment a sub-agent fans out.
    var compactInstanceIdentity: ActivityIdentity { get }
    var compactRepresentationPriority: CompactRepresentationPriority { get }
    var compactRegion: CompactActivityRegion { get }
    var kind: ActivityKind { get }
    var priority: ActivityPriority { get }
    var orderBand: ActivityOrderBand { get }
    var autoDismiss: AutoDismissDescriptor? { get }
    var primaryAction: PrimaryAction? { get }
}

extension Activity {
    public var compactGroupIdentity: ActivityIdentity { identity }
    /// An ungrouped activity is its own instance: one icon, one thing, count one.
    public var compactInstanceIdentity: ActivityIdentity { identity }
    public var compactRepresentationPriority: CompactRepresentationPriority { .active }
    public var compactRegion: CompactActivityRegion { .standard }
    /// Most activities queue by urgency alone. Only media and capture pin
    /// themselves above that.
    public var orderBand: ActivityOrderBand { .standard }
    public var autoDismiss: AutoDismissDescriptor? { nil }

    /// An activity with no primary action is inert to clicks beyond the panel's
    /// own expand and collapse, per `docs/05-activity-model.md`.
    public var primaryAction: PrimaryAction? { nil }
}

public enum CompactActivityRegion: Sendable {
    case standard
    case agentTrailing
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
