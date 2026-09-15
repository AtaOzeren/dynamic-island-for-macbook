import Foundation

/// The island's own account of a watchdog episode the user did not witness,
/// shown once on the launch that follows a self-restart or a self-quit.
///
/// It is an activity rather than a bespoke panel because the island already
/// knows how to say something briefly and then stop: the announcement window
/// takes it off the pill, and auto-dismiss takes it out of the model. A notice
/// with neither would sit in the island until the next relaunch, which is how a
/// one-off explanation becomes furniture.
public struct WatchdogNoticeActivity: Activity, Equatable {
    /// Long enough to notice and read after coming back to the machine, and
    /// gone before it competes with real activity for the pill.
    public static let announcementWindow: TimeInterval = 20
    public static let autoDismissAfter: Duration = .seconds(30)

    public let didRelaunch: Bool

    public init(didRelaunch: Bool) {
        self.didRelaunch = didRelaunch
    }

    /// One identity for the notice as such: two markers cannot be consumed on
    /// one launch, and if that ever changed the second must replace the first
    /// rather than stack beside it.
    public var identity: ActivityIdentity { ActivityIdentity("watchdog-notice") }
    public var kind: ActivityKind { .watchdogNotice }
    /// Above ordinary work: it explains why everything else on the island is
    /// missing, which is only useful while the user is still wondering.
    public var priority: ActivityPriority { .high }
    public var compactRepresentationPriority: CompactRepresentationPriority { .attention }
    public var compactAnnouncementWindow: TimeInterval? { Self.announcementWindow }
    public var autoDismiss: AutoDismissDescriptor? {
        AutoDismissDescriptor(after: Self.autoDismissAfter)
    }
}
