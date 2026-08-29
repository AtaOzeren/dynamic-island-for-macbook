import Testing
@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("MusicProvider")
@MainActor
struct MusicProviderTests {
    private static func nowPlaying(
        _ title: String,
        state: MusicPlaybackState = .playing,
        source: String? = "Spotify"
    ) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: "Aphex Twin",
            playbackState: state,
            sourceApplicationName: source
        )
    }

    @Test("maps now-playing metadata onto the shared music activity")
    func mapsNowPlayingToActivity() {
        let activity = musicActivity(for: Self.nowPlaying("Nannou"))

        #expect(activity?.nowPlaying.title == "Nannou")
        #expect(activity?.kind == .music)
        #expect(activity?.priority == .low)
    }

    /// Nothing playing means no activity at all, rather than an activity
    /// describing silence — the teardown rule in `docs/06-activity-providers.md`.
    @Test("produces no activity when nothing is playing")
    func noActivityWhenSilent() {
        #expect(musicActivity(for: nil) == nil)
    }

    @Test("forwards every emission while observing")
    func forwardsEmissions() {
        let provider = FakeMusicProvider()
        var received: [String?] = []

        provider.startObserving { nowPlaying in
            received.append(nowPlaying?.title)
        }
        provider.emit(Self.nowPlaying("Nannou"))
        provider.emit(Self.nowPlaying("Avril 14th", state: .paused))
        provider.emit(nil)

        #expect(received == ["Nannou", "Avril 14th", nil])
        #expect(provider.startCount == 1)
    }

    @Test("drops emissions once observation stops")
    func stopSuppressesEmissions() {
        let provider = FakeMusicProvider()
        var receivedCount = 0

        provider.startObserving { _ in receivedCount += 1 }
        provider.emit(Self.nowPlaying("Nannou"))
        provider.stopObserving()
        provider.emit(Self.nowPlaying("Avril 14th"))

        #expect(receivedCount == 1)
        #expect(provider.stopCount == 1)
        #expect(provider.hasObserver == false)
    }

    @Test("restarting observation replaces the previous observer")
    func restartReplacesObserver() {
        let provider = FakeMusicProvider()
        var firstCount = 0
        var secondCount = 0

        provider.startObserving { _ in firstCount += 1 }
        provider.startObserving { _ in secondCount += 1 }
        provider.emit(Self.nowPlaying("Nannou"))

        #expect(firstCount == 0)
        #expect(secondCount == 1)
    }

    @Test("sends every transport command through to the backend")
    func sendsTransportCommands() {
        let provider = FakeMusicProvider()

        for command in MusicTransportCommand.allCases {
            provider.send(command)
        }

        #expect(provider.sentCommands == MusicTransportCommand.allCases)
    }

    /// Todo 44 puts the active backend's name in the about pane; the protocol is
    /// where that name has to come from, since the backend type itself is
    /// selected at compile time and invisible above this seam.
    @Test("names its backend for support purposes")
    func namesItsBackend() {
        let provider: any MusicProvider = FakeMusicProvider()

        #expect(provider.backendName == "Fake")
    }
}

/// The seam's test double: the `docs/11-testing-strategy.md` pattern of a fake
/// conforming to the same protocol as the real backend, emitting on the test's
/// schedule instead of the OS's.
private final class FakeMusicProvider: MusicProvider {
    private var observer: NowPlayingObserver?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var sentCommands: [MusicTransportCommand] = []

    let backendName = "Fake"

    var hasObserver: Bool { observer != nil }

    func startObserving(_ observer: @escaping NowPlayingObserver) {
        startCount += 1
        self.observer = observer
    }

    func stopObserving() {
        stopCount += 1
        observer = nil
    }

    func send(_ command: MusicTransportCommand) {
        sentCommands.append(command)
    }

    func emit(_ nowPlaying: NowPlaying?) {
        observer?(nowPlaying)
    }
}
