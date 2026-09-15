import CoreAudio
import Foundation

/// A process running microphone input.
public enum MicrophoneClient: Hashable, Sendable {
    case application(bundleIdentifier: String)
    /// A process with no bundle — a command-line recorder, say. Still a client:
    /// dropping it would let an integration claim a microphone it shares.
    case unidentifiedProcess
}

/// What the microphone is doing, as far as KerNotch is allowed to see.
public struct MicrophoneActivity: Equatable, Sendable {
    public static let idle = MicrophoneActivity(isRunning: false, clients: nil)

    /// Whether any input device is running for any process.
    public let isRunning: Bool

    /// Who is running the input, or `nil` when that is not known: nobody asked,
    /// the microphone is idle, or the system cannot say — per-process input
    /// state arrived in macOS 14.2.
    public let clients: Set<MicrophoneClient>?

    public init(isRunning: Bool, clients: Set<MicrophoneClient>?) {
        self.isRunning = isRunning
        self.clients = clients
    }
}

/// The CoreAudio reads the monitor needs, as values so tests can stand in for
/// the hardware.
struct MicrophoneHardware: Sendable {
    var inputDeviceIdentifiers: @Sendable () -> [AudioObjectID]
    var isDeviceRunning: @Sendable (AudioObjectID) -> Bool
    /// `nil` where the system has no process objects to offer.
    var processIdentifiers: @Sendable () -> [AudioObjectID]?
    var processBundleIdentifier: @Sendable (AudioObjectID) -> String?
    var isProcessRunningInput: @Sendable (AudioObjectID) -> Bool

    static let system = MicrophoneHardware(
        inputDeviceIdentifiers: { CoreAudioSystem.inputDeviceIdentifiers() },
        isDeviceRunning: { CoreAudioSystem.isRunningSomewhere($0) },
        processIdentifiers: { CoreAudioSystem.processIdentifiers() },
        processBundleIdentifier: { CoreAudioSystem.bundleIdentifier(ofProcess: $0) },
        isProcessRunningInput: { CoreAudioSystem.isRunningInput(process: $0) }
    )
}

