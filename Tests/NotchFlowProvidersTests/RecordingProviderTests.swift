import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

/// The provider half of both recording indicators: session start and stop
/// become an activity and its absence, and the redraw wakeup exists only while
/// something is on screen to redraw. The fake session source stands in for the
/// system signals, which — per `docs/06-activity-providers.md` — are the part
/// that can only be exercised on hardware.
@Suite("RecordingProvider")
@MainActor
struct RecordingProviderTests {
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
        let provider: RecordingProvider
        let sessions: FakeRecordingObserver
        let scheduler: FakeTickScheduler
        let clock: Clock
    }

    /// A provider with an observer attached and a visible panel — the only
    /// configuration in which ticking is legal, so every "must not tick" case
    /// is one deviation from it.
    private static func makeVisibleProvider(
        source: RecordingSource = .screen,
        onActivity: @escaping RecordingActivityObserver = { _ in }
    ) -> Fixture {
        let sessions = FakeRecordingObserver()
        let scheduler = FakeTickScheduler()
        let clock = Clock(start)
        let provider = RecordingProvider(
            source: source,
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

        fixture.sessions.emit(RecordingSession(startedAt: Self.start))

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

        fixture.sessions.emit(RecordingSession(startedAt: Self.start))
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
        let session = RecordingSession(startedAt: Self.start)

        fixture.sessions.emit(session)
        fixture.clock.advance(30)
        fixture.sessions.emit(session)

        #expect(fixture.provider.currentActivity?.elapsed == .seconds(30))
    }

    @Test("starts a fresh count for a genuinely new session")
    func newSessionRestartsTheCount() {
        let fixture = Self.makeVisibleProvider()

        fixture.sessions.emit(RecordingSession(startedAt: Self.start))
        fixture.clock.advance(30)
        fixture.sessions.emit(RecordingSession(startedAt: fixture.clock.date))

        #expect(fixture.provider.currentActivity?.elapsed == .zero)
    }

    @Test("arms a wakeup while a recording is on screen")
    func armsAWakeupWhileVisible() {
        let fixture = Self.makeVisibleProvider()

        fixture.sessions.emit(RecordingSession(startedAt: Self.start))

        #expect(fixture.provider.hasTickSource)
    }

    /// The performance contract's "active only while a time-based activity is
    /// visible" rule, applied to the recording counter.
    @Test("cancels the wakeup when the panel hides and rearms when it returns")
    func wakeupFollowsPanelVisibility() {
        let fixture = Self.makeVisibleProvider()
        fixture.sessions.emit(RecordingSession(startedAt: Self.start))

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
        fixture.sessions.emit(RecordingSession(startedAt: Self.start))

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
        fixture.sessions.emit(RecordingSession(startedAt: Self.start))

        fixture.clock.advance(1)
        fixture.scheduler.fire()

        #expect(fixture.provider.currentActivity?.elapsed == .seconds(1))
    }

    @Test("drops its wakeup and its session subscription when observation stops")
    func stopObservingReleasesEverything() {
        let fixture = Self.makeVisibleProvider()
        fixture.sessions.emit(RecordingSession(startedAt: Self.start))

        fixture.provider.stopObserving()

        #expect(fixture.provider.hasTickSource == false)
        #expect(fixture.sessions.isObserving == false)
    }

    @Test("reports the source it was built for")
    func audioSourceProducesAnAudioActivity() {
        let fixture = Self.makeVisibleProvider(source: .audio)

        fixture.sessions.emit(RecordingSession(startedAt: Self.start))

        #expect(fixture.provider.currentActivity?.source == .audio)
    }

    /// Screen and microphone capture are concurrent facts, so the two providers
    /// must produce activities the manager can hold at once. Sharing an identity
    /// would let one silently replace the other in the island.
    @Test("gives each source its own activity identity")
    func sourcesDoNotShareAnIdentity() {
        let screen = Self.makeVisibleProvider(source: .screen)
        let audio = Self.makeVisibleProvider(source: .audio)

        screen.sessions.emit(RecordingSession(startedAt: Self.start))
        audio.sessions.emit(RecordingSession(startedAt: Self.start))

        #expect(screen.provider.currentActivity?.identity != audio.provider.currentActivity?.identity)
    }

    /// A microphone that was already live when NotchFlow launched has been live
    /// since before the first emission, and the counter must say so.
    @Test("counts from the session's start instant, not from when it was told")
    func countsFromTheSessionStartRatherThanTheEmission() {
        let fixture = Self.makeVisibleProvider(source: .audio)

        fixture.clock.advance(90)
        fixture.sessions.emit(RecordingSession(startedAt: Self.start))

        #expect(fixture.provider.currentActivity?.elapsed == .seconds(90))
    }
}

/// The seam's test double: a session source the test drives directly, standing
/// in for the system signal that needs real hardware.
@MainActor
private final class FakeRecordingObserver: RecordingObserving {
    private var observer: RecordingSessionObserver?

    var isObserving: Bool { observer != nil }

    func startObserving(_ observer: @escaping RecordingSessionObserver) {
        self.observer = observer
    }

    func stopObserving() {
        observer = nil
    }

    func emit(_ session: RecordingSession?) {
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
