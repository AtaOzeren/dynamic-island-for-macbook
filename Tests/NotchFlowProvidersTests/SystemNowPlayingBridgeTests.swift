import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("System now-playing snapshot")
struct SystemNowPlayingBridgeTests {
    private static let keys = SystemNowPlayingDictionaryKeys(
        title: "title",
        artist: "artist",
        album: "album",
        sourceApplicationName: "sourceApplicationName",
        playbackRate: "playbackRate"
    ).withArtworkDataKey("artworkData")

    @Test("maps dictionary values to a snapshot")
    func mapsDictionaryValues() {
        let dictionary: NSDictionary = [
            Self.keys.title: "Windowlicker",
            Self.keys.artist: "Aphex Twin",
            Self.keys.album: "Windowlicker EP",
            Self.keys.sourceApplicationName: "Safari",
            Self.keys.playbackRate: 1,
        ]

        let snapshot = SystemNowPlayingSnapshot.parse(dictionary: dictionary, keys: Self.keys)

        #expect(snapshot.title == "Windowlicker")
        #expect(snapshot.artist == "Aphex Twin")
        #expect(snapshot.album == "Windowlicker EP")
        #expect(snapshot.sourceApplicationName == "Safari")
        #expect(snapshot.playbackState == .playing)
    }

    @Test("maps absent metadata and a zero playback rate")
    func mapsAbsentMetadata() {
        let dictionary: NSDictionary = [Self.keys.playbackRate: 0]

        let snapshot = SystemNowPlayingSnapshot.parse(dictionary: dictionary, keys: Self.keys)

        #expect(snapshot.title == nil)
        #expect(snapshot.artist == nil)
        #expect(snapshot.album == nil)
        #expect(snapshot.sourceApplicationName == nil)
        #expect(snapshot.playbackState == .paused)
    }

    @Test("maps artwork bytes supplied by MediaRemote")
    func mapsArtworkData() {
        let artwork = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let dictionary: NSDictionary = [Self.keys.artworkData: artwork]

        let snapshot = SystemNowPlayingSnapshot.parse(dictionary: dictionary, keys: Self.keys)

        #expect(snapshot.artworkData == artwork)
    }

    @Test("resolves playback state through the dedicated macOS 26 callback")
    func resolvesDedicatedPlaybackState() {
        let snapshot = SystemNowPlayingSnapshot.parse(dictionary: [:], keys: Self.keys)

        #expect(snapshot.resolvingPlaybackState(systemValue: 1).playbackState == .playing)
        #expect(snapshot.resolvingPlaybackState(systemValue: 2).playbackState == .paused)
        #expect(snapshot.resolvingPlaybackState(systemValue: 0).playbackState == .paused)
    }

    @Test("resolves source through the dedicated now-playing client callback")
    func resolvesDedicatedSourceApplication() {
        let snapshot = SystemNowPlayingSnapshot.parse(dictionary: [:], keys: Self.keys)

        #expect(
            snapshot.resolvingSourceApplicationName("Spotify").sourceApplicationName
                == "Spotify"
        )
    }
}
