import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("AppleScriptMusicProvider")
@MainActor
struct AppleScriptMusicProviderTests {
    /// Every test drives the provider through a private, in-process
    /// `NotificationCenter` standing in for `DistributedNotificationCenter`, so
    /// the wake-up edge is delivered on the test's schedule and no real player
    /// app is ever contacted.
    private static func make(
        players: FakeMusicPlayerClient = FakeMusicPlayerClient()
    ) -> (AppleScriptMusicProvider, FakeMusicPlayerClient, NotificationCenter) {
        let center = NotificationCenter()
        let provider = AppleScriptMusicProvider(players: players, notifications: center)
        return (provider, players, center)
    }

    private static func post(_ target: MusicPlayerTarget, on center: NotificationCenter) {
        center.post(name: target.playbackNotificationName, object: nil)
    }

    private static func snapshot(
        _ title: String,
        artist: String = "Aphex Twin",
        state: MusicPlaybackState = .playing
    ) -> MusicPlayerSnapshot {
        MusicPlayerSnapshot(title: title, artist: artist, playbackState: state)
    }

    // MARK: - Targets

    @Test("observes exactly the two scriptable players the App Store build may target")
    func targetsAreSpotifyAndAppleMusic() {
        #expect(MusicPlayerTarget.allCases == [.spotify, .appleMusic])
        #expect(MusicPlayerTarget.spotify.bundleIdentifier == "com.spotify.client")
        #expect(MusicPlayerTarget.appleMusic.bundleIdentifier == "com.apple.Music")
    }

    /// The two notification names in `docs/06-activity-providers.md` are the
    /// provider's only wake-up source, so a typo in either is a silent provider.
    @Test("subscribes to the documented distributed notification names")
    func usesDocumentedNotificationNames() {
        let spotify = MusicPlayerTarget.spotify.playbackNotificationName
        let appleMusic = MusicPlayerTarget.appleMusic.playbackNotificationName

        #expect(spotify.rawValue == "com.spotify.client.PlaybackStateChanged")
        #expect(appleMusic.rawValue == "com.apple.Music.playerInfo")
    }

    @Test("names its backend for support purposes")
    func namesItsBackend() {
        let (provider, _, _) = Self.make()

        #expect(provider.backendName == "ScriptingBridge")
    }

    // MARK: - Cadence

    /// The update-cadence rule in `docs/06-activity-providers.md` is "purely
    /// event-driven, no polling of player state at any interval". A provider
    /// that queried on `startObserving` would already be reading state nobody
    /// asked about; the first read must come from a notification.
    @Test("queries no player until a notification wakes it")
    func doesNotQueryBeforeAnyNotification() {
        let (provider, players, _) = Self.make()

        provider.startObserving { _ in }

        #expect(players.queriedTargets.isEmpty)
    }

    @Test("emits the playing track when a player posts a change")
    func emitsOnNotification() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Nannou")
        var received: [NowPlaying?] = []

        provider.startObserving { received.append($0) }
        Self.post(.spotify, on: center)

