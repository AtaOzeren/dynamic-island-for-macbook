import Foundation
import NotchFlowCore

/// Called with the timer as it stands, or `nil` once there is no timer at all.
///
/// The optional mirrors `NowPlayingObserver`: teardown is the absence of an
/// activity rather than an activity describing absence, per the teardown rule
/// in `docs/06-activity-providers.md`.
public typealias TimerActivityObserver = @MainActor (TimerActivity?) -> Void

/// A repeating wakeup the provider can arm and cancel.
///
/// Abstracted out of `TimerProvider` so that "is a tick source armed right
/// now?" — this todo's acceptance criterion — can be asserted directly in CI
/// rather than inferred by sampling a live process.
@MainActor
public protocol TickScheduling: AnyObject {
    var isScheduled: Bool { get }
    func schedule(_ tick: @escaping @MainActor () -> Void)
    func cancel()
}

/// The real wakeup: a `DispatchSourceTimer` with generous leeway, per
/// `docs/02-performance-contract.md`.
///
/// The leeway is what makes a once-a-second wakeup affordable — it lets the OS
/// coalesce ours with others already scheduled instead of forcing a precise
/// one. Half a second of tolerance costs nothing visible on a display that only
/// ever draws whole seconds.
@MainActor
public final class DispatchTickScheduler: TickScheduling {
    /// One second: the finest granularity any timer display draws.
    public static let intervalMilliseconds = 1000
    public static let leewayMilliseconds = 500

    private let queue: DispatchQueue
    private var source: DispatchSourceTimer?

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public var isScheduled: Bool { source != nil }

    public func schedule(_ tick: @escaping @MainActor () -> Void) {
        cancel()

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + .milliseconds(Self.intervalMilliseconds),
            repeating: .milliseconds(Self.intervalMilliseconds),
            leeway: .milliseconds(Self.leewayMilliseconds)
        )
        source.setEventHandler {
            MainActor.assumeIsolated { tick() }
        }
        source.resume()

        self.source = source
    }

    public func cancel() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }
}

/// What the user can ask of NotchFlow's own timer, from the expanded island or
/// from settings.
public enum TimerCommand: Equatable, Sendable {
    case start(TimerMode)
    case pause
    case resume
    /// Stops and clears the timer. Also how an expired countdown is
    /// acknowledged, since acknowledgment and teardown are one gesture.
    case stop
}

/// NotchFlow's countdown and stopwatch — the only V1 provider that owns a
/// repeating tick, per `docs/06-activity-providers.md`.
///
/// The tick exists only while there is something for it to redraw: a running,
/// unexpired timer on a visible panel, with someone listening. Every other
/// combination cancels the source outright. Because `TimerActivity` derives its
/// elapsed time from timestamps, cancelling the tick suspends the *display
/// refresh* and never the timer, so a countdown run entirely behind a hidden
/// panel is still correct on the first frame after it reappears.
@MainActor
public final class TimerProvider {
    private let scheduler: any TickScheduling
    private let now: () -> Date

    private var observer: TimerActivityObserver?
    private var activity: TimerActivity?
    private var isPanelVisible = false

    public init(
        scheduler: any TickScheduling = DispatchTickScheduler(),
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduler = scheduler
        self.now = now
    }

    /// Whether a wakeup is currently armed. This todo's acceptance criterion
    /// reads directly off this.
    public var hasTickSource: Bool { scheduler.isScheduled }

    public var currentActivity: TimerActivity? { activity }

    public func startObserving(_ observer: @escaping TimerActivityObserver) {
        self.observer = observer
        synchronizeTicking()
    }

    public func stopObserving() {
        observer = nil
        scheduler.cancel()
    }

    /// Whether the timer's activity is currently on screen. The panel tells the
    /// provider rather than the provider reaching up to ask, which keeps the
    /// dependency pointing one way.
    public func setPanelVisible(_ isVisible: Bool) {
        guard isPanelVisible != isVisible else { return }

        isPanelVisible = isVisible
        synchronizeTicking()
    }

    public func handle(_ command: TimerCommand) {
        let date = now()

        switch command {
        case .start(let mode):
            activity = .started(mode, at: date)
        case .pause:
            activity = activity?.paused(at: date)
        case .resume:
            activity = activity?.resumed(at: date)
        case .stop:
            activity = nil
        }

        emit()
        synchronizeTicking()
    }

    private func tick() {
        guard let current = activity else { return }

        let advanced = current.advanced(to: now())
        activity = advanced
        emit()

        // The tick that discovers the expiry is the last one: an expired
        // countdown has nothing further to redraw while it waits to be
        // acknowledged.
        if advanced.isExpiring {
            synchronizeTicking()
        }
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

    /// A tick only earns its wakeup when a running, unexpired timer is actually
    /// on screen with someone listening.
    private var shouldTick: Bool {
        guard observer != nil, isPanelVisible, let activity else { return false }
        return activity.isRunning && activity.isExpiring == false
    }
}
