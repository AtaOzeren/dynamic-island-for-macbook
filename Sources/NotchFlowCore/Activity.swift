import Foundation

public protocol Activity: Sendable {
    var identity: ActivityIdentity { get }
    var kind: ActivityKind { get }
    var priority: ActivityPriority { get }
    var autoDismiss: AutoDismissDescriptor? { get }
    var primaryAction: PrimaryAction? { get }
}

public extension Activity {
    var autoDismiss: AutoDismissDescriptor? { nil }

    /// An activity with no primary action is inert to clicks beyond the panel's
    /// own expand and collapse, per `docs/05-activity-model.md`.
    var primaryAction: PrimaryAction? { nil }
}
