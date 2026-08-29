import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

/// The provider half of the screen recording indicator: session start and stop
/// become an activity and its absence, and the redraw wakeup exists only while
/// something is on screen to redraw. The fake session source stands in for the
/// permission-gated system signal, which — per
/// `docs/06-activity-providers.md` — is the part that can only be exercised on
/// hardware.
@Suite("ScreenRecordingProvider")
@MainActor
struct ScreenRecordingProviderTests {
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

    private struct Fixture {
        let provider: ScreenRecordingProvider
        let sessions: FakeScreenRecordingObserver
        let scheduler: FakeTickScheduler
        let clock: Clock
    }

    /// A provider with an observer attached and a visible panel — the only
    /// configuration in which ticking is legal, so every "must not tick" case
    /// is one deviation from it.
    private static func makeVisibleProvider(
        onActivity: @escaping RecordingActivityObserver = { _ in }
    ) -> Fixture {
        let sessions = FakeScreenRecordingObserver()
        let scheduler = FakeTickScheduler()
        let clock = Clock(start)
        let provider = ScreenRecordingProvider(
            sessions: sessions,
            scheduler: scheduler,
            now: { clock.date }
        )

        provider.startObserving(onActivity)
        provider.setPanelVisible(true)

        return Fixture(provider: provider, sessions: sessions, scheduler: scheduler, clock: clock)
    }

    @Test("produces no activity and no wakeup until a recording starts")
    func idleUntilRecordingStarts() {
        let fixture = Self.makeVisibleProvider()

        #expect(fixture.provider.currentActivity == nil)
        #expect(fixture.provider.hasTickSource == false)
        #expect(fixture.scheduler.scheduleCount == 0)
    }

    @Test("produces a recording activity when a session starts")
    func startingASessionProducesAnActivity() {
        var emissions: [RecordingActivity?] = []
        let fixture = Self.makeVisibleProvider { emissions.append($0) }

        fixture.sessions.emit(ScreenRecordingSession(startedAt: Self.start))

        #expect(fixture.provider.currentActivity?.source == .screen)
        #expect(fixture.provider.currentActivity?.elapsed == .zero)
        #expect(emissions.count == 1)
        #expect(emissions.last ?? nil != nil)
    }

    /// Teardown is the absence of an activity, never an activity describing
    /// absence.
    @Test("ends the activity when the session stops")
    func stoppingASessionEndsTheActivity() {
        var emissions: [RecordingActivity?] = []
        let fixture = Self.makeVisibleProvider { emissions.append($0) }

        fixture.sessions.emit(ScreenRecordingSession(startedAt: Self.start))
        fixture.sessions.emit(nil)

        #expect(fixture.provider.currentActivity == nil)
        #expect(emissions.last ?? nil == nil)
        #expect(fixture.provider.hasTickSource == false)
    }

    /// A session that is still the same session must not restart the counter,
    /// or a redundant notification would visibly reset the display.
    @Test("keeps the original start instant when the same session re-emits")
    func repeatedEmissionKeepsTheCounterRunning() {
        let fixture = Self.makeVisibleProvider()
        let session = ScreenRecordingSession(startedAt: Self.start)

        fixture.sessions.emit(session)
        fixture.clock.advance(30)
        fixture.sessions.emit(session)

        #expect(fixture.provider.currentActivity?.elapsed == .seconds(30))
    }

    @Test("starts a fresh count for a genuinely new session")
    func newSessionRestartsTheCount() {
        let fixture = Self.makeVisibleProvider()

        fixture.sessions.emit(ScreenRecordingSession(startedAt: Self.start))
        fixture.clock.advance(30)
        fixture.sessions.emit(ScreenRecordingSession(startedAt: fixture.clock.date))

        #expect(fixture.provider.currentActivity?.elapsed == .zero)
    }

    @Test("arms a wakeup while a recording is on screen")
    func armsAWakeupWhileVisible() {
        let fixture = Self.makeVisibleProvider()

        fixture.sessions.emit(ScreenRecordingSession(startedAt: Self.start))

        #expect(fixture.provider.hasTickSource)
    }

    /// The performance contract's "active only while a time-based activity is
    /// visible" rule, applied to the recording counter.
    @Test("cancels the wakeup when the panel hides and rearms when it returns")
    func wakeupFollowsPanelVisibility() {
        let fixture = Self.makeVisibleProvider()
        fixture.sessions.emit(ScreenRecordingSession(startedAt: Self.start))

        fixture.provider.setPanelVisible(false)
        #expect(fixture.provider.hasTickSource == false)

        fixture.provider.setPanelVisible(true)
        #expect(fixture.provider.hasTickSource)
    }

    /// Suspending the wakeup suspends the redraw, never the count: the elapsed
    /// time is read from the session's start instant on the first frame back.
    @Test("counts correctly across a stretch with no wakeups at all")
    func countSurvivesAHiddenPanel() {
        let fixture = Self.makeVisibleProvider()
        fixture.sessions.emit(ScreenRecordingSession(startedAt: Self.start))

        fixture.provider.setPanelVisible(false)
        fixture.clock.advance(3600)
        fixture.provider.setPanelVisible(true)
        fixture.scheduler.fire()

        #expect(fixture.provider.currentActivity?.elapsed == .seconds(3600))
        #expect(fixture.scheduler.scheduleCount == 2)
    }

    @Test("advances the displayed time on each wakeup")
    func tickAdvancesTheDisplayedTime() {
        let fixture = Self.makeVisibleProvider()
        fixture.sessions.emit(ScreenRecordingSession(startedAt: Self.start))

        fixture.clock.advance(1)
        fixture.scheduler.fire()

        #expect(fixture.provider.currentActivity?.elapsed == .seconds(1))
    }

    @Test("drops its wakeup and its session subscription when observation stops")
    func stopObservingReleasesEverything() {
        let fixture = Self.makeVisibleProvider()
        fixture.sessions.emit(ScreenRecordingSession(startedAt: Self.start))

        fixture.provider.stopObserving()

        #expect(fixture.provider.hasTickSource == false)
        #expect(fixture.sessions.isObserving == false)
    }
}

/// The seam's test double: a session source the test drives directly, standing
/// in for the system signal that needs real hardware.
@MainActor
private final class FakeScreenRecordingObserver: ScreenRecordingObserving {
    private var observer: ScreenRecordingSessionObserver?

    var isObserving: Bool { observer != nil }

    func startObserving(_ observer: @escaping ScreenRecordingSessionObserver) {
        self.observer = observer
    }

    func stopObserving() {
        observer = nil
    }

    func emit(_ session: ScreenRecordingSession?) {
        observer?(session)
    }
}

/// A scheduler that arms and cancels like the real one but fires only when the
/// test says so, per `docs/11-testing-strategy.md`.
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
