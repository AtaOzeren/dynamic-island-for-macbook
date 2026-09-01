import Foundation

/// Which direction NotchFlow's own clock runs.
///
/// A countdown carries the duration it was started with; a stopwatch has no
/// destination and so cannot expire. Keeping the target on the case rather than
/// on the activity is what lets `remaining` be undefined-by-construction for a
/// stopwatch instead of being an optional every caller has to unwrap.
public enum TimerMode: Equatable, Sendable {
    case countdown(duration: Duration)
    case stopwatch
}

/// The timer's progress at a given instant, derived from timestamps rather than
/// accumulated from ticks.
///
/// This is the concrete reason `docs/06-activity-providers.md` can promise that
/// no ticks are "lost" while the panel is hidden: a tick only ever asks this
/// type what the elapsed time *is*, and never adds to it. Suppressing every
/// tick for an hour and asking once at the end yields the same answer as
/// ticking once a second throughout.
public struct TimerSchedule: Equatable, Sendable {
    /// When the timer last started or resumed. `nil` while paused, which is
    /// what makes "paused" unrepresentable-as-running rather than a flag that
    /// could disagree with the timestamps.
    private let runningSince: Date?
    /// Time banked by earlier running stretches, before the most recent pause.
    private let accumulated: Duration

    private init(runningSince: Date?, accumulated: Duration) {
        self.runningSince = runningSince
        self.accumulated = accumulated
    }

    public static func started(at date: Date) -> Self {
        Self(runningSince: date, accumulated: .zero)
    }

    public var isRunning: Bool { runningSince != nil }

    /// How long the timer has been running in total, as of `date`.
    ///
    /// Clamped at the banked total so that a clock that jumps backwards — an
    /// NTP correction mid-countdown — reports a stalled timer rather than one
    /// that runs backwards.
    public func elapsed(at date: Date) -> Duration {
        guard let runningSince else { return accumulated }

        let sinceResume = Duration.seconds(date.timeIntervalSince(runningSince))
        guard sinceResume > .zero else { return accumulated }

        return accumulated + sinceResume
    }

    public func paused(at date: Date) -> Self {
        guard isRunning else { return self }
        return Self(runningSince: nil, accumulated: elapsed(at: date))
    }

    public func resumed(at date: Date) -> Self {
        guard isRunning == false else { return self }
        return Self(runningSince: date, accumulated: accumulated)
    }
}

/// NotchFlow's own countdown or stopwatch — the one V1 activity the app is both
/// the source and the consumer of, per `docs/06-activity-providers.md`.
///
/// The activity is a value describing the timer at an instant; `TimerProvider`
/// in `NotchFlowProviders` is what re-derives it on each tick. Nothing here
/// owns a tick, which is what keeps the whole state machine (start → tick →
/// expire → acknowledge) testable as pure logic over an injected date.
public struct TimerActivity: Activity, Equatable {
    /// One identity for the whole timer feature: V1 runs at most one timer, so
    /// a tick is an update to the same activity rather than a new registration,
    /// which is what stops the island re-sorting itself every second.
    public static let identity = ActivityIdentity("notchflow.timer")

    public let mode: TimerMode
    public let schedule: TimerSchedule
    /// The instant this value describes. Every derived quantity — elapsed,
    /// remaining, expiry — is relative to it, so a `TimerActivity` compares
    /// equal to itself across a tick only when the displayed time is unchanged.
    public let date: Date

    public init(mode: TimerMode, schedule: TimerSchedule, at date: Date) {
        self.mode = mode
        self.schedule = schedule
        self.date = date
    }

    public static func started(_ mode: TimerMode, at date: Date) -> Self {
        Self(mode: mode, schedule: .started(at: date), at: date)
    }

    public var identity: ActivityIdentity { Self.identity }

    public var kind: ActivityKind { .timer }

    public var isRunning: Bool { schedule.isRunning }

    public var elapsed: Duration { schedule.elapsed(at: date) }

    /// The countdown's time left, floored at zero; `nil` for a stopwatch, which
    /// has no destination to be short of.
    public var remaining: Duration? {
        guard case .countdown(let duration) = mode else { return nil }
        return max(.zero, duration - elapsed)
    }

    /// A countdown that has reached zero. A stopwatch is never expiring.
    public var isExpiring: Bool { remaining == .zero }

    /// `high` only while expiring — the V1 priority table's "Timer expiring"
    /// row. A running timer the user is already watching is not a forcing
    /// condition beyond having registered an activity at all, so it sits at
    /// `normal` and lets recording and AI activities outrank it.
    public var priority: ActivityPriority { isExpiring ? .high : .normal }

    /// None. An expired countdown "stays until acknowledged" per the V1 table,
    /// and a running timer has no reason to disappear on its own.
    public var autoDismiss: AutoDismissDescriptor? { nil }

    public var primaryAction: PrimaryAction? {
        if isExpiring {
            return PrimaryAction(title: "Dismiss", symbolName: "checkmark", intent: .stopTimer)
        }
        return isRunning
            ? PrimaryAction(title: "Pause", symbolName: "pause.fill", intent: .pauseTimer)
            : PrimaryAction(title: "Resume", symbolName: "play.fill", intent: .resumeTimer)
    }

    /// The same timer re-read at a later instant — what a tick produces.
    public func advanced(to date: Date) -> Self {
        Self(mode: mode, schedule: schedule, at: date)
    }

    public func paused(at date: Date) -> Self {
        Self(mode: mode, schedule: schedule.paused(at: date), at: date)
    }

    public func resumed(at date: Date) -> Self {
        Self(mode: mode, schedule: schedule.resumed(at: date), at: date)
    }
}
