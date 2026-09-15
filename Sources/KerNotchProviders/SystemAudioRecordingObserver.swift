import CoreAudio
import Foundation

/// The microphone-in-use signal KerNotch is actually allowed to see.
///
/// `docs/12-api-feasibility-matrix.md` row 15 is blunt about this: there is no
/// documented Apple API whose stated purpose is "is any process using the
/// microphone", and the orange-dot indicator behind that question is not
/// exposed for third parties to read. The permission the row names —
/// `kTCCServiceMicrophone` — governs *KerNotch's own* capture, and
/// `docs/09-security-privacy-permissions.md` forbids the recording indicators
/// from requiring it: an indicator that demands the capability it reports on is
/// a worse trade than a narrower indicator.
///
/// What remains public, documented, permission-free and prompt-free is
/// CoreAudio's own account of its hardware:
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` reports whether a device's IO
/// is running for *any* process on the machine. Read against the devices that
/// have input streams, that is "someone is running the microphone" — the
/// boolean, and nothing about who or what is being said. KerNotch opens no
/// stream of its own and reads no audio content, so no microphone prompt is
/// ever triggered.
///
/// Its limits are recorded honestly in
/// `.omo/evidence/task-47-kernotch-v1/detection-limits.md` rather than papered
/// over with a guess.
///
/// Nothing here polls. Every read is driven by a CoreAudio property listener,
/// and the device list itself is listened to as well, so a microphone plugged
/// in mid-session is picked up on the edge rather than discovered by a sweep.
@MainActor
public final class SystemAudioRecordingObserver: RecordingObserving {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private let inputDeviceIdentifiers: @Sendable () -> [AudioObjectID]
    private let isDeviceRunning: @Sendable (AudioObjectID) -> Bool
    private let listeners: any AudioPropertyListening
    private let now: () -> Date

    private var latch = RecordingSessionLatch()
    private var observer: RecordingSessionObserver?

    /// The input devices currently carrying a running-somewhere listener, so a
    /// device-list change touches only the devices that actually came or went.
    private var watchedInputDevices: Set<AudioObjectID> = []

    public convenience init() {
        self.init(
            inputDeviceIdentifiers: { CoreAudioSystem.inputDeviceIdentifiers() },
            isDeviceRunning: { CoreAudioSystem.isRunningSomewhere($0) },
            listeners: CoreAudioPropertyListeners()
        )
    }

    init(
        inputDeviceIdentifiers: @escaping @Sendable () -> [AudioObjectID],
        isDeviceRunning: @escaping @Sendable (AudioObjectID) -> Bool,
        listeners: any AudioPropertyListening,
        now: @escaping () -> Date = Date.init
    ) {
        self.inputDeviceIdentifiers = inputDeviceIdentifiers
        self.isDeviceRunning = isDeviceRunning
        self.listeners = listeners
        self.now = now
    }

    public func startObserving(_ observer: @escaping RecordingSessionObserver) {
        stopObserving()
        self.observer = observer

        listenForDeviceListChanges()
        watchInputDevices()

        // A recording already in progress when KerNotch launches is a real
        // state, not an edge we missed, so it is read once here rather than
        // waited for.
        emitCurrentState()
    }

    public func stopObserving() {
        listeners.removeAll()
        watchedInputDevices = []
        latch.reset()
        observer = nil
    }

    /// Registered once per observation, never from inside its own callback.
    ///
    /// Re-registering it on every change is what turned a display change or a
    /// wake — each a burst of device-list notifications — into a runaway: any
    /// listener that failed to come off doubled on the next notification.
    private func listenForDeviceListChanges() {
        listeners.listen(to: .deviceList, on: Self.systemObject) { [weak self] in
            self?.deviceListDidChange()
        }
    }

    private func deviceListDidChange() {
        watchInputDevices()
        emitCurrentState()
    }

    /// Brings the per-device listeners in line with the input devices as they
    /// now stand: devices that left lose theirs, devices that arrived gain one,
    /// and devices that stayed are not touched. A microphone that appears
    /// mid-session is therefore observed on the same terms as one present at
    /// launch, without re-registering everything else.
    ///
    /// Only a device whose listener actually registered counts as watched. A
    /// registration can fail while the HAL is still settling after a wake, and a
    /// device recorded as watched anyway would never be tried again.
    private func watchInputDevices() {
        let currentDevices = Set(inputDeviceIdentifiers())

        for device in watchedInputDevices.subtracting(currentDevices) {
            listeners.stopListening(to: .isRunningSomewhere, on: device)
        }

        var watched = watchedInputDevices.intersection(currentDevices)
        for device in currentDevices.subtracting(watchedInputDevices) where watchRunningState(of: device) {
            watched.insert(device)
        }
        watchedInputDevices = watched
    }

    private func watchRunningState(of device: AudioObjectID) -> Bool {
        listeners.listen(to: .isRunningSomewhere, on: device) { [weak self] in
            self?.emitCurrentState()
        }
    }

    private func emitCurrentState() {
        guard let observer else { return }

        let isRecording = inputDeviceIdentifiers().contains(where: isDeviceRunning)

        guard latch.update(isRecording: isRecording, at: now) else { return }

        observer(latch.session)
    }
}

/// The CoreAudio properties this observer subscribes to, named so the call site
/// reads as intent rather than as four-character codes.
enum AudioProperty: Hashable {
    case deviceList
    case isRunningSomewhere

    var address: AudioObjectPropertyAddress {
        switch self {
        case .deviceList:
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        case .isRunningSomewhere:
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        }
    }
}

/// The subscription half of CoreAudio, behind a protocol for the reason
/// `docs/11-testing-strategy.md` gives for every hardware seam: the observer's
/// resubscribe-and-emit logic is CI-testable, the driver behind it is not.
///
/// A listener is identified by its property and object. Listening again to the
/// same pair replaces the earlier listener, so no call sequence can stack
/// duplicates on one property. `listen` reports whether the listener is in
/// place, so a caller never counts a property as watched when it is not.
@MainActor
protocol AudioPropertyListening: AnyObject {
    @discardableResult
    func listen(to property: AudioProperty, on object: AudioObjectID, changed: @escaping @MainActor () -> Void) -> Bool
    func stopListening(to property: AudioProperty, on object: AudioObjectID)
    func removeAll()
}

/// The query half of CoreAudio: the two reads this observer needs, with the
/// `AudioObjectGetPropertyData` ceremony kept in one place.
enum CoreAudioSystem {
    /// Every audio device that has at least one input stream — the set a
    /// microphone can be running on.
    static func inputDeviceIdentifiers() -> [AudioObjectID] {
        allDeviceIdentifiers().filter(hasInputStreams)
    }

    static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        var address = AudioProperty.isRunningSomewhere.address
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &isRunning)

        return status == noErr && isRunning != 0
    }

    private static func allDeviceIdentifiers() -> [AudioObjectID] {
        var address = AudioProperty.deviceList.address
        var size: UInt32 = 0

        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size
            ) == noErr
        else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size

        guard count > 0 else { return [] }

        var devices = [AudioObjectID](repeating: 0, count: count)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        )

        return status == noErr ? devices : []
    }

    /// A device counts as an input when its input-scoped stream configuration
    /// carries at least one buffer. The configuration is a variable-length
    /// `AudioBufferList`, so it is read into raw storage sized by CoreAudio
    /// rather than into a fixed struct.
    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        guard
            AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
            size >= UInt32(MemoryLayout<AudioBufferList>.size)
        else { return false }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else {
            return false
        }

        return storage.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers > 0
    }
}