/// The one place KerNotch listens to the microphone, shared by everything that
/// reports on it.
///
/// Whether the microphone is running comes from
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` on every input device: public,
/// documented, permission-free, and read by listener, never by polling. Which
/// application is running it comes from the per-process input state CoreAudio
/// added in macOS 14.2 (`kAudioProcessPropertyIsRunningInput`), equally
/// permission-free. KerNotch opens no stream and reads no audio content either
/// way, so no microphone prompt is ever triggered.
///
/// Attribution is paid for only while it is wanted. The process listeners go on
/// when the microphone starts running *and* an observer has asked who is using
/// it, and come off the moment either stops being true — so an idle microphone,
/// or a user with no integration enabled, costs exactly the device listeners the
/// recording indicator always had.
///
/// Its limits are recorded honestly in
/// `.omo/evidence/task-47-kernotch-v1/detection-limits.md` rather than papered
/// over with a guess.
@MainActor
public final class MicrophoneActivityMonitor {
    public typealias Observer = @MainActor (MicrophoneActivity) -> Void
    /// Runs an action once, shortly after now.
    typealias SettlingReadScheduler = @MainActor (@escaping @MainActor () -> Void) -> Void

    /// How long after the microphone starts an unattributed reading is given to
    /// settle. Long enough for a process's input state to catch up with its
    /// device, short enough that a wrong indicator is never seen.
    static let settlingReadDelay = DispatchTimeInterval.milliseconds(250)

    static let dispatchSettlingRead: SettlingReadScheduler = { action in
        DispatchQueue.main.asyncAfter(deadline: .now() + settlingReadDelay) {
            MainActor.assumeIsolated { action() }
        }
    }

    public struct Observation: Hashable, Sendable {
        fileprivate let rawValue: UInt
    }

    private struct Registration {
        let wantsClients: Bool
        let deliver: Observer
    }

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// What a process's input starting or stopping is heard through.
    ///
    /// `kAudioProcessPropertyIsRunningInput` is the documented property, but on
    /// macOS 26 its listeners were never called — measured across repeated
    /// Discord joins and leaves while the value itself flipped. The process's
    /// device list changed on every one of those edges, so that is the
    /// notification relied on; the documented one is kept beside it for the
    /// systems that do deliver it. Either firing only triggers a re-read.
    private static let processChangeProperties: [AudioProperty] = [.processDevices, .processIsRunningInput]

    private let hardware: MicrophoneHardware
    private let listeners: any AudioPropertyListening
    private let scheduleSettlingRead: SettlingReadScheduler

    private var registrations: [Observation: Registration] = [:]
    private var lastObservationValue: UInt = 0
    private var current = MicrophoneActivity.idle

    /// The input devices currently carrying a running-somewhere listener, so a
    /// device-list change touches only the devices that actually came or went.
    private var watchedInputDevices: Set<AudioObjectID> = []
    private var watchedProcesses: Set<AudioObjectID> = []
    private var isWatchingProcessList = false
    /// At most one settling read per stretch of the microphone running, so a
    /// client that stays unattributable is re-read once, never polled.
    private var hasScheduledSettlingRead = false

    public convenience init() {
        self.init(hardware: .system, listeners: CoreAudioPropertyListeners())
    }

    init(
        hardware: MicrophoneHardware,
        listeners: any AudioPropertyListening,
        scheduleSettlingRead: @escaping SettlingReadScheduler = MicrophoneActivityMonitor.dispatchSettlingRead
    ) {
        self.hardware = hardware
        self.listeners = listeners
        self.scheduleSettlingRead = scheduleSettlingRead
    }

    /// The microphone as it was last read.
    public var activity: MicrophoneActivity { current }

    /// Delivers whether the microphone is running, now and on every change.
    @discardableResult
    public func observeRunningState(_ observer: @escaping Observer) -> Observation {
        register(Registration(wantsClients: false, deliver: observer))
    }

    /// Delivers who is running the microphone, now and on every change.
    @discardableResult
    public func observeClients(_ observer: @escaping Observer) -> Observation {
        register(Registration(wantsClients: true, deliver: observer))
    }

    /// The last observation to go takes every CoreAudio listener with it.
    public func removeObservation(_ observation: Observation) {
        guard registrations.removeValue(forKey: observation) != nil else { return }

        guard registrations.isEmpty == false else {
            stopListening()
            return
        }
        refresh()
    }

    private func register(_ registration: Registration) -> Observation {
        let isFirst = registrations.isEmpty
        lastObservationValue += 1
        let observation = Observation(rawValue: lastObservationValue)
        registrations[observation] = registration

        if isFirst {
            listenForDeviceListChanges()
            watchInputDevices()
        }

        // A microphone already live when observation starts is a real state,
        // not an edge that was missed, so it is read here rather than waited
        // for. A newcomer that changed nothing is still owed the current value.
        if refresh() == false {
            registration.deliver(current)
        }
        return observation
    }

    private func stopListening() {
        listeners.removeAll()
        watchedInputDevices = []
        watchedProcesses = []
        isWatchingProcessList = false
        hasScheduledSettlingRead = false
        current = .idle
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
        refresh()
    }

    /// Brings the per-device listeners in line with the input devices as they
    /// now stand: devices that left lose theirs, devices that arrived gain one,
    /// and devices that stayed are not touched.
    ///
    /// Only a device whose listener actually registered counts as watched. A
    /// registration can fail while the HAL is still settling after a wake, and a
    /// device recorded as watched anyway would never be tried again.
    private func watchInputDevices() {
        watchedInputDevices = reconcile(
            watched: watchedInputDevices,
            current: Set(hardware.inputDeviceIdentifiers()),
            properties: [.isRunningSomewhere]
        )
    }

    /// Re-reads the microphone and tells every observer when the reading
    /// changed. Returns whether it did.
    @discardableResult
    private func refresh() -> Bool {
        let isRunning = hardware.inputDeviceIdentifiers().contains(where: hardware.isDeviceRunning)
        let next = MicrophoneActivity(
            isRunning: isRunning,
            clients: isRunning && wantsClients ? attributedClients() : nil
        )
        if next.clients == nil {
            stopWatchingProcesses()
        }
        settleUnattributedStart(of: next)

        guard next != current else { return false }
        current = next

        let observers = registrations.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value.deliver)
        for deliver in observers {
            deliver(next)
        }
        return true
    }

    /// A microphone that starts running with no client yet visible is read once
    /// more, shortly after.
    ///
    /// The device's running state and a process's own input state are updated
    /// separately, and the process listeners that would report the second are
    /// only attached by the read the first one triggered. Without a second look,
    /// a Discord call could open as the ordinary microphone indicator.
    private func settleUnattributedStart(of reading: MicrophoneActivity) {
        guard reading.isRunning else {
            hasScheduledSettlingRead = false
            return
        }
        guard reading.clients?.isEmpty == true, hasScheduledSettlingRead == false else { return }

        hasScheduledSettlingRead = true
        scheduleSettlingRead { [weak self] in
            guard let self, registrations.isEmpty == false else { return }
            refresh()
        }
    }

    private var wantsClients: Bool {
        registrations.values.contains(where: \.wantsClients)
    }

    /// Who holds the input right now, with a listener on every audio process so
    /// the answer is re-read the moment it changes.
    private func attributedClients() -> Set<MicrophoneClient>? {
        guard let processes = hardware.processIdentifiers() else { return nil }

        if isWatchingProcessList == false {
            isWatchingProcessList = listeners.listen(to: .processList, on: Self.systemObject) { [weak self] in
                self?.refresh()
            }
        }
        watchedProcesses = reconcile(
            watched: watchedProcesses,
            current: Set(processes),
            properties: Self.processChangeProperties
        )

        return Set(
            processes.filter(hardware.isProcessRunningInput).map { process in
                hardware.processBundleIdentifier(process).map { .application(bundleIdentifier: $0) }
                    ?? .unidentifiedProcess
            }
        )
    }

    private func stopWatchingProcesses() {
        if isWatchingProcessList {
            listeners.stopListening(to: .processList, on: Self.systemObject)
            isWatchingProcessList = false
        }
        for process in watchedProcesses {
            for property in Self.processChangeProperties {
                listeners.stopListening(to: property, on: process)
            }
        }
        watchedProcesses = []
    }

    /// Moves the listeners for `properties` from the objects in `watched` to
    /// the objects in `current`, touching only the difference, and returns the
    /// objects that now carry all of them. An object that took only some is
    /// released again, so it is retried whole on the next change.
    private func reconcile(
        watched: Set<AudioObjectID>,
        current: Set<AudioObjectID>,
        properties: [AudioProperty]
    ) -> Set<AudioObjectID> {
        for object in watched.subtracting(current) {
            for property in properties {
                listeners.stopListening(to: property, on: object)
            }
        }

        var stillWatched = watched.intersection(current)
        for object in current.subtracting(watched) {
            let registered = properties.filter { property in
                listeners.listen(to: property, on: object) { [weak self] in
                    self?.refresh()
                }
            }
            if registered.count == properties.count {
                stillWatched.insert(object)
            } else {
                for property in registered {
                    listeners.stopListening(to: property, on: object)
                }
            }
        }
        return stillWatched
    }
}

/// The CoreAudio properties the monitor subscribes to, named so the call site
/// reads as intent rather than as four-character codes.
enum AudioProperty: Hashable {
    case deviceList
    case isRunningSomewhere
    case processList
    case processIsRunningInput
    case processDevices

    var address: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private var selector: AudioObjectPropertySelector {
        switch self {
        case .deviceList: kAudioHardwarePropertyDevices
        case .isRunningSomewhere: kAudioDevicePropertyDeviceIsRunningSomewhere
        case .processList: kAudioHardwarePropertyProcessObjectList
        case .processIsRunningInput: kAudioProcessPropertyIsRunningInput
        case .processDevices: kAudioProcessPropertyDevices
        }
    }
}

/// The subscription half of CoreAudio, behind a protocol for the reason
/// `docs/11-testing-strategy.md` gives for every hardware seam: the monitor's
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

/// The query half of CoreAudio, with the `AudioObjectGetPropertyData` ceremony
/// kept in one place.
enum CoreAudioSystem {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// Every audio device that has at least one input stream — the set a
    /// microphone can be running on.
    static func inputDeviceIdentifiers() -> [AudioObjectID] {
        objectList(.deviceList)?.filter(hasInputStreams) ?? []
    }

    static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        flag(.isRunningSomewhere, of: device)
    }

    /// Every process CoreAudio knows as a client, or `nil` on a system that
    /// predates process objects: there the property is unknown and the read
    /// fails, which is the availability check.
    static func processIdentifiers() -> [AudioObjectID]? {
        objectList(.processList)
    }

    static func isRunningInput(process: AudioObjectID) -> Bool {
        flag(.processIsRunningInput, of: process)
    }

    static func bundleIdentifier(ofProcess process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        // The HAL hands back a retained string the caller owns.
        let identifier = value?.takeRetainedValue() as String?
        return identifier?.isEmpty == false ? identifier : nil
    }

    private static func flag(_ property: AudioProperty, of object: AudioObjectID) -> Bool {
        var address = property.address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)

        return status == noErr && value != 0
    }

    private static func objectList(_ property: AudioProperty) -> [AudioObjectID]? {
        var address = property.address
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else {
            return nil
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size

        guard count > 0 else { return [] }

        var objects = [AudioObjectID](repeating: 0, count: count)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &objects)

        return status == noErr ? objects : nil
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
