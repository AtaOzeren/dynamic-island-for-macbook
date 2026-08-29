import Foundation
import Testing

@testable import NotchFlowCore

/// The timer's whole state machine is pure logic over an injected date, per
/// `docs/06-activity-providers.md` — so every case here runs without a wall
/// clock, a hardware timer, or a sleep.
@Suite("TimerActivity")
struct TimerActivityTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    private static func date(_ offset: TimeInterval) -> Date {
        start.addingTimeInterval(offset)
    }

    private static func countdown(seconds: Int) -> TimerActivity {
        .started(.countdown(duration: .seconds(seconds)), at: start)
    }

    @Test("a fresh countdown is running with its full duration remaining")
    func freshCountdown() {
        let timer = Self.countdown(seconds: 60)

        #expect(timer.kind == .timer)
        #expect(timer.isRunning)
        #expect(timer.elapsed == .zero)
        #expect(timer.remaining == .seconds(60))
        #expect(timer.isExpiring == false)
    }

    /// Elapsed time is derived from the start timestamp, never accumulated from
    /// ticks — so one late read is worth exactly as much as sixty on-time ones.
    @Test("derives elapsed time from timestamps rather than tick count")
    func elapsedFromTimestamps() {
        let timer = Self.countdown(seconds: 60)

        #expect(timer.advanced(to: Self.date(1)).elapsed == .seconds(1))
        #expect(timer.advanced(to: Self.date(45)).elapsed == .seconds(45))
        #expect(timer.advanced(to: Self.date(45)).remaining == .seconds(15))
    }

    /// The panel can be hidden for the whole countdown and the answer on the
    /// single read afterwards is still correct — the "no ticks are lost"
    /// guarantee in `docs/06-activity-providers.md`.
    @Test("a single read after a long invisible stretch is accurate")
    func noTicksLostWhileInvisible() {
        let ticked = (1...3600).reduce(Self.countdown(seconds: 7200)) { timer, second in
            timer.advanced(to: Self.date(TimeInterval(second)))
        }
        let readOnce = Self.countdown(seconds: 7200).advanced(to: Self.date(3600))

        #expect(ticked.elapsed == readOnce.elapsed)
        #expect(readOnce.remaining == .seconds(3600))
    }

    @Test("a countdown floors at zero rather than going negative")
    func countdownFloorsAtZero() {
        let expired = Self.countdown(seconds: 10).advanced(to: Self.date(90))

        #expect(expired.remaining == .zero)
        #expect(expired.isExpiring)
    }

    /// The V1 priority table's "Timer expiring" row: `high` only once the
    /// countdown has arrived, not for its whole run.
    @Test("takes high priority only while expiring")
    func priorityRisesOnlyOnExpiry() {
        let running = Self.countdown(seconds: 60).advanced(to: Self.date(30))
        let expired = Self.countdown(seconds: 60).advanced(to: Self.date(60))

        #expect(running.priority == .normal)
        #expect(expired.priority == .high)
    }

    /// "Stays until acknowledged" — an expired countdown must not auto-dismiss
    /// itself out from under the user.
    @Test("never auto-dismisses, expired or not")
    func neverAutoDismisses() {
        #expect(Self.countdown(seconds: 60).autoDismiss == nil)
        #expect(Self.countdown(seconds: 60).advanced(to: Self.date(60)).autoDismiss == nil)
    }

    @Test("banks elapsed time across a pause and does not advance while paused")
    func pauseBanksElapsedTime() {
        let paused = Self.countdown(seconds: 60)
            .advanced(to: Self.date(20))
            .paused(at: Self.date(20))

        #expect(paused.isRunning == false)
        #expect(paused.elapsed == .seconds(20))
        #expect(paused.advanced(to: Self.date(300)).elapsed == .seconds(20))
        #expect(paused.advanced(to: Self.date(300)).remaining == .seconds(40))
    }

    @Test("resumes from the banked total rather than from the original start")
    func resumeContinuesFromBankedTotal() {
        let resumed = Self.countdown(seconds: 60)
            .paused(at: Self.date(20))
            .resumed(at: Self.date(300))

        #expect(resumed.isRunning)
        #expect(resumed.elapsed == .seconds(20))
        #expect(resumed.advanced(to: Self.date(310)).elapsed == .seconds(30))
    }

    @Test("ignores a redundant pause or resume")
    func redundantTransitionsAreInert() {
        let paused = Self.countdown(seconds: 60).paused(at: Self.date(20))
        let running = Self.countdown(seconds: 60)

        #expect(paused.paused(at: Self.date(50)).elapsed == .seconds(20))
        #expect(running.resumed(at: Self.date(50)).advanced(to: Self.date(60)).elapsed == .seconds(60))
    }

    /// An NTP correction mid-countdown must stall the display, not run it
    /// backwards past time the user already watched elapse.
    @Test("stalls rather than reversing when the clock jumps backwards")
    func clockGoingBackwardsDoesNotReverseTheTimer() {
        let timer = Self.countdown(seconds: 60)
            .advanced(to: Self.date(30))
            .paused(at: Self.date(30))
            .resumed(at: Self.date(30))

        #expect(timer.advanced(to: Self.date(10)).elapsed == .seconds(30))
        #expect(timer.advanced(to: Self.date(10)).remaining == .seconds(30))
    }

    @Test("a stopwatch counts up and never expires")
    func stopwatchCountsUp() {
        let stopwatch = TimerActivity.started(.stopwatch, at: Self.start)

        #expect(stopwatch.advanced(to: Self.date(90)).elapsed == .seconds(90))
        #expect(stopwatch.advanced(to: Self.date(90)).remaining == nil)
        #expect(stopwatch.advanced(to: Self.date(90)).isExpiring == false)
        #expect(stopwatch.advanced(to: Self.date(90)).priority == .normal)
    }

    /// A tick is an update to one activity, not a new registration — which is
    /// what keeps the island from re-sorting itself every second.
    @Test("keeps one identity across ticks and transitions")
    func identityIsStableAcrossTicks() {
        let timer = Self.countdown(seconds: 60)

        #expect(timer.advanced(to: Self.date(30)).identity == timer.identity)
        #expect(timer.paused(at: Self.date(30)).identity == timer.identity)
        #expect(timer.identity == TimerActivity.identity)
    }

    /// The affordance the expanded row draws has to describe what a click will
    /// actually do, per `docs/05-activity-model.md`.
    @Test("offers the primary action matching its current state")
    func primaryActionMatchesState() {
        let running = Self.countdown(seconds: 60)
        let paused = running.paused(at: Self.date(10))
        let expired = running.advanced(to: Self.date(60))

        #expect(running.primaryAction?.title == "Pause")
        #expect(paused.primaryAction?.title == "Resume")
        #expect(expired.primaryAction?.title == "Dismiss")
    }
}
