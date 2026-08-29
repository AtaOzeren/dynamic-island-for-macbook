#if DIRECT_BUILD
import Foundation
import NotchFlowCore
import NotchFlowProviders

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

@MainActor
final class DirectSystemNowPlayingBridge: SystemNowPlayingBridge {
    private typealias MRGetInfoFunc = @convention(c) (DispatchQueue, @escaping (CFDictionary) -> Void) -> Void
    private typealias MRCommandFunc = @convention(c) (Int32, CFDictionary?) -> Void

    private let handleWrapper: HandleWrapper
    private let dictionaryKeys = SystemNowPlayingDictionaryKeys(
        title: "kMRMediaRemoteNowPlayingInfoTitle",
        artist: "kMRMediaRemoteNowPlayingInfoArtist",
        album: "kMRMediaRemoteNowPlayingInfoAlbum",
        sourceApplicationName: "kMRMediaRemoteNowPlayingInfoClientDisplayName",
        playbackRate: "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    )
    private var observer: (@MainActor (SystemNowPlayingSnapshot?) -> Void)?
    private var notificationCenterToken: NSObjectProtocol?

    init() {
        let pointer = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        self.handleWrapper = HandleWrapper(pointer: pointer)
    }

    func startObserving(_ observer: @escaping @MainActor (SystemNowPlayingSnapshot?) -> Void) {
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
            Task { @MainActor [weak self] in
                self?.fetchNowPlayingInfo()
            }
        }

        registerForNowPlayingNotifications()
        fetchNowPlayingInfo()
    }

    func stopObserving() {
        if let token = notificationCenterToken {
            DistributedNotificationCenter.default().removeObserver(token)
            notificationCenterToken = nil
        }
        observer = nil
    }

    func send(_ command: MusicTransportCommand) {
        guard let handle = handleWrapper.pointer,
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand")
        else { return }

        let function = unsafeBitCast(symbol, to: MRCommandFunc.self)
        let commandValue: Int32
        switch command {
        case .playPause: commandValue = 2
        case .nextTrack: commandValue = 4
        case .previousTrack: commandValue = 5
        }
        function(commandValue, nil)
    }

    private func registerForNowPlayingNotifications() {
        guard let handle = handleWrapper.pointer,
              let symbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
        else { return }

        typealias RegisterFunc = @convention(c) (DispatchQueue) -> Void
        let function = unsafeBitCast(symbol, to: RegisterFunc.self)
        function(.main)
    }

    private func fetchNowPlayingInfo() {
        guard let handle = handleWrapper.pointer,
              let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        else {
            observer?(nil)
            return
        }

        let function = unsafeBitCast(symbol, to: MRGetInfoFunc.self)
        function(.main) { [weak self] dictionary in
            guard let self else { return }
            let snapshot = SystemNowPlayingSnapshot.parse(
                dictionary: dictionary as NSDictionary,
                keys: self.dictionaryKeys
            )
            Task { @MainActor [weak self] in
                self?.observer?(snapshot)
            }
        }
    }
}
#endif
