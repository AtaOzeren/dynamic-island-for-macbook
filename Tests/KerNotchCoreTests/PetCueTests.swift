import Foundation
import Testing

@testable import KerNotchCore

/// What the pet notices on the island: news as it arrives, never a state held,
/// and the mood of whatever is going on.
@Suite("Pet cues")
struct PetCueTests {
    private static let session = UUID()
    private static let other = UUID()

    private static func agent(
        _ state: AIAgentState,
        session: UUID = session,
        root: UUID? = nil,
        reason: AIAgentFailureReason? = nil
    ) -> AIAgentActivity {
        AIAgentActivity(
            agent: .claudeCode,
            sessionID: session,
            rootSessionID: root,
            state: state,
            reason: reason,
            detail: "Editing App.swift"
        )
    }

    private static func music(_ state: MusicPlaybackState) -> MusicActivity {
        MusicActivity(
            nowPlaying: NowPlaying(
                title: "Windowlicker",
                artist: "Aphex Twin",
                playbackState: state,
                sourceApplicationName: "Spotify"
            )
        )
    }

    private static func charging(_ state: ChargingState) -> ChargingActivity {
        ChargingActivity(state: state, level: BatteryLevel(fraction: 0.5))
    }

    private static func countdown(expiring: Bool) -> TimerActivity {
        let start = Date(timeIntervalSince1970: 0)
        let timer = TimerActivity.started(.countdown(duration: .seconds(60)), at: start)
        return timer.advanced(to: start.addingTimeInterval(expiring ? 61 : 30))
    }

    @Test("an agent's news is answered once, when it arrives")
    func agentNewsArrivesOnce() {
        var reader = PetCueReader()

        #expect(reader.read(activities: [Self.agent(.working)], isExpanded: false, at: 0).moments.isEmpty)
        #expect(
            reader.read(activities: [Self.agent(.waitingForUser)], isExpanded: false, at: 1).moments == [.agentAsked])
        #expect(reader.read(activities: [Self.agent(.waitingForUser)], isExpanded: false, at: 2).moments.isEmpty)
        #expect(
            reader.read(activities: [Self.agent(.completed)], isExpanded: false, at: 3).moments == [.agentCompleted])
        #expect(reader.read(activities: [Self.agent(.error)], isExpanded: false, at: 4).moments == [.agentFailed])
    }

    @Test("running out of quota is its own news")
    func quotaIsItsOwnNews() {
        var reader = PetCueReader()
        let cues = reader.read(
            activities: [Self.agent(.error, reason: .quotaExhausted)],
            isExpanded: false,
            at: 0
        )

        #expect(cues.moments == [.quotaExhausted])
        #expect(cues.mood == .napping)
    }

    /// Its instance is still working: a green light for every delegated step
    /// would drown the one for the task itself.
    @Test("a sub-agent finishing is not news, a sub-agent asking is")
    func subagentNews() {
        var reader = PetCueReader()
        let root = UUID()

        #expect(reader.read(activities: [Self.agent(.completed, root: root)], isExpanded: false, at: 0).moments.isEmpty)
        #expect(
            reader.read(activities: [Self.agent(.waitingForUser, root: root)], isExpanded: false, at: 1).moments
                == [.agentAsked]
        )
    }

    @Test("the island opening and closing are news, but not the first look at it")
    func islandComingsAndGoings() {
        var reader = PetCueReader()

        #expect(reader.read(activities: [], isExpanded: true, at: 0).moments.isEmpty)
        #expect(reader.read(activities: [], isExpanded: false, at: 1).moments == [.islandClosed])
        #expect(reader.read(activities: [], isExpanded: false, at: 2).moments.isEmpty)
        #expect(reader.read(activities: [], isExpanded: true, at: 3).moments == [.islandOpened])
    }

    @Test("a countdown running out rings once")
    func timerRingsOnce() {
        var reader = PetCueReader()

        #expect(reader.read(activities: [Self.countdown(expiring: false)], isExpanded: false, at: 0).moments.isEmpty)
        #expect(
            reader.read(activities: [Self.countdown(expiring: true)], isExpanded: false, at: 1).moments == [
                .timerExpired
            ]
        )
        #expect(reader.read(activities: [Self.countdown(expiring: true)], isExpanded: false, at: 2).moments.isEmpty)
    }

    /// The cable going in reads as plugged in, then charging: one event.
    @Test("the charger going in is one piece of news, however the battery reports it")
    func chargerOnce() {
        var reader = PetCueReader()

        #expect(
            reader.read(activities: [Self.charging(.pluggedIn)], isExpanded: false, at: 0).moments == [
                .chargerConnected
            ])
        #expect(reader.read(activities: [Self.charging(.charging)], isExpanded: false, at: 1).moments.isEmpty)
        #expect(reader.read(activities: [], isExpanded: false, at: 2).moments.isEmpty)
        #expect(reader.read(activities: [Self.charging(.onBattery)], isExpanded: false, at: 3).moments.isEmpty)
        #expect(
            reader.read(activities: [Self.charging(.charging)], isExpanded: false, at: 4).moments == [.chargerConnected]
        )
    }

    @Test("the watchdog's notice is news when it appears")
    func watchdogNotice() {
        var reader = PetCueReader()
        let notice = WatchdogNoticeActivity(didRelaunch: true)

        #expect(reader.read(activities: [notice], isExpanded: false, at: 0).moments == [.cpuStrained])
        #expect(reader.read(activities: [notice], isExpanded: false, at: 1).moments.isEmpty)
    }

    @Test(
        "the strongest of what is going on sets the mood",
        arguments: [
            ([any Activity](), PetMood.idle(since: 5)),
            ([PetCueTests.music(.paused)], .calm),
            ([PetCueTests.music(.playing)], .listening),
            ([PetCueTests.music(.playing), PetCueTests.agent(.working)], .digging),
            ([PetCueTests.agent(.thinking), DiscordCallActivity(channel: nil, isMuted: nil)], .onCall),
            (
                [DiscordCallActivity(channel: nil, isMuted: nil), PetCueTests.agent(.error, reason: .quotaExhausted)],
                .napping
            ),
            (
                [
                    PetCueTests.agent(.error, reason: .quotaExhausted),
                    PetCueTests.agent(.waitingForUser, session: PetCueTests.other),
                ], .asking
            ),
            ([PetCueTests.agent(.waitingForUser), RecordingActivity.started(.screen, at: .distantPast)], .hiding),
            ([RecordingActivity.started(.audio, at: .distantPast)], .calm),
        ] as [([any Activity], PetMood)]
    )
    func moodFollowsTheStrongest(activities: [any Activity], mood: PetMood) {
        var reader = PetCueReader()

        #expect(reader.read(activities: activities, isExpanded: false, at: 5).mood == mood)
    }

    /// The nap is counted from the island emptying, not from the last refresh.
    @Test("an empty island is empty since the first time it was seen empty")
    func idleSinceTheIslandEmptied() {
        var reader = PetCueReader()

        #expect(reader.read(activities: [], isExpanded: false, at: 10).mood == .idle(since: 10))
        #expect(reader.read(activities: [], isExpanded: false, at: 70).mood == .idle(since: 10))
        #expect(reader.read(activities: [Self.music(.paused)], isExpanded: false, at: 80).mood == .calm)
        #expect(reader.read(activities: [], isExpanded: false, at: 90).mood == .idle(since: 90))
    }
}