        #expect(received.count == 1)
        #expect(received.first??.title == "Nannou")
        #expect(received.first??.artist == "Aphex Twin")
        #expect(received.first??.playbackState == .playing)
        #expect(received.first??.sourceApplicationName == "Spotify")
    }

    /// Either app's notification refreshes the whole picture: Music.app posting
    /// while Spotify is the one playing must not blank out Spotify's track.
    @Test("refreshes every target on any player's notification")
    func refreshesAllTargetsOnAnyNotification() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Nannou")
        var received: [NowPlaying?] = []

        provider.startObserving { received.append($0) }
        Self.post(.appleMusic, on: center)

        #expect(received.first??.title == "Nannou")
    }

    // MARK: - Selection

    @Test("prefers a playing player over a paused one")
    func playingWinsOverPaused() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Avril 14th", state: .paused)
        players.snapshots[.appleMusic] = Self.snapshot("Nannou", state: .playing)
        var received: [NowPlaying?] = []

        provider.startObserving { received.append($0) }
        Self.post(.spotify, on: center)

        #expect(received.first??.title == "Nannou")
        #expect(received.first??.sourceApplicationName == "Music")
    }

    /// With both players in the same state there is no better answer than "the
    /// one that just spoke", which also keeps the island from flapping between
    /// two paused players every time either posts.
    @Test("breaks a tie in favour of the player that posted the notification")
    func tieGoesToTheNotifyingPlayer() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Avril 14th")
        players.snapshots[.appleMusic] = Self.snapshot("Nannou")
        var received: [NowPlaying?] = []

        provider.startObserving { received.append($0) }
        Self.post(.appleMusic, on: center)

        #expect(received.first??.title == "Nannou")
    }

    // MARK: - Absence

    /// "Handles the app-not-running and permission-denied cases by producing no
    /// activity rather than erroring" — both arrive here as the same absent
    /// snapshot, which is the whole point of collapsing them at the seam.
    ///
    /// Nothing is emitted at all, not even a teardown: an activity that was
    /// never registered has nothing to tear down, the same judgement
    /// `ChargingProvider` makes about a machine that launches on battery.
    @Test("produces no activity when no player answers")
    func silenceWhenNoPlayerAnswers() {
        let (provider, _, center) = Self.make()
        var received: [NowPlaying?] = []

        provider.startObserving { received.append($0) }
        Self.post(.spotify, on: center)

        #expect(received.isEmpty)
    }

    @Test("tears down the activity when the playing player stops")
    func teardownWhenPlaybackStops() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Nannou")
        var received: [NowPlaying?] = []

        provider.startObserving { received.append($0) }
        Self.post(.spotify, on: center)
        players.snapshots[.spotify] = nil
        Self.post(.spotify, on: center)

        #expect(received.count == 2)
        #expect(received.last == .some(nil))
    }

    // MARK: - Deduplication

    /// The players post on every state change they consider interesting, and a
    /// repeat emission restarts the manager's dismiss window. Deduping on the
    /// emitted value is what keeps an unchanged track from pinning the island
    /// open, the same judgement `ChargingProvider` makes.
    @Test("stays quiet when a notification carries no change")
    func dedupesUnchangedState() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Nannou")
        var received: [NowPlaying?] = []

        provider.startObserving { received.append($0) }
        Self.post(.spotify, on: center)
        Self.post(.spotify, on: center)
        Self.post(.appleMusic, on: center)

        #expect(received.count == 1)
    }

    @Test("emits again when the track or play state actually changes")
    func emitsOnRealChange() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Nannou")
        var received: [String?] = []

        provider.startObserving { received.append($0?.title) }
        Self.post(.spotify, on: center)
        players.snapshots[.spotify] = Self.snapshot("Nannou", state: .paused)
        Self.post(.spotify, on: center)
        players.snapshots[.spotify] = Self.snapshot("Avril 14th")
        Self.post(.spotify, on: center)

        #expect(received == ["Nannou", "Nannou", "Avril 14th"])
    }

    @Test("stays quiet while nothing has ever played")
    func dedupesContinuedSilence() {
        let (provider, _, center) = Self.make()
        var received: [NowPlaying?] = []

        provider.startObserving { received.append($0) }
        Self.post(.spotify, on: center)
        Self.post(.spotify, on: center)

        #expect(received.isEmpty)
    }

    // MARK: - Lifecycle

    @Test("drops emissions once observation stops")
    func stopSuppressesEmissions() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Nannou")
        var received = 0

        provider.startObserving { _ in received += 1 }
        Self.post(.spotify, on: center)
        provider.stopObserving()
        players.snapshots[.spotify] = Self.snapshot("Avril 14th")
        Self.post(.spotify, on: center)

        #expect(received == 1)
    }

    /// Forgetting the last emission is part of stopping, for the reason
    /// `ChargingProvider` documents: a provider restarted into the state it was
    /// stopped in must report it rather than dedupe against a reading from
    /// before anyone was listening.
    @Test("re-reports the current track after a restart")
    func restartForgetsThePreviousEmission() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Nannou")
        var received: [String?] = []

        provider.startObserving { received.append($0?.title) }
        Self.post(.spotify, on: center)
        provider.stopObserving()
        provider.startObserving { received.append($0?.title) }
        Self.post(.spotify, on: center)

        #expect(received == ["Nannou", "Nannou"])
    }

    @Test("restarting observation replaces the previous observer")
    func restartReplacesObserver() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Nannou")
        var firstCount = 0
        var secondCount = 0

        provider.startObserving { _ in firstCount += 1 }
        provider.startObserving { _ in secondCount += 1 }
        Self.post(.spotify, on: center)

        #expect(firstCount == 0)
        #expect(secondCount == 1)
    }

    // MARK: - Transport

    @Test("routes transport commands to the player currently being reported")
    func routesTransportToTheReportedPlayer() {
        let (provider, players, center) = Self.make()
        players.snapshots[.appleMusic] = Self.snapshot("Nannou")

        provider.startObserving { _ in }
        Self.post(.appleMusic, on: center)
        for command in MusicTransportCommand.allCases {
            provider.send(command)
        }

        #expect(players.sentCommands.map(\.target) == [.appleMusic, .appleMusic, .appleMusic])
        #expect(players.sentCommands.map(\.command) == MusicTransportCommand.allCases)
    }

    @Test("re-routes transport after the reported player changes")
    func retargetsTransportAfterSourceChange() {
        let (provider, players, center) = Self.make()
        players.snapshots[.spotify] = Self.snapshot("Nannou")

        provider.startObserving { _ in }
        Self.post(.spotify, on: center)
        players.snapshots[.spotify] = nil
        players.snapshots[.appleMusic] = Self.snapshot("Avril 14th")
        Self.post(.appleMusic, on: center)
        provider.send(.nextTrack)

        #expect(players.sentCommands.map(\.target) == [.appleMusic])
    }

    /// "A backend that cannot honour the command drops it rather than erroring"
    /// — with nothing playing there is no honest target, and a music activity
    /// is never worth an alert.
    @Test("drops transport commands when no player is being reported")
    func dropsTransportWithoutASource() {
        let (provider, players, center) = Self.make()

        provider.startObserving { _ in }
        provider.send(.playPause)
        Self.post(.spotify, on: center)
        provider.send(.playPause)

        #expect(players.sentCommands.isEmpty)
    }
}

/// The ScriptingBridge seam's test double: answers for each target on the
/// test's schedule, exactly as `docs/11-testing-strategy.md` prescribes for a
/// source that can only be exercised for real on hardware with those apps
/// installed. An absent entry is the app-not-running and permission-denied case
/// the real client collapses into the same answer.
@MainActor
private final class FakeMusicPlayerClient: MusicPlayerQuerying {
    var snapshots: [MusicPlayerTarget: MusicPlayerSnapshot] = [:]
    private(set) var queriedTargets: [MusicPlayerTarget] = []
    private(set) var sentCommands: [(command: MusicTransportCommand, target: MusicPlayerTarget)] = []

    func snapshot(for target: MusicPlayerTarget) -> MusicPlayerSnapshot? {
        queriedTargets.append(target)
        return snapshots[target]
    }

    func send(_ command: MusicTransportCommand, to target: MusicPlayerTarget) {
        sentCommands.append((command, target))
    }
}
