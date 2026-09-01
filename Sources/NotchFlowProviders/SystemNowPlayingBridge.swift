import Foundation
import NotchFlowCore

public struct SystemNowPlayingSnapshot: Equatable, Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public private(set) var sourceApplicationName: String?
    public private(set) var playbackState: MusicPlaybackState
    public private(set) var artworkData: Data?

    public init(
        title: String?,
        artist: String?,
        album: String? = nil,
        sourceApplicationName: String? = nil,
        playbackState: MusicPlaybackState = .playing
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.sourceApplicationName = sourceApplicationName
        self.playbackState = playbackState
        artworkData = nil
    }

    public static func parse(
        dictionary: NSDictionary,
        keys: SystemNowPlayingDictionaryKeys
    ) -> Self {
        Self(
            title: dictionary[keys.title] as? String,
            artist: dictionary[keys.artist] as? String,
            album: dictionary[keys.album] as? String,
            sourceApplicationName: dictionary[keys.sourceApplicationName] as? String,
            playbackState: playbackState(from: dictionary[keys.playbackRate])
        )
        .withArtworkData(dictionary[keys.artworkData] as? Data)
    }

    public func resolvingPlaybackState(systemValue: Int32) -> Self {
        resolvingPlaybackState(systemValue == 1 ? .playing : .paused)
    }

    public func resolvingPlaybackState(_ playbackState: MusicPlaybackState) -> Self {
        var copy = self
        copy.playbackState = playbackState
        return copy
    }

    public func resolvingSourceApplicationName(_ sourceApplicationName: String?) -> Self {
        var copy = self
        copy.sourceApplicationName = sourceApplicationName
        return copy
    }

    private func withArtworkData(_ artworkData: Data?) -> Self {
        var copy = self
        copy.artworkData = artworkData
        return copy
    }

    private static func playbackState(from value: Any?) -> MusicPlaybackState {
        let playbackRate = (value as? NSNumber)?.doubleValue ?? 0
        return playbackRate > 0 ? .playing : .paused
    }

}

public struct SystemNowPlayingDictionaryKeys: Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let sourceApplicationName: String
    public let playbackRate: String
    public private(set) var artworkData: String

    public init(
        title: String,
        artist: String,
        album: String,
        sourceApplicationName: String,
        playbackRate: String
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.sourceApplicationName = sourceApplicationName
        self.playbackRate = playbackRate
        artworkData = "artworkData"
    }

    public func withArtworkDataKey(_ artworkData: String) -> Self {
        var copy = self
        copy.artworkData = artworkData
        return copy
    }
}

@MainActor
public protocol SystemNowPlayingBridge: AnyObject {
    func startObserving(_ observer: @escaping @MainActor (SystemNowPlayingSnapshot?) -> Void)
    func stopObserving()
    func send(_ command: MusicTransportCommand)
}
