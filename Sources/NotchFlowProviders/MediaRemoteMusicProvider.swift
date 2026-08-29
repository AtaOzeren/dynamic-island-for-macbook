import Foundation
import NotchFlowCore

/// The Direct build's music backend: system-wide now-playing observation
/// via `MediaRemoteBridgeProtocol`.
///
/// Unlike `AppleScriptMusicProvider` which can only observe Spotify and Music.app,
/// `MediaRemoteMusicProvider` receives system-wide media playback events from any
/// audio/video application (browsers, third-party players, etc.).
@MainActor
public final class MediaRemoteMusicProvider: MusicProvider {
    private let bridge: any MediaRemoteBridgeProtocol
    private var observer: NowPlayingObserver?
    private var lastReported: NowPlaying?

    public init(bridge: any MediaRemoteBridgeProtocol = DefaultMediaRemoteBridge()) {
        self.bridge = bridge
    }

    public var backendName: String { "MediaRemote" }

    public func startObserving(_ observer: @escaping NowPlayingObserver) {
        stopObserving()
        self.observer = observer

        bridge.startObserving { [weak self] snapshot in
            self?.handleSnapshot(snapshot)
        }
    }

    public func stopObserving() {
        bridge.stopObserving()
        observer = nil
        lastReported = nil
    }

    public func send(_ command: MusicTransportCommand) {
        bridge.send(command)
    }

    private func handleSnapshot(_ snapshot: MediaRemoteNowPlayingSnapshot?) {
        guard let snapshot = snapshot,
              let title = snapshot.title,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            if lastReported != nil {
                lastReported = nil
                observer?(nil)
            }
            return
        }

        let artist = snapshot.artist ?? ""
        let nowPlaying = NowPlaying(
            title: title,
            artist: artist,
            playbackState: snapshot.playbackState,
            sourceApplicationName: snapshot.sourceApplicationName
        )

        if nowPlaying != lastReported {
            lastReported = nowPlaying
            observer?(nowPlaying)
        }
    }
}
