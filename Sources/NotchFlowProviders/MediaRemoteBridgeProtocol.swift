import Foundation
import NotchFlowCore

/// A snapshot of now-playing info emitted by MediaRemote.
public struct MediaRemoteNowPlayingSnapshot: Equatable, Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let sourceApplicationName: String?
    public let playbackState: MusicPlaybackState

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
    }
}

/// Seam for accessing the system-wide MediaRemote private framework.
@MainActor
public protocol MediaRemoteBridgeProtocol: AnyObject {
    /// Starts observing MediaRemote now-playing notifications and state.
    func startObserving(_ observer: @escaping @MainActor (MediaRemoteNowPlayingSnapshot?) -> Void)

    /// Stops observing.
    func stopObserving()

    /// Sends transport commands to MediaRemote.
    func send(_ command: MusicTransportCommand)
}
