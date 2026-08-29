import Foundation
import NotchFlowCore

/// A screen capture the system is reporting as in progress.
///
/// It carries only a start instant: the public signal in
/// `docs/12-api-feasibility-matrix.md` reports *that* the screen is being
/// captured, never by which app, so there is no recorder identity to carry.
public struct ScreenRecordingSession: Equatable, Sendable {
    public let startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }
}

/// Called with the capture session as it stands, or `nil` once nothing the
/// signal can see is capturing.
public typealias ScreenRecordingSessionObserver = @MainActor (ScreenRecordingSession?) -> Void

/// The seam between "however the system tells us the screen is being captured"
/// and "how that becomes a `RecordingActivity`".
///
/// Split out for the reason `docs/06-activity-providers.md` gives: the system
/// query is exercisable only on real hardware, while the activity, priority and
/// teardown logic around it must be verifiable in CI against a fake source.
/// Conformances are event-driven; one that polls violates
/// `docs/02-performance-contract.md`.
@MainActor
public protocol ScreenRecordingObserving: AnyObject {
    func startObserving(_ observer: @escaping ScreenRecordingSessionObserver)
    func stopObserving()
}

/// Called with the recording activity, or `nil` once there is no recording at
/// all — teardown is the absence of an activity rather than an activity
/// describing absence, per the teardown rule in `docs/06-activity-providers.md`.
public typealias RecordingActivityObserver = @MainActor (RecordingActivity?) -> Void

/// Turns the system's screen-capture signal into the indicator the manager
/// registers, per `docs/06-activity-providers.md`.
///
/// Session start and end are event-driven off the underlying observer; the only
/// wakeup this provider owns is the one that redraws the elapsed counter, and it
/// follows the timer provider's discipline exactly — a source exists only while
/// a recording is actually on screen with someone listening. Because
/// `RecordingActivity` derives its elapsed time from the session's start
/// timestamp, suspending that wakeup suspends the *display refresh* and never
/// the count.
@MainActor
public final class ScreenRecordingProvider {
    private let sessions: any ScreenRecordingObserving
    private let scheduler: any TickScheduling
    private let now: () -> Date

    private var observer: RecordingActivityObserver?
    private var activity: RecordingActivity?
    private var isPanelVisible = false

    public init(
        sessions: any ScreenRecordingObserving,
        scheduler: any TickScheduling = DispatchTickScheduler(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sessions = sessions
        self.scheduler = scheduler
        self.now = now
    }

    /// Whether a redraw wakeup is currently armed.
    public var hasTickSource: Bool { scheduler.isScheduled }

    public var currentActivity: RecordingActivity? { activity }

    public func startObserving(_ observer: @escaping RecordingActivityObserver) {
        self.observer = observer

        sessions.startObserving { [weak self] session in
            self?.apply(session)
        }
    }

    public func stopObserving() {
        observer = nil
        sessions.stopObserving()
        scheduler.cancel()
    }

    /// Whether the recording's activity is currently on screen. The panel tells
    /// the provider rather than the provider reaching up to ask, which keeps the
    /// dependency pointing one way.
    public func setPanelVisible(_ isVisible: Bool) {
        guard isPanelVisible != isVisible else { return }

        isPanelVisible = isVisible
        synchronizeTicking()
    }

    /// The activity is rebuilt from the session's own start instant every time,
    /// so a redundant re-emission of a running session re-reads the counter
    /// instead of restarting it — the session, not the notification, is what
    /// the elapsed time is measured from.
    private func apply(_ session: ScreenRecordingSession?) {
        activity = session.map {
            RecordingActivity(source: .screen, startedAt: $0.startedAt, at: now())
        }

        emit()
        synchronizeTicking()
    }

    private func tick() {
        guard let activity else { return }

        self.activity = activity.advanced(to: now())
        emit()
    }

    private func emit() {
        observer?(activity)
    }

    private func synchronizeTicking() {
        guard shouldTick else {
            scheduler.cancel()
            return
        }

        guard scheduler.isScheduled == false else { return }

        scheduler.schedule { [weak self] in
            self?.tick()
        }
    }

    /// A wakeup is only earned by a recording that someone is both listening for
    /// and looking at.
    private var shouldTick: Bool {
        observer != nil && isPanelVisible && activity != nil
    }
}
