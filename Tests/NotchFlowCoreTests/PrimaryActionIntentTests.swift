import Foundation
import Testing

@testable import NotchFlowCore

/// Todo 12's acceptance: `PrimaryAction` gains dispatch capability as a value,
/// without gaining a closure — the `Sendable`/`Equatable` guarantees its doc
/// comment says the design depends on must survive.
@Suite("PrimaryAction intents")
struct PrimaryActionIntentTests {
    private static let epoch = Date(timeIntervalSince1970: 0)

    @Test("stays Equatable, so ExpandedRow equality still holds")
    func remainsEquatable() {
        let one = PrimaryAction(title: "Open Spotify", intent: .openApplicationNamed("Spotify"))
        let same = PrimaryAction(title: "Open Spotify", intent: .openApplicationNamed("Spotify"))
        let different = PrimaryAction(title: "Open Spotify", intent: .openApplicationNamed("Music"))

        #expect(one == same)
        #expect(one != different)
    }

    @Test("an action with no intent is still constructible and still equal")
    func intentIsOptional() {
        let bare = PrimaryAction(title: "Dismiss", symbolName: "checkmark")

        #expect(bare.intent == nil)
        #expect(bare == PrimaryAction(title: "Dismiss", symbolName: "checkmark"))
    }

    @Test("music names the application its now-playing came from")
    func musicIntentNamesItsSource() {
        let activity = MusicActivity(
            nowPlaying: NowPlaying(
                title: "Track",
                artist: "Artist",
                playbackState: .playing,
                sourceApplicationName: "Spotify"
            )
        )

        #expect(activity.primaryAction?.intent == .openApplicationNamed("Spotify"))
    }

    @Test("music with no attributable source offers no action at all")
    func musicWithoutSourceOffersNothing() {
        let activity = MusicActivity(
            nowPlaying: NowPlaying(title: "Track", artist: "Artist", playbackState: .playing)
        )

        #expect(activity.primaryAction == nil)
    }

    @Test("an agent names its own application")
    func agentIntentNamesTheAgent() {
        let activity = AIAgentActivity(
            agent: .codex,
            sessionID: UUID(),
            state: .working,
            detail: "compiling"
        )

        #expect(activity.primaryAction?.intent == .openAgentApplication(.codex))
    }

    @Test("a running timer pauses, a paused timer resumes, an expired timer stops")
    func timerIntentsFollowState() {
        let running = TimerActivity(
            mode: .countdown(duration: .seconds(600)),
            schedule: .started(at: Self.epoch),
            at: Self.epoch
        )
        #expect(running.primaryAction?.intent == .pauseTimer)

        let paused = running.paused(at: Self.epoch)
        #expect(paused.primaryAction?.intent == .resumeTimer)

        let expired = TimerActivity(
            mode: .countdown(duration: .seconds(1)),
            schedule: .started(at: Self.epoch),
            at: Self.epoch.addingTimeInterval(5)
        )
        #expect(expired.isExpiring)
        #expect(expired.primaryAction?.intent == .stopTimer)
    }
}
