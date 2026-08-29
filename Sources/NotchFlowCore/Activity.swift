import Foundation

public protocol Activity: Sendable {
    var identity: ActivityIdentity { get }
    var kind: ActivityKind { get }
    var priority: ActivityPriority { get }
    var autoDismiss: AutoDismissDescriptor? { get }
}

public extension Activity {
    var autoDismiss: AutoDismissDescriptor? { nil }
}
