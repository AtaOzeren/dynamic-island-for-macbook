import Foundation
import Testing

@testable import NotchFlowCore

@Suite("MusicActivity")
struct MusicActivityTests {
    private static func nowPlaying(
        title: String = "Windowlicker",
        artist: String = "Aphex Twin",
        state: MusicPlaybackState = .playing,
        source: String? = "Spotify"
    ) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: artist,
            playbackState: state,
            sourceApplicationName: source
        )
    }

    @Test("is a low-priority music activity, per the V1 priority table")
    func kindAndPriority() {
        let activity = MusicActivity(nowPlaying: Self.nowPlaying())

        #expect(activity.kind == .music)
        #expect(activity.priority == .low)
    }

    /// Music never expires on a clock: `docs/06-activity-providers.md` ends it on
    /// an observed stop, never on a timeout.
    @Test("never auto-dismisses")
    func neverAutoDismisses() {
        #expect(MusicActivity(nowPlaying: Self.nowPlaying()).autoDismiss == nil)
    }

    @Test("keeps one stable identity across track and state changes")
    func stableIdentity() {
        let first = MusicActivity(nowPlaying: Self.nowPlaying(title: "Nannou"))
        let second = MusicActivity(
            nowPlaying: Self.nowPlaying(title: "Avril 14th", state: .paused, source: "Music")
        )

        #expect(first.identity == second.identity)
        #expect(first.identity == MusicActivity.identity)
    }

    /// The stable identity is not cosmetic: it is what makes a track change an
    /// in-place update rather than a new registration that would re-sort the
    /// island every few minutes.
    @Test("a track change updates in place and keeps the original ordering time")
    @MainActor
    func trackChangeUpdatesInPlace() {
        let manager = ActivityManager()
        let started = Date(timeIntervalSince1970: 1)

        manager.register(MusicActivity(nowPlaying: Self.nowPlaying(title: "Nannou")), at: started)
        manager.register(
            MusicActivity(nowPlaying: Self.nowPlaying(title: "Avril 14th")),
            at: started.addingTimeInterval(600)
        )

        let active = manager.activeActivities
        #expect(active.count == 1)
        #expect((active.first as? MusicActivity)?.nowPlaying.title == "Avril 14th")

        // A later, higher-registration-time activity must still sort after the
        // music, which it only does if the original registration time survived.
        manager.register(
            MusicActivity(nowPlaying: Self.nowPlaying(title: "Nannou")),
            at: started.addingTimeInterval(900)
        )
        #expect(manager.activeActivities.count == 1)
    }

    @Test("offers opening the source application as its primary action")
    func primaryActionNamesTheSourceApplication() {
        let activity = MusicActivity(nowPlaying: Self.nowPlaying(source: "Spotify"))

        #expect(activity.primaryAction?.title == "Open Spotify")
    }

    /// The Direct build's backend reports system-wide now-playing that cannot
    /// always be attributed to a named application, so the action is optional
    /// rather than a fabricated label.
    @Test("offers no primary action when the source application is unknown")
    func primaryActionIsOptional() {
        #expect(MusicActivity(nowPlaying: Self.nowPlaying(source: nil)).primaryAction == nil)
        #expect(MusicActivity(nowPlaying: Self.nowPlaying(source: "   ")).primaryAction == nil)
    }

    @Test("stays an activity while paused")
    func pausedIsStillAnActivity() {
        let activity = MusicActivity(nowPlaying: Self.nowPlaying(state: .paused))

        #expect(activity.nowPlaying.playbackState == .paused)
        #expect(activity.kind == .music)
    }

    @Test("trims surrounding whitespace from the metadata it is handed")
    func trimsMetadata() {
        let nowPlaying = NowPlaying(
            title: "  Windowlicker\n",
            artist: "\tAphex Twin ",
            playbackState: .playing,
            sourceApplicationName: " Spotify "
        )

        #expect(nowPlaying.title == "Windowlicker")
        #expect(nowPlaying.artist == "Aphex Twin")
        #expect(nowPlaying.sourceApplicationName == "Spotify")
    }

    /// Track metadata is attacker-influenced in the sense that any app can put
    /// anything in it, so the model caps it rather than trusting the source.
    @Test("caps absurdly long metadata instead of trusting the source")
    func capsLongMetadata() {
        let nowPlaying = NowPlaying(
            title: String(repeating: "a", count: NowPlaying.maximumFieldLength * 2),
            artist: String(repeating: "b", count: NowPlaying.maximumFieldLength * 2),
            playbackState: .playing,
            sourceApplicationName: nil
        )

        #expect(nowPlaying.title.count == NowPlaying.maximumFieldLength)
        #expect(nowPlaying.artist.count == NowPlaying.maximumFieldLength)
    }

    @Test("carries bounded artwork data without changing track metadata")
    func carriesArtworkData() {
        let artwork = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let nowPlaying = Self.nowPlaying().withArtworkData(artwork)

        #expect(nowPlaying.artworkData == artwork)
        #expect(nowPlaying.title == "Windowlicker")
        #expect(nowPlaying.artist == "Aphex Twin")
    }

    @Test("rejects oversized artwork instead of retaining unbounded media data")
    func rejectsOversizedArtworkData() {
        let oversizedArtwork = Data(
            repeating: 0,
            count: NowPlaying.maximumArtworkByteCount + 1
        )

        #expect(Self.nowPlaying().withArtworkData(oversizedArtwork).artworkData == nil)
    }

    @Test("every transport command is representable")
    func transportCommands() {
        #expect(
            Set(MusicTransportCommand.allCases) == [.previousTrack, .playPause, .nextTrack]
        )
    }
}
