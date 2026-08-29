import Foundation
import NotchFlowCore

private final class HandleWrapper: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer?

    init(pointer: UnsafeMutableRawPointer?) {
        self.pointer = pointer
    }

    deinit {
        if let pointer = pointer {
            dlclose(pointer)
        }
    }
}

/// Default implementation of `MediaRemoteBridgeProtocol` that dynamically loads
/// `MediaRemote.framework` at runtime via `dlopen`/`dlsym` if available in the process environment.
@MainActor
public final class DefaultMediaRemoteBridge: MediaRemoteBridgeProtocol {
    private typealias MRGetInfoFunc = @convention(c) (DispatchQueue, @escaping (CFDictionary) -> Void) -> Void
    private typealias MRCommandFunc = @convention(c) (Int32, CFDictionary?) -> Void

    private let handleWrapper: HandleWrapper
    private var observer: (@MainActor (MediaRemoteNowPlayingSnapshot?) -> Void)?
    private var notificationCenterToken: NSObjectProtocol?

    public init() {
        let pointer = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        self.handleWrapper = HandleWrapper(pointer: pointer)
    }

    public func startObserving(_ observer: @escaping @MainActor (MediaRemoteNowPlayingSnapshot?) -> Void) {
        stopObserving()
        self.observer = observer

        guard handleWrapper.pointer != nil else {
            return
        }

        notificationCenterToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fetchNowPlayingInfo()
            }
        }

        fetchNowPlayingInfo()
    }

    public func stopObserving() {
        if let token = notificationCenterToken {
            DistributedNotificationCenter.default().removeObserver(token)
            notificationCenterToken = nil
        }
        observer = nil
    }

    public func send(_ command: MusicTransportCommand) {
        guard let pointer = handleWrapper.pointer, let sym = dlsym(pointer, "MRMediaRemoteSendCommand") else { return }
        let sendCommand = unsafeBitCast(sym, to: MRCommandFunc.self)

        let commandID: Int32
        switch command {
        case .playPause:
            commandID = 2 // TogglePlayPause
        case .nextTrack:
            commandID = 4 // NextTrack
        case .previousTrack:
            commandID = 5 // PreviousTrack
        }

        sendCommand(commandID, nil)
    }

    private func fetchNowPlayingInfo() {
        guard let pointer = handleWrapper.pointer, let sym = dlsym(pointer, "MRMediaRemoteGetNowPlayingInfo") else { return }
        let getNowPlayingInfo = unsafeBitCast(sym, to: MRGetInfoFunc.self)

        getNowPlayingInfo(.main) { [weak self] dict in
            MainActor.assumeIsolated {
                let snapshot = self?.parseDictionary(dict)
                self?.observer?(snapshot)
            }
        }
    }

    private func parseDictionary(_ dict: CFDictionary) -> MediaRemoteNowPlayingSnapshot? {
        let nsDict = dict as NSDictionary

        let title = nsDict["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let artist = nsDict["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        let album = nsDict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
        let appName = nsDict["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] as? String
            ?? nsDict["kMRMediaRemoteNowPlayingInfoApplicationDisplayName"] as? String

        let rate = (nsDict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0.0
        let playbackState: MusicPlaybackState = rate > 0 ? .playing : .paused

        guard let title = title, !title.isEmpty else { return nil }

        return MediaRemoteNowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            sourceApplicationName: appName,
            playbackState: playbackState
        )
    }
}
