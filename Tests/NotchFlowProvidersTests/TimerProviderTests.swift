import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

/// The tick-lifetime half of the timer provider: when a wakeup exists and when
/// it must not. The fake scheduler stands in for `DispatchSourceTimer` so the
/// acceptance criterion — "no timer source exists while no time activity is
/// visible" — is a direct assertion rather than a sampled process.
@Suite("TimerProvider")
@MainActor
struct TimerProviderTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    private final class Clock {
        var date: Date

        init(_ date: Date) {
            self.date = date
        }

        func advance(_ seconds: TimeInterval) {
            date = date.addingTimeInterval(seconds)
        }
    }

    /// A provider with a fake scheduler, an observer already attached, and a
    /// visible panel — the only configuration in which ticking is legal, so
    /// every "should not tick" case is one deviation from it.
    private static func makeVisibleProvider() -> (TimerProvider, FakeTickScheduler, Clock) {
        let scheduler = FakeTickScheduler()
        let clock = Clock(start)
        let provider = TimerProvider(scheduler: scheduler, now: { clock.date })

        provider.startObserving { _ in }
        provider.setPanelVisible(true)

        return (provider, scheduler, clock)
    }

    @Test("arms no tick source until a timer is actually started")
    func noTickSourceWithoutATimer() {
        let (provider, scheduler, _) = Self.makeVisibleProvider()

        #expect(provider.hasTickSource == false)
        #expect(scheduler.scheduleCount == 0)
    }

    @Test("arms a tick source for a running timer on a visible panel")
    func ticksWhileRunningAndVisible() {
        let (provider, scheduler, _) = Self.makeVisibleProvider()

        provider.handle(.start(.countdown(duration: .seconds(60))))

        #expect(provider.hasTickSource)
        #expect(scheduler.scheduleCount == 1)
    }

    /// The performance contract's "active only while a time-based activity is
    /// visible" rule, in its most literal form.
    @Test("cancels the tick source when the panel stops being visible")
    func hidingThePanelCancelsTheTick() {
        let (provider, _, _) = Self.makeVisibleProvider()
        provider.handle(.start(.countdown(duration: .seconds(60))))

        provider.setPanelVisible(false)

        #expect(provider.hasTickSource == false)
    }

    @Test("re-arms the tick source when the panel becomes visible again")
    func showingThePanelRearmsTheTick() {
        let (provider, _, _) = Self.makeVisibleProvider()
        provider.handle(.start(.countdown(duration: .seconds(60))))
        provider.setPanelVisible(false)

        provider.setPanelVisible(true)

        #expect(provider.hasTickSource)
    }

    /// The elapsed time is derived from timestamps, so suppressing the tick
    /// suspends the display refresh and not the countdown.
    @Test("keeps counting accurately across an invisible stretch")
    func timeKeepsRunningWhileNotVisible() {
        let (provider, _, clock) = Self.makeVisibleProvider()
        provider.handle(.start(.countdown(duration: .seconds(600))))

        provider.setPanelVisible(false)
        clock.advance(300)
        provider.setPanelVisible(true)

        #expect(provider.currentActivity?.advanced(to: clock.date).remaining == .seconds(300))
    }

    @Test("cancels the tick source while the timer is paused")
    func pauseCancelsTheTick() {
        let (provider, _, _) = Self.makeVisibleProvider()
        provider.handle(.start(.countdown(duration: .seconds(60))))

        provider.handle(.pause)

        #expect(provider.hasTickSource == false)
        #expect(provider.currentActivity?.isRunning == false)
    }

    @Test("re-arms the tick source on resume")
    func resumeRearmsTheTick() {
        let (provider, _, _) = Self.makeVisibleProvider()
        provider.handle(.start(.countdown(duration: .seconds(60))))
        provider.handle(.pause)

        provider.handle(.resume)

        #expect(provider.hasTickSource)
    }

    /// The acceptance criterion: end the timer, and nothing is left ticking.
    @Test("leaves no tick source once the timer is stopped")
    func stopLeavesNoTickSource() {
        let (provider, _, _) = Self.makeVisibleProvider()
        provider.handle(.start(.countdown(duration: .seconds(60))))

        provider.handle(.stop)

        #expect(provider.hasTickSource == false)
        #expect(provider.currentActivity == nil)
    }

    /// An expired countdown stays on screen until acknowledged, but it has
    /// nothing left to redraw — so it waits without a wakeup.
    @Test("stops ticking once the countdown expires, while staying visible")
    func expiryStopsTheTickButNotTheActivity() {
        let (provider, scheduler, clock) = Self.makeVisibleProvider()
        provider.handle(.start(.countdown(duration: .seconds(2))))

        clock.advance(2)
        scheduler.fire()

        #expect(provider.hasTickSource == false)
        #expect(provider.currentActivity?.isExpiring == true)
    }

    @Test("emits the advancing timer on every tick")
    func emitsOnEveryTick() {
        let scheduler = FakeTickScheduler()
        let clock = Clock(Self.start)
        let provider = TimerProvider(scheduler: scheduler, now: { clock.date })
        var received: [Duration?] = []

        provider.startObserving { activity in
            received.append(activity?.elapsed)
        }
        provider.setPanelVisible(true)
        provider.handle(.start(.stopwatch))

        clock.advance(1)
        scheduler.fire()
        clock.advance(1)
        scheduler.fire()

        #expect(received == [.zero, .seconds(1), .seconds(2)])
    }

    /// Teardown is the absence of an activity, not an activity describing
    /// absence — the same contract the music backends emit `nil` under.
    @Test("emits nil when the timer is stopped")
    func emitsNilOnStop() {
        let (provider, _, _) = Self.makeVisibleProvider()
        var received: [TimerActivity?] = []

        provider.startObserving { received.append($0) }
        provider.handle(.start(.countdown(duration: .seconds(60))))
        provider.handle(.stop)

        #expect(received.count == 2)
        #expect(received.last == .some(nil))
    }

    @Test("arms no tick source while nobody is observing")
    func noTickSourceWithoutAnObserver() {
        let scheduler = FakeTickScheduler()
        let provider = TimerProvider(scheduler: scheduler, now: { Self.start })

        provider.setPanelVisible(true)
        provider.handle(.start(.countdown(duration: .seconds(60))))

        #expect(provider.hasTickSource == false)
    }

    @Test("cancels the tick source when observation stops")
    func stopObservingCancelsTheTick() {
        let (provider, _, _) = Self.makeVisibleProvider()
        provider.handle(.start(.countdown(duration: .seconds(60))))

        provider.stopObserving()

        #expect(provider.hasTickSource == false)
    }

    /// Re-arming an already-armed source would leak wakeups: two sources for
    /// one timer is twice the idle cost the contract budgets for.
    @Test("never arms a second tick source over a live one")
    func doesNotStackTickSources() {
        let (provider, scheduler, _) = Self.makeVisibleProvider()

        provider.handle(.start(.countdown(duration: .seconds(60))))
        provider.handle(.start(.countdown(duration: .seconds(90))))
        provider.setPanelVisible(true)

        #expect(scheduler.scheduleCount == 1)
        #expect(scheduler.isScheduled)
    }

    @Test("a stopwatch ticks indefinitely without ever expiring")
    func stopwatchNeverExpires() {
        let (provider, scheduler, clock) = Self.makeVisibleProvider()
        provider.handle(.start(.stopwatch))

        clock.advance(3600)
        scheduler.fire()

        #expect(provider.hasTickSource)
        #expect(provider.currentActivity?.isExpiring == false)
        #expect(provider.currentActivity?.elapsed == .seconds(3600))
    }

    /// The real scheduler's leeway is the mechanism the performance contract
    /// names, so the value is worth pinning rather than leaving to drift.
    @Test("schedules its real wakeup with generous leeway")
    func realSchedulerUsesGenerousLeeway() {
        #expect(DispatchTickScheduler.leewayMilliseconds > 0)
        #expect(DispatchTickScheduler.leewayMilliseconds <= DispatchTickScheduler.intervalMilliseconds)
    }
}

/// The seam's test double: a scheduler that arms and cancels like the real one
/// but fires only when the test says so, per `docs/11-testing-strategy.md`.
@MainActor
private final class FakeTickScheduler: TickScheduling {
    private var tick: (@MainActor () -> Void)?

    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0

    var isScheduled: Bool { tick != nil }

    func schedule(_ tick: @escaping @MainActor () -> Void) {
        scheduleCount += 1
        self.tick = tick
    }

    func cancel() {
        guard tick != nil else { return }

        cancelCount += 1
        tick = nil
    }

    func fire() {
        tick?()
    }
}
