import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// The island's one wake-up: whichever clock-driven change is due first, and
/// nothing at all while nothing is counting down.
@Suite("IslandPresentationClocks")
struct IslandPresentationClocksTests {
    private static let t0 = Date(timeIntervalSinceReferenceDate: 9_000)

    private static func music(_ playback: MusicPlaybackState) -> MusicActivity {
        MusicActivity(
            nowPlaying: NowPlaying(
                title: "Windowlicker",
                artist: "Aphex Twin",
                playbackState: playback,
                sourceApplicationName: "Spotify"
            )
        )
    }

    private static func agent(_ state: AIAgentState, reason: AIAgentFailureReason? = nil) -> AIAgentActivity {
        AIAgentActivity(
            agent: .claudeCode,
            sessionID: UUID(uuidString: "4D5B8B84-3E0B-4E3D-9D0E-6E1C7B7A0A11")!,
            state: state,
            reason: reason,
            detail: "detail"
        )
    }

    /// The performance contract: an island with nothing counting down must not
    /// schedule a single wake-up.
    @Test("working agents and playing music schedule no wake-up")
    func steadyStateSchedulesNothing() {
        var clocks = IslandPresentationClocks()

        clocks.advance(activities: [Self.agent(.working), Self.music(.playing)], registrationTimes: [:], now: Self.t0)

        #expect(clocks.nextDeadline == nil)
        #expect(clocks.reading.hiddenMusicSlotIDs.isEmpty)
        #expect(clocks.reading.attentionGlow == nil)
    }

    @Test("a paused track wakes the island when its note is due to leave")
    func pausedTrackSchedulesItsDeparture() {
        var clocks = IslandPresentationClocks()

        clocks.advance(activities: [Self.music(.paused)], registrationTimes: [:], now: Self.t0)
        #expect(clocks.nextDeadline == Self.t0.addingTimeInterval(20))

        clocks.advance(activities: [Self.music(.paused)], registrationTimes: [:], now: Self.t0.addingTimeInterval(20))
        #expect(clocks.reading.hiddenMusicSlotIDs == [MusicActivity.identity.rawValue])
        #expect(clocks.nextDeadline == nil)
    }

    @Test("a glow wakes the island when its passes are over")
    func glowSchedulesItsEnd() {
        var clocks = IslandPresentationClocks()

        clocks.advance(activities: [Self.agent(.waitingForUser)], registrationTimes: [:], now: Self.t0)
        #expect(clocks.reading.attentionGlow?.reason == .needsInput)
        #expect(clocks.nextDeadline == Self.t0.addingTimeInterval(22))

        clocks.advance(
            activities: [Self.agent(.waitingForUser)],
            registrationTimes: [:],
            now: Self.t0.addingTimeInterval(22)
        )
        #expect(clocks.reading.attentionGlow == nil)
    }

    /// Switched off in AI Integrations, the glow is neither drawn nor woken for,
    /// yet its moments are still tracked: switching it back on shows what is
    /// still running instead of replaying news from while it was off.
    @Test("a switched-off glow is hidden, and switching it on does not replay old news")
    func switchedOffGlowIsHidden() {
        var clocks = IslandPresentationClocks()
        clocks.showsAttentionGlow = false

        clocks.advance(activities: [Self.agent(.waitingForUser)], registrationTimes: [:], now: Self.t0)
        #expect(clocks.reading.attentionGlow == nil)
        #expect(clocks.nextDeadline == nil)

        clocks.showsAttentionGlow = true
        clocks.advance(
            activities: [Self.agent(.waitingForUser)],
            registrationTimes: [:],
            now: Self.t0.addingTimeInterval(10)
        )
        #expect(clocks.reading.attentionGlow?.startedAt == Self.t0, "the running glow shows where it stands")

        clocks.advance(
            activities: [Self.agent(.waitingForUser)],
            registrationTimes: [:],
            now: Self.t0.addingTimeInterval(30)
        )
        #expect(clocks.reading.attentionGlow == nil, "an unchanged question is not announced a second time")
    }

    /// The Settings test button shows the user what the switch controls — so it
    /// plays even with the switch off and with no agent running.
    @Test("a preview crosses once, whatever the switch says, and then ends")
    func previewPlaysOnce() {
        var clocks = IslandPresentationClocks()
        clocks.showsAttentionGlow = false

        clocks.previewAttentionGlow(at: Self.t0)
        clocks.advance(activities: [], registrationTimes: [:], now: Self.t0)
        #expect(clocks.reading.attentionGlow?.reason == .needsInput)
        #expect(clocks.reading.attentionGlow?.passCount == 1)
        #expect(clocks.nextDeadline == Self.t0.addingTimeInterval(2), "one two-second crossing, no rest after it")

        clocks.advance(activities: [], registrationTimes: [:], now: Self.t0.addingTimeInterval(2))
        #expect(clocks.reading.attentionGlow == nil)
        #expect(clocks.nextDeadline == nil)
    }

    @Test("pressing the test button again starts the preview over")
    func previewRestarts() {
        var clocks = IslandPresentationClocks()

        clocks.previewAttentionGlow(at: Self.t0)
        clocks.previewAttentionGlow(at: Self.t0.addingTimeInterval(1))
        clocks.advance(activities: [], registrationTimes: [:], now: Self.t0.addingTimeInterval(1))

        #expect(clocks.reading.attentionGlow?.startedAt == Self.t0.addingTimeInterval(1))
    }

    @Test("a real agent's glow takes precedence over a preview")
    func agentGlowOutranksPreview() {
        var clocks = IslandPresentationClocks()

        clocks.previewAttentionGlow(at: Self.t0)
        clocks.advance(activities: [Self.agent(.error)], registrationTimes: [:], now: Self.t0.addingTimeInterval(1))

        #expect(clocks.reading.attentionGlow?.reason == .failed)
    }

    /// A blocked agent's glow, its announcement and a paused note all end on
    /// clocks of their own; the island wakes for each in turn.
    @Test("the soonest clock wins, then the next")
    func soonestClockWins() {
        var clocks = IslandPresentationClocks()
        let blocked = Self.agent(.error, reason: .quotaExhausted)

        clocks.advance(activities: [blocked], registrationTimes: [:], now: Self.t0)
        #expect(clocks.nextDeadline == Self.t0.addingTimeInterval(22), "the glow ends first")

        clocks.advance(activities: [blocked], registrationTimes: [:], now: Self.t0.addingTimeInterval(22))
        #expect(clocks.nextDeadline == Self.t0.addingTimeInterval(60), "then the announcement")

        clocks.advance(
            activities: [blocked, Self.music(.paused)],
            registrationTimes: [:],
            now: Self.t0.addingTimeInterval(50)
        )
        #expect(clocks.nextDeadline == Self.t0.addingTimeInterval(60))

        clocks.advance(
            activities: [blocked, Self.music(.paused)],
            registrationTimes: [:],
            now: Self.t0.addingTimeInterval(60)
        )
        #expect(clocks.nextDeadline == Self.t0.addingTimeInterval(70), "then the paused note")
    }
}
