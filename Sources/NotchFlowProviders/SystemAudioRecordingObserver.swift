import CoreAudio
import Foundation

/// The microphone-in-use signal NotchFlow is actually allowed to see.
///
/// `docs/12-api-feasibility-matrix.md` row 15 is blunt about this: there is no
/// documented Apple API whose stated purpose is "is any process using the
/// microphone", and the orange-dot indicator behind that question is not
/// exposed for third parties to read. The permission the row names —
/// `kTCCServiceMicrophone` — governs *NotchFlow's own* capture, and
/// `docs/09-security-privacy-permissions.md` forbids the recording indicators
/// from requiring it: an indicator that demands the capability it reports on is
/// a worse trade than a narrower indicator.
///
/// What remains public, documented, permission-free and prompt-free is
/// CoreAudio's own account of its hardware:
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` reports whether a device's IO
/// is running for *any* process on the machine. Read against the devices that
/// have input streams, that is "someone is running the microphone" — the
/// boolean, and nothing about who or what is being said. NotchFlow opens no
/// stream of its own and reads no audio content, so no microphone prompt is
/// ever triggered.
///
/// Its limits are recorded honestly in
/// `.omo/evidence/task-47-notchflow-v1/detection-limits.md` rather than papered
/// over with a guess.
///
/// Nothing here polls. Every read is driven by a CoreAudio property listener,
/// and the device list itself is listened to as well, so a microphone plugged
/// in mid-session is picked up on the edge rather than discovered by a sweep.
@MainActor
public final class SystemAudioRecordingObserver: RecordingObserving {
    private let inputDeviceIdentifiers: @Sendable () -> [AudioObjectID]
    private let isDeviceRunning: @Sendable (AudioObjectID) -> Bool
    private let listeners: any AudioPropertyListening
    private let now: () -> Date

    private var latch = RecordingSessionLatch()
    private var observer: RecordingSessionObserver?

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

        subscribeToDevices()

        // A recording already in progress when NotchFlow launches is a real
        // state, not an edge we missed, so it is read once here rather than
        // waited for.
        emitCurrentState()
    }

    public func stopObserving() {
        listeners.removeAll()
        latch.reset()
        observer = nil
    }

    /// The device list is itself a listened-to property: when a microphone is
    /// attached or removed the per-device subscriptions are rebuilt against the
    /// list as it now stands, so a device that appears mid-session is observed
    /// on the same terms as one present at launch.
    private func subscribeToDevices() {
        listeners.removeAll()

        listeners.listen(to: .deviceList, on: AudioObjectID(kAudioObjectSystemObject)) { [weak self] in
            self?.subscribeToDevices()
            self?.emitCurrentState()
        }

        for device in inputDeviceIdentifiers() {
            listeners.listen(to: .isRunningSomewhere, on: device) { [weak self] in
                self?.emitCurrentState()
            }
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
@MainActor
protocol AudioPropertyListening: AnyObject {
    func listen(to property: AudioProperty, on object: AudioObjectID, changed: @escaping @MainActor () -> Void)
    func removeAll()
}

/// Real CoreAudio property listeners, registered on the main queue and torn
/// down as a set. Each block must be handed back to CoreAudio to deregister, so
/// the block is retained alongside the object and address it was registered
/// for.
@MainActor
final class CoreAudioPropertyListeners: AudioPropertyListening {
    private struct Registration {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private var registrations: [Registration] = []

    func listen(
        to property: AudioProperty,
        on object: AudioObjectID,
        changed: @escaping @MainActor () -> Void
    ) {
        var address = property.address
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { changed() }
        }

        let status = AudioObjectAddPropertyListenerBlock(object, &address, .main, block)

        guard status == noErr else { return }

        registrations.append(Registration(object: object, address: address, block: block))
    }

    func removeAll() {
        for registration in registrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(
                registration.object,
                &address,
                .main,
                registration.block
            )
        }

        registrations.removeAll()
    }

    deinit {
        MainActor.assumeIsolated { removeAll() }
    }
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
