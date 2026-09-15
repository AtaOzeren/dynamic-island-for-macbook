import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// When the island glows around the compact pill, and when it stops.
///
/// The rules come straight from the request: green when an agent finishes,
/// yellow when it asks, red when it fails — five passes, stopping as soon as
/// the moment is over.
@Suite("IslandAttentionGlowTracker")
struct IslandAttentionGlowTrackerTests {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
    private static let rootID = UUID()
    private static let otherRootID = UUID()

    private static func session(
        _ state: AIAgentState,
        id: UUID = rootID,
        root: UUID? = nil,
        agent: IPCAgentID = .claudeCode
    ) -> AIAgentActivity {
        AIAgentActivity(agent: agent, sessionID: id, rootSessionID: root, state: state, detail: "detail")
    }

    private static func advanced(
        _ tracker: inout IslandAttentionGlowTracker,
        _ sessions: [AIAgentActivity],
        at seconds: TimeInterval
    ) -> IslandAttentionGlow? {
        tracker.advance(activities: sessions, registrationTimes: [:], now: t0.addingTimeInterval(seconds))
        return tracker.glow
    }

    @Test("a question lights the island yellow from the moment it is asked")
    func questionStartsAYellowGlow() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.working)], at: 0)

        let glow = Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 1)

        #expect(glow?.reason == .needsInput)
        #expect(glow?.reason.badgeTone == .yellow)
        #expect(glow?.startedAt == Self.t0.addingTimeInterval(1))
    }

    @Test("a finished task glows green and a failure glows red")
    func completionAndFailureTones() {
        var completed = IslandAttentionGlowTracker()
        var failed = IslandAttentionGlowTracker()

        #expect(Self.advanced(&completed, [Self.session(.completed)], at: 0)?.reason.badgeTone == .green)
        #expect(Self.advanced(&failed, [Self.session(.error)], at: 0)?.reason.badgeTone == .red)
    }

    @Test("work in flight never glows")
    func workInFlightNeverGlows() {
        var tracker = IslandAttentionGlowTracker()

        for state in [AIAgentState.idle, .thinking, .working, .usingTool] {
            #expect(Self.advanced(&tracker, [Self.session(state)], at: 0) == nil)
        }
    }

    /// A delegated step finishing is not the task finishing.
    @Test("a sub-agent finishing does not glow, but a sub-agent asking or failing does")
    func subagentRules() {
        let childID = UUID()
        var completed = IslandAttentionGlowTracker()
        var asking = IslandAttentionGlowTracker()
        var failing = IslandAttentionGlowTracker()

        #expect(Self.advanced(&completed, [Self.session(.completed, id: childID, root: Self.rootID)], at: 0) == nil)
        #expect(Self.advanced(&asking, [Self.session(.waitingForUser, id: childID, root: Self.rootID)], at: 0) != nil)
        #expect(Self.advanced(&failing, [Self.session(.error, id: childID, root: Self.rootID)], at: 0) != nil)
    }

    /// Agents repeat their state freely. A light that restarted on each
    /// repetition would never end.
    @Test("repeating the same state does not restart the glow")
    func repetitionDoesNotRestart() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 0)

        let glow = Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 5)

        #expect(glow?.startedAt == Self.t0)
    }

    @Test("the glow stops as soon as the question is answered")
    func answeringStopsTheGlow() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 0)

        #expect(Self.advanced(&tracker, [Self.session(.working)], at: 4) == nil)
    }

    @Test("the glow stops when its session ends")
    func endingTheSessionStopsTheGlow() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.error)], at: 0)

        #expect(Self.advanced(&tracker, [], at: 2) == nil)
    }

    /// Five two-second crossings with a three-second rest after each but the
    /// last: 5 × 2 + 4 × 3 = 22 seconds.
    @Test("five slow passes with a rest between them, and then the glow is over")
    func glowLastsFivePasses() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 0)

        #expect(Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 21.9) != nil)
        #expect(Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 22) == nil)
        #expect(Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 40) == nil)
    }

    /// The user asked for a two-second crossing followed by a three-second rest
    /// counted from the moment the light leaves.
    @Test("each crossing takes two seconds and the rest after it three")
    func passBeat() {
        #expect(IslandAttentionGlowTiming.passDuration == 2)
        #expect(IslandAttentionGlowTiming.restAfterPass == 3)
        #expect(IslandAttentionGlowTiming.passInterval == 5)
        #expect(IslandAttentionGlowTiming.totalDuration == 22)
    }

    /// A finished task's glow and its green tick leave the island together.
    @Test("the glow lasts exactly as long as a completed agent stays")
    func glowMatchesTheCompletedCard() {
        #expect(IslandAttentionGlowTiming.passCount == 5)
        #expect(
            Duration.seconds(IslandAttentionGlowTiming.totalDuration)
                == AIAgentActivity.completedAutoDismissAfter
        )
    }

    @Test("a more urgent moment takes over a running glow")
    func moreUrgentArrivalTakesOver() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.completed)], at: 0)

        let glow = Self.advanced(
            &tracker,
            [Self.session(.completed), Self.session(.error, id: Self.otherRootID)],
            at: 2
        )

        #expect(glow?.reason == .failed)
        #expect(glow?.sessionIdentity == Self.session(.error, id: Self.otherRootID).identity)
    }

    @Test("a less urgent moment leaves a running glow alone")
    func lessUrgentArrivalIsIgnored() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.error)], at: 0)

        let glow = Self.advanced(
            &tracker,
            [Self.session(.error), Self.session(.completed, id: Self.otherRootID)],
            at: 2
        )

        #expect(glow?.reason == .failed)
        #expect(glow?.startedAt == Self.t0)
    }

    /// A question asked while another agent's failure glows must still get its
    /// own light once the failure is over, or it is never announced.
    @Test("a moment held behind a more urgent glow lights up once that glow stops")
    func heldMomentLightsWhenTheGlowStops() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.error)], at: 0)
        _ = Self.advanced(&tracker, [Self.session(.error), Self.session(.waitingForUser, id: Self.otherRootID)], at: 2)

        let glow = Self.advanced(
            &tracker,
            [Self.session(.working), Self.session(.waitingForUser, id: Self.otherRootID)],
            at: 5
        )

        #expect(glow?.reason == .needsInput)
        #expect(glow?.startedAt == Self.t0.addingTimeInterval(5))
    }

    @Test("a held moment lights up when the glow ahead of it runs its course")
    func heldMomentLightsWhenTheGlowExpires() {
        var tracker = IslandAttentionGlowTracker()
        let failing = Self.session(.error)
        let asking = Self.session(.waitingForUser, id: Self.otherRootID)
        _ = Self.advanced(&tracker, [failing], at: 0)
        _ = Self.advanced(&tracker, [failing, asking], at: 2)

        let glow = Self.advanced(&tracker, [failing, asking], at: 22)

        #expect(glow?.reason == .needsInput)
        #expect(glow?.sessionIdentity == asking.identity)
    }

    @Test("a held moment that was resolved meanwhile never lights up")
    func resolvedHeldMomentStaysDark() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.error)], at: 0)
        _ = Self.advanced(&tracker, [Self.session(.error), Self.session(.waitingForUser, id: Self.otherRootID)], at: 2)
        _ = Self.advanced(&tracker, [Self.session(.error), Self.session(.working, id: Self.otherRootID)], at: 4)

        let glow = Self.advanced(
            &tracker,
            [Self.session(.working), Self.session(.working, id: Self.otherRootID)],
            at: 6
        )

        #expect(glow == nil)
    }

    @Test("an equally urgent moment restarts the glow for the newer session")
    func equalUrgencyReplaces() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 0)

        let glow = Self.advanced(
            &tracker,
            [Self.session(.waitingForUser), Self.session(.waitingForUser, id: Self.otherRootID, agent: .opencode)],
            at: 3
        )

        #expect(glow?.startedAt == Self.t0.addingTimeInterval(3))
        #expect(glow?.sessionIdentity == Self.session(.waitingForUser, id: Self.otherRootID, agent: .opencode).identity)
    }

    @Test("when several moments arrive together the most urgent wins")
    func mostUrgentOfABatchWins() {
        var tracker = IslandAttentionGlowTracker()

        let glow = Self.advanced(
            &tracker,
            [
                Self.session(.completed, id: UUID()),
                Self.session(.waitingForUser, id: UUID()),
                Self.session(.error, id: Self.otherRootID),
            ],
            at: 0
        )

        #expect(glow?.reason == .failed)
    }

    @Test("asking again after carrying on lights the island again")
    func reenteringRelights() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 0)
        _ = Self.advanced(&tracker, [Self.session(.working)], at: 4)

        let glow = Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 8)

        #expect(glow?.startedAt == Self.t0.addingTimeInterval(8))
    }

    @Test("a stopped glow stays off while nothing changes")
    func stoppedGlowStaysOff() {
        var tracker = IslandAttentionGlowTracker()
        _ = Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 0)
        _ = Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 22)

        #expect(Self.advanced(&tracker, [Self.session(.waitingForUser)], at: 23) == nil)
    }

    @Test("activities other than agents never glow")
    func otherActivitiesNeverGlow() {
        var tracker = IslandAttentionGlowTracker()
        let music = MusicActivity(
            nowPlaying: NowPlaying(title: "Windowlicker", artist: "Aphex Twin", playbackState: .playing)
        )

        tracker.advance(activities: [music], registrationTimes: [:], now: Self.t0)

        #expect(tracker.glow == nil)
    }
}
