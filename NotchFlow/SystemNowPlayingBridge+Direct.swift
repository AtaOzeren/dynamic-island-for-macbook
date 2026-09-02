#if DIRECT_BUILD
    import Foundation
    import NotchFlowCore
    import NotchFlowProviders

    @MainActor
    private final class HandleWrapper {
        let pointer: UnsafeMutableRawPointer?

        init(pointer: UnsafeMutableRawPointer?) {
            self.pointer = pointer
        }

        isolated deinit {
            if let pointer = pointer {
                dlclose(pointer)
            }
        }
    }

    @MainActor
    final class DirectSystemNowPlayingBridge: SystemNowPlayingBridge {
        private typealias MRGetInfoCallback = @convention(block) (CFDictionary) -> Void
        private typealias MRGetPlaybackStateCallback = @convention(block) (Int32) -> Void
        private typealias MRGetClientCallback = @convention(block) (UnsafeRawPointer?) -> Void
        private typealias MRGetInfoFunc = @convention(c) (DispatchQueue, @escaping MRGetInfoCallback) -> Void
        private typealias MRGetPlaybackStateFunc = @convention(c) (DispatchQueue, @escaping MRGetPlaybackStateCallback) -> Void
        private typealias MRGetClientFunc = @convention(c) (DispatchQueue, @escaping MRGetClientCallback) -> Void
        private typealias MRGetClientStringFunc = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>?
        private typealias MRCommandFunc = @convention(c) (Int32, CFDictionary?) -> Void

        private static let notificationNames = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification",
        ]

        private let handleWrapper: HandleWrapper
        private let dictionaryKeys = SystemNowPlayingDictionaryKeys(
            title: "kMRMediaRemoteNowPlayingInfoTitle",
            artist: "kMRMediaRemoteNowPlayingInfoArtist",
            album: "kMRMediaRemoteNowPlayingInfoAlbum",
            sourceApplicationName: "kMRMediaRemoteNowPlayingInfoClientDisplayName",
            playbackRate: "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        ).withArtworkDataKey("kMRMediaRemoteNowPlayingInfoArtworkData")
        private var observer: (@MainActor (SystemNowPlayingSnapshot?) -> Void)?
        private var notificationCenterTokens: [NSObjectProtocol] = []
        private var latestSnapshot: SystemNowPlayingSnapshot?
        private var pendingInfoCallback: MRGetInfoCallback?
        private var pendingPlaybackStateCallback: MRGetPlaybackStateCallback?
        private var pendingClientCallback: MRGetClientCallback?
        private var isRegisteredForNotifications = false

        init() {
            let pointer = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
            self.handleWrapper = HandleWrapper(pointer: pointer)
        }

        func startObserving(_ observer: @escaping @MainActor (SystemNowPlayingSnapshot?) -> Void) {
            stopObserving()
            self.observer = observer
            beginObservation()
        }

        private func beginObservation() {
            guard observer != nil else { return }

            guard handleWrapper.pointer != nil else {
                return
            }

            notificationCenterTokens = Self.notificationNames.map { name in
                DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name(name),
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.fetchNowPlayingInfo()
                    }
                }
            }

            registerForNowPlayingNotifications()
            fetchNowPlayingInfo()
        }

        func stopObserving() {
            for token in notificationCenterTokens {
                DistributedNotificationCenter.default().removeObserver(token)
            }
            notificationCenterTokens.removeAll()
            unregisterForNowPlayingNotifications()
            latestSnapshot = nil
            pendingInfoCallback = nil
            pendingPlaybackStateCallback = nil
            pendingClientCallback = nil
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
            isRegisteredForNotifications = true
        }

        private func unregisterForNowPlayingNotifications() {
            guard isRegisteredForNotifications else { return }
            isRegisteredForNotifications = false
            guard let handle = handleWrapper.pointer,
                let symbol = dlsym(handle, "MRMediaRemoteUnregisterForNowPlayingNotifications")
            else { return }

            typealias UnregisterFunc = @convention(c) (DispatchQueue) -> Void
            let function = unsafeBitCast(symbol, to: UnregisterFunc.self)
            function(.main)
        }

        private func fetchNowPlayingInfo() {
            guard pendingInfoCallback == nil else { return }
            guard let handle = handleWrapper.pointer,
                let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
            else {
                observer?(nil)
                return
            }

            let function = unsafeBitCast(symbol, to: MRGetInfoFunc.self)
            let callback: MRGetInfoCallback = { [weak self] dictionary in
                MainActor.assumeIsolated {
                    self?.receiveNowPlayingDictionary(dictionary)
                }
            }
            pendingInfoCallback = callback
            function(.main, callback)
        }

        private func receiveNowPlayingDictionary(_ dictionary: CFDictionary) {
            pendingInfoCallback = nil
            let snapshot = SystemNowPlayingSnapshot.parse(
                dictionary: dictionary as NSDictionary,
                keys: dictionaryKeys
            )
            receiveMetadata(snapshot)
        }

        /// Publishes usable metadata before optional context callbacks complete.
        /// A missing private callback must never hide a title and artwork the
        /// system already returned successfully.
        private func receiveMetadata(_ snapshot: SystemNowPlayingSnapshot) {
            var merged = snapshot
            if let latestSnapshot {
                merged = merged
                    .resolvingPlaybackState(latestSnapshot.playbackState)
                    .resolvingSourceApplicationName(latestSnapshot.sourceApplicationName)
            }
            publish(merged)
            requestPlaybackState()
            requestSourceApplication()
        }

        private func requestPlaybackState() {
            guard pendingPlaybackStateCallback == nil else { return }
            guard let handle = handleWrapper.pointer,
                let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPlaybackState")
            else { return }

            let function = unsafeBitCast(symbol, to: MRGetPlaybackStateFunc.self)
            let callback: MRGetPlaybackStateCallback = { [weak self] systemValue in
                MainActor.assumeIsolated {
                    self?.pendingPlaybackStateCallback = nil
                    self?.receivePlaybackState(systemValue)
                }
            }
            pendingPlaybackStateCallback = callback
            function(.main, callback)
        }

        private func receivePlaybackState(_ systemValue: Int32) {
            guard let latestSnapshot else { return }
            publish(latestSnapshot.resolvingPlaybackState(systemValue: systemValue))
        }

        private func requestSourceApplication() {
            guard pendingClientCallback == nil else { return }
            guard let handle = handleWrapper.pointer,
                let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingClient")
            else { return }

            let function = unsafeBitCast(symbol, to: MRGetClientFunc.self)
            let callback: MRGetClientCallback = { [weak self] client in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pendingClientCallback = nil
                    self.receiveSourceApplicationName(
                        self.sourceApplicationName(from: client)
                    )
                }
            }
            pendingClientCallback = callback
            function(.main, callback)
        }

        private func receiveSourceApplicationName(_ sourceApplicationName: String?) {
            guard let latestSnapshot else { return }
            publish(latestSnapshot.resolvingSourceApplicationName(sourceApplicationName))
        }

        private func publish(_ snapshot: SystemNowPlayingSnapshot) {
            latestSnapshot = snapshot
            observer?(snapshot)
        }

        private func sourceApplicationName(from client: UnsafeRawPointer?) -> String? {
            guard let client, let handle = handleWrapper.pointer else { return nil }

            for symbolName in [
                "MRNowPlayingClientGetDisplayName",
                "MRNowPlayingClientGetBundleIdentifier",
            ] {
                guard let symbol = dlsym(handle, symbolName) else { continue }
                let function = unsafeBitCast(symbol, to: MRGetClientStringFunc.self)
                if let value = function(client)?.takeUnretainedValue() {
                    return value as String
                }
            }
            return nil
        }
    }
#endif
