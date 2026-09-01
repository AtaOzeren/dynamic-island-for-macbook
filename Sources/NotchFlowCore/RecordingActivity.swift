import Foundation

/// Which capture the indicator is reporting.
///
/// The two sources share one `ActivityKind` but never one identity: a screen
/// recording and a microphone recording are concurrent facts about the machine,
/// so collapsing them onto a single identity would let one silently replace the
/// other in the island.
public enum RecordingSource: Hashable, Sendable {
    case screen
    case audio
}

/// A capture the system reports as in progress, with the time it has been
/// running, per `docs/06-activity-providers.md`.
///
/// Elapsed time is derived from the session's start timestamp rather than
/// accumulated from ticks, for the same reason `TimerActivity` derives its own:
/// a recording that ran for an hour behind a hidden panel is correct on the
/// first frame after the panel reappears, so the display refresh can be
/// suspended without the count drifting.
///
/// The activity says *that* a recording is running and never *which app* is
/// running it — the public signal in `docs/12-api-feasibility-matrix.md` does
/// not attribute a recorder, and inventing an attribution would be a lie the
/// user cannot check.
public struct RecordingActivity: Activity, Equatable {
    public let source: RecordingSource
    /// When the system began reporting this capture.
    public let startedAt: Date
    /// The instant this value describes; every derived quantity is relative to
    /// it, so two values compare equal across a tick only when the displayed
    /// time is unchanged.
    public let date: Date

    public init(source: RecordingSource, startedAt: Date, at date: Date) {
        self.source = source
        self.startedAt = startedAt
        self.date = date
    }

    public static func started(_ source: RecordingSource, at date: Date) -> Self {
        Self(source: source, startedAt: date, at: date)
    }

    /// One identity per source, stable for the life of the session, so a tick
    /// updates the existing activity instead of re-registering it and
    /// re-sorting the island every second.
    public static func identity(for source: RecordingSource) -> ActivityIdentity {
        switch source {
        case .screen: ActivityIdentity("notchflow.recording.screen")
        case .audio: ActivityIdentity("notchflow.recording.audio")
        }
    }

    public var identity: ActivityIdentity { Self.identity(for: source) }

    public var kind: ActivityKind { .recording }

    /// `high`, and never auto-dismissing: per `docs/06-activity-providers.md`
    /// an extra always-on indicator is the cheaper failure than silently
    /// missing that something is being recorded.
    /// A live camera or microphone belongs at the top whatever else is running.
    /// It is the card that answers "is something capturing me right now".
    public var orderBand: ActivityOrderBand { .pinned }

    public var priority: ActivityPriority { .high }

    public var autoDismiss: AutoDismissDescriptor? { nil }

    /// How long the capture has been running, as of `date`.
    ///
    /// Clamped at zero so a clock that jumps backwards — an NTP correction
    /// mid-recording — reports a stalled counter rather than a negative one.
    public var elapsed: Duration {
        let running = Duration.seconds(date.timeIntervalSince(startedAt))
        return running > .zero ? running : .zero
    }

    /// The same session, re-read at a later instant. The start timestamp is
    /// carried through untouched, which is what makes the count independent of
    /// how often this is called.
    public func advanced(to date: Date) -> Self {
        Self(source: source, startedAt: startedAt, at: date)
    }
}
