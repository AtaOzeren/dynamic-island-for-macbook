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
    )

    @Test("maps dictionary values to a snapshot")
    func mapsDictionaryValues() {
        let dictionary: NSDictionary = [
            Self.keys.title: "Windowlicker",
            Self.keys.artist: "Aphex Twin",
            Self.keys.album: "Windowlicker EP",
            Self.keys.sourceApplicationName: "Safari",
            Self.keys.playbackRate: 1
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
}
