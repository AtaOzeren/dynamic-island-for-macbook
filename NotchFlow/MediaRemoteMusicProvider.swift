#if DIRECT_BUILD
    import Foundation
    import NotchFlowCore
    import NotchFlowProviders

    @MainActor
    final class MediaRemoteMusicProvider: MusicProvider {
        private let bridge: any SystemNowPlayingBridge
        private var observer: NowPlayingObserver?
        private var lastReported: NowPlaying?

        init(bridge: any SystemNowPlayingBridge = DirectSystemNowPlayingBridge()) {
            self.bridge = bridge
        }

        var backendName: String { "MediaRemote" }

        func startObserving(_ observer: @escaping NowPlayingObserver) {
            stopObserving()
            self.observer = observer

            bridge.startObserving { [weak self] snapshot in
                self?.handleSnapshot(snapshot)
            }
        }

        func stopObserving() {
            bridge.stopObserving()
            observer = nil
            lastReported = nil
        }

        func send(_ command: MusicTransportCommand) {
            bridge.send(command)
        }

        private func handleSnapshot(_ snapshot: SystemNowPlayingSnapshot?) {
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

            let nowPlaying = NowPlaying(
                title: title,
                artist: snapshot.artist ?? "",
                playbackState: snapshot.playbackState,
                sourceApplicationName: snapshot.sourceApplicationName
            )

            guard nowPlaying != lastReported else { return }
            lastReported = nowPlaying
            observer?(nowPlaying)
        }
    }
#endif
