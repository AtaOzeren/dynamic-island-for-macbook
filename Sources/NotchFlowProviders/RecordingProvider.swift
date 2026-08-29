import Foundation
import NotchFlowCore

/// A capture — of the screen or of the microphone — that the system is
/// reporting as in progress.
///
/// It carries only a start instant: the public signals in
/// `docs/12-api-feasibility-matrix.md` report *that* something is being
/// captured, never by which app, so there is no recorder identity to carry.
public struct RecordingSession: Equatable, Sendable {
    public let startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }
}

/// Called with the capture session as it stands, or `nil` once nothing the
/// signal can see is capturing.
public typealias RecordingSessionObserver = @MainActor (RecordingSession?) -> Void

/// The seam between "however the system tells us something is being captured"
/// and "how that becomes a `RecordingActivity`".
///
/// One protocol serves both capture sources because both answer the same
/// question — is a capture running, and since when — and differ only in which
/// system signal answers it. That difference lives in the conformance, so the
/// activity, priority and teardown logic is written and tested once.
///
/// Split out for the reason `docs/06-activity-providers.md` gives: the system
/// query is exercisable only on real hardware, while the activity, priority and
/// teardown logic around it must be verifiable in CI against a fake source.
/// Conformances are event-driven; one that polls violates
/// `docs/02-performance-contract.md`.
@MainActor
public protocol RecordingObserving: AnyObject {
    func startObserving(_ observer: @escaping RecordingSessionObserver)
    func stopObserving()
}

/// Called with the recording activity, or `nil` once there is no recording at
/// all — teardown is the absence of an activity rather than an activity
/// describing absence, per the teardown rule in `docs/06-activity-providers.md`.
public typealias RecordingActivityObserver = @MainActor (RecordingActivity?) -> Void

/// Turns one system capture signal into the indicator the manager registers,
/// per `docs/06-activity-providers.md`.
///
/// Which capture it reports is the `source` it is constructed with, paired with
/// the observer that can see that source: screen recording and microphone
/// recording produce separate instances, and `RecordingActivity` gives each its
/// own identity so a live microphone never displaces a live screen capture.
///
/// Session start and end are event-driven off the underlying observer; the only
/// wakeup this provider owns is the one that redraws the elapsed counter, and it
/// follows the timer provider's discipline exactly — a source exists only while
/// a recording is actually on screen with someone listening. Because
/// `RecordingActivity` derives its elapsed time from the session's start
/// timestamp, suspending that wakeup suspends the *display refresh* and never
/// the count.
@MainActor
public final class RecordingProvider {
    private let source: RecordingSource
    private let sessions: any RecordingObserving
    private let scheduler: any TickScheduling
    private let now: () -> Date

    private var observer: RecordingActivityObserver?
    private var activity: RecordingActivity?
    private var isPanelVisible = false

    public init(
        source: RecordingSource,
        sessions: any RecordingObserving,
        scheduler: any TickScheduling = DispatchTickScheduler(),
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
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
    private func apply(_ session: RecordingSession?) {
        activity = session.map {
            RecordingActivity(source: source, startedAt: $0.startedAt, at: now())
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
