import Foundation
import Testing
@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("MediaRemoteMusicProvider")
@MainActor
struct MediaRemoteMusicProviderTests {

    final class FakeMediaRemoteBridge: MediaRemoteBridgeProtocol {
        var observer: (@MainActor (MediaRemoteNowPlayingSnapshot?) -> Void)?
        var sentCommands: [MusicTransportCommand] = []
        var isObserving = false

        func startObserving(_ observer: @escaping @MainActor (MediaRemoteNowPlayingSnapshot?) -> Void) {
            self.observer = observer
            self.isObserving = true
        }

        func stopObserving() {
            self.observer = nil
            self.isObserving = false
        }

        func send(_ command: MusicTransportCommand) {
            sentCommands.append(command)
        }

        func emit(_ snapshot: MediaRemoteNowPlayingSnapshot?) {
            observer?(snapshot)
        }
    }

    @Test("reports MediaRemote as backendName")
    func backendNameIsMediaRemote() {
        let bridge = FakeMediaRemoteBridge()
        let provider = MediaRemoteMusicProvider(bridge: bridge)
        #expect(provider.backendName == "MediaRemote")
    }

    @Test("emits NowPlaying when bridge receives playing track snapshot")
    func emitsNowPlayingOnPlayingTrack() {
        let bridge = FakeMediaRemoteBridge()
        let provider = MediaRemoteMusicProvider(bridge: bridge)

        var emitted: [NowPlaying?] = []
        provider.startObserving { emitted.append($0) }

        let snapshot = MediaRemoteNowPlayingSnapshot(
            title: "Windowlicker",
            artist: "Aphex Twin",
            album: "Windowlicker EP",
            sourceApplicationName: "Safari",
            playbackState: .playing
        )
        bridge.emit(snapshot)

        #expect(emitted.count == 1)
        #expect(emitted[0]?.title == "Windowlicker")
        #expect(emitted[0]?.artist == "Aphex Twin")
        #expect(emitted[0]?.playbackState == .playing)
        #expect(emitted[0]?.sourceApplicationName == "Safari")
    }

    @Test("emits NowPlaying with paused state when track is paused")
    func emitsNowPlayingOnPausedTrack() {
        let bridge = FakeMediaRemoteBridge()
        let provider = MediaRemoteMusicProvider(bridge: bridge)

        var emitted: [NowPlaying?] = []
        provider.startObserving { emitted.append($0) }

        let snapshot = MediaRemoteNowPlayingSnapshot(
            title: "Selected Ambient Works",
            artist: "Aphex Twin",
            playbackState: .paused
        )
        bridge.emit(snapshot)

        #expect(emitted.count == 1)
        #expect(emitted[0]?.title == "Selected Ambient Works")
        #expect(emitted[0]?.playbackState == .paused)
    }

    @Test("emits nil when bridge receives nil snapshot or empty title")
    func emitsNilOnEmptySnapshot() {
        let bridge = FakeMediaRemoteBridge()
        let provider = MediaRemoteMusicProvider(bridge: bridge)

        var emitted: [NowPlaying?] = []
        provider.startObserving { emitted.append($0) }

        bridge.emit(MediaRemoteNowPlayingSnapshot(title: "Track", artist: "Artist", playbackState: .playing))
        #expect(emitted.count == 1)

        bridge.emit(nil)
        #expect(emitted.count == 2)
        #expect(emitted[1] == nil)

        bridge.emit(MediaRemoteNowPlayingSnapshot(title: "   ", artist: "Artist", playbackState: .playing))
        #expect(emitted.count == 2)
    }

    @Test("deduplicates identical consecutive now playing emissions")
    func deduplicatesIdenticalEmissions() {
        let bridge = FakeMediaRemoteBridge()
        let provider = MediaRemoteMusicProvider(bridge: bridge)

        var emitted: [NowPlaying?] = []
        provider.startObserving { emitted.append($0) }

        let snapshot = MediaRemoteNowPlayingSnapshot(
            title: "Alberto Balsalm",
            artist: "Aphex Twin",
            playbackState: .playing
        )

        bridge.emit(snapshot)
        bridge.emit(snapshot)
        bridge.emit(snapshot)

        #expect(emitted.count == 1)
    }

    @Test("forwards transport commands to bridge")
    func forwardsTransportCommands() {
        let bridge = FakeMediaRemoteBridge()
        let provider = MediaRemoteMusicProvider(bridge: bridge)

        provider.send(.playPause)
        provider.send(.nextTrack)
        provider.send(.previousTrack)

        #expect(bridge.sentCommands == [.playPause, .nextTrack, .previousTrack])
    }

    @Test("stopObserving cleans up bridge observation and observer")
    func stopObservingCleansUp() {
        let bridge = FakeMediaRemoteBridge()
        let provider = MediaRemoteMusicProvider(bridge: bridge)

        var emittedCount = 0
        provider.startObserving { _ in emittedCount += 1 }
        #expect(bridge.isObserving == true)

        provider.stopObserving()
        #expect(bridge.isObserving == false)

        bridge.emit(MediaRemoteNowPlayingSnapshot(title: "Track", artist: "Artist", playbackState: .playing))
        #expect(emittedCount == 0)
    }
}
