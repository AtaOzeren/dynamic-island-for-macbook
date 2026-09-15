import CoreAudio
import Foundation
import Testing

@testable import KerNotchProviders

/// The observer half of the audio recording indicator, with CoreAudio itself
/// faked: what is testable in CI is the logic *around* the driver — that a
/// running input device becomes a session, that the session survives a
/// redundant property change without restarting, that a device attached
/// mid-session gets subscribed, and that nothing polls. Whether CoreAudio
/// actually reports another app's microphone is the hardware half, per
/// `docs/11-testing-strategy.md`.
@Suite("SystemAudioRecordingObserver")
@MainActor
struct SystemAudioRecordingObserverTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    @MainActor
    private final class AudioSystem {
        var inputDevices: [AudioObjectID] = [1]
        var runningDevices: Set<AudioObjectID> = []
        var date = start

        func setRunning(_ device: AudioObjectID, _ isRunning: Bool) {
            if isRunning {
                runningDevices.insert(device)
            } else {
                runningDevices.remove(device)
            }
        }

        func advance(_ seconds: TimeInterval) {
            date = date.addingTimeInterval(seconds)
        }
    }

    private struct Fixture {
        let observer: SystemAudioRecordingObserver
        let system: AudioSystem
        let listeners: FakeAudioPropertyListeners
    }

    private static func makeObserver(
        alreadyRunning: Set<AudioObjectID> = [],
        onSession: @escaping RecordingSessionObserver = { _ in }
    ) -> Fixture {
        let system = AudioSystem()
        system.runningDevices = alreadyRunning
        let listeners = FakeAudioPropertyListeners()
        let observer = SystemAudioRecordingObserver(
            inputDeviceIdentifiers: { MainActor.assumeIsolated { system.inputDevices } },
            isDeviceRunning: { device in
                MainActor.assumeIsolated { system.runningDevices.contains(device) }
            },
            listeners: listeners,
            now: { system.date }
        )
        observer.startObserving(onSession)
        return Fixture(observer: observer, system: system, listeners: listeners)
    }

    @Test("reports nothing while no input device is running")
    func idleWhileNothingRecords() {
        var emissions: [RecordingSession?] = []
        _ = Self.makeObserver { emissions.append($0) }

        #expect(emissions.isEmpty)
    }

    /// A microphone already live when KerNotch launches is a real state, not an
    /// edge that was missed, so it is read at start rather than waited for.
    @Test("reports a recording that was already running at start")
    func reportsARecordingInProgressAtLaunch() {
        var emissions: [RecordingSession?] = []
        _ = Self.makeObserver(alreadyRunning: [1]) { emissions.append($0) }

        #expect(emissions.count == 1)
        #expect(emissions.last??.startedAt == Self.start)
    }

    @Test("starts a session when an input device begins running")
    func startsASessionWhenADeviceRuns() {
        var emissions: [RecordingSession?] = []
        let fixture = Self.makeObserver { emissions.append($0) }

        fixture.system.setRunning(1, true)
        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        #expect(emissions.count == 1)
        #expect(emissions.last??.startedAt == Self.start)
    }

    /// Teardown is the absence of a session, never a session describing absence.
    @Test("ends the session when the device stops running")
    func endsTheSessionWhenTheDeviceStops() {
        var emissions: [RecordingSession?] = []
        let fixture = Self.makeObserver { emissions.append($0) }

        fixture.system.setRunning(1, true)
        fixture.listeners.fire(.isRunningSomewhere, on: 1)
        fixture.system.setRunning(1, false)
        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        #expect(emissions.count == 2)
        #expect(emissions.last ?? nil == nil)
    }

    /// CoreAudio fires a property listener whenever it likes; only a change of
    /// state is news, so a re-notification mid-recording must not restamp the
    /// start instant and visibly reset the counter.
    @Test("does not restart the session when the level is re-reported unchanged")
    func redundantNotificationsDoNotRestartTheSession() {
        var emissions: [RecordingSession?] = []
        let fixture = Self.makeObserver { emissions.append($0) }

        fixture.system.setRunning(1, true)
        fixture.listeners.fire(.isRunningSomewhere, on: 1)
        fixture.system.advance(30)
        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        #expect(emissions.count == 1)
        #expect(emissions.last??.startedAt == Self.start)
    }

    @Test("says nothing when a device that was already idle is re-reported")
    func redundantIdleNotificationsEmitNothing() {
        var emissions: [RecordingSession?] = []
        let fixture = Self.makeObserver { emissions.append($0) }

        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        #expect(emissions.isEmpty)
    }

    /// A microphone plugged in mid-session must be observed on the same terms as
    /// one present at launch — otherwise the only way to notice it would be a
    /// sweep, which `docs/02-performance-contract.md` forbids.
    @Test("subscribes to a device that appears after start")
    func subscribesToDevicesAttachedLater() {
        var emissions: [RecordingSession?] = []
        let fixture = Self.makeObserver { emissions.append($0) }

        fixture.system.inputDevices = [1, 2]
        fixture.listeners.fire(.deviceList, on: AudioObjectID(kAudioObjectSystemObject))

        fixture.system.setRunning(2, true)
        fixture.listeners.fire(.isRunningSomewhere, on: 2)

        #expect(emissions.count == 1)
        #expect(fixture.listeners.isListening(to: .isRunningSomewhere, on: 2))
    }

    @Test("watches every input device, not only the first")
    func watchesEveryInputDevice() {
        let fixture = Self.makeObserver()
        fixture.system.inputDevices = [1, 2, 3]
        fixture.listeners.fire(.deviceList, on: AudioObjectID(kAudioObjectSystemObject))

        #expect(fixture.listeners.isListening(to: .isRunningSomewhere, on: 1))
        #expect(fixture.listeners.isListening(to: .isRunningSomewhere, on: 2))
        #expect(fixture.listeners.isListening(to: .isRunningSomewhere, on: 3))
    }

    /// Rebuilding on a device-list change must replace the subscriptions, not
    /// accumulate them, or every attach would double the wakeups.
    @Test("does not accumulate subscriptions across device list changes")
    func rebuildingSubscriptionsReplacesThem() {
        let fixture = Self.makeObserver()
        let initial = fixture.listeners.count

        fixture.listeners.fire(.deviceList, on: AudioObjectID(kAudioObjectSystemObject))

        #expect(fixture.listeners.count == initial)
    }

    /// The device-list listener is registered once per observation. Registering
    /// it again from inside its own callback is what let a single failed removal
    /// double the listeners on every display change or wake.
    @Test("registers the device-list listener once, however often the list changes")
    func registersTheDeviceListListenerOnce() {
        let fixture = Self.makeObserver()

        for devices: [AudioObjectID] in [[1, 2], [1], [1, 2, 3], []] {
            fixture.system.inputDevices = devices
            fixture.listeners.fire(.deviceList, on: Self.systemObject)
        }

        #expect(fixture.listeners.registrationCount(for: .deviceList, on: Self.systemObject) == 1)
    }

    /// A wake or a display change arrives as a burst of device-list changes.
    @Test("a burst of device-list changes never grows the listener set")
    func deviceListBurstNeverGrowsTheListenerSet() {
        let fixture = Self.makeObserver()

        for round in 0..<100 {
            fixture.system.inputDevices = round.isMultiple(of: 2) ? [1, 2, 3] : [1]
            fixture.listeners.fire(.deviceList, on: Self.systemObject)
            #expect(fixture.listeners.count <= 4)
        }

        #expect(fixture.listeners.count == 2)
    }

    @Test("leaves a device that stays attached with its original listener")
    func keepsTheListenerOfADeviceThatStays() {
        let fixture = Self.makeObserver()

        fixture.system.inputDevices = [1, 2]
        fixture.listeners.fire(.deviceList, on: Self.systemObject)

        #expect(fixture.listeners.registrationCount(for: .isRunningSomewhere, on: 1) == 1)
    }

    @Test("stops watching a device that is detached")
    func stopsWatchingADetachedDevice() {
        let fixture = Self.makeObserver()
        fixture.system.inputDevices = [1, 2]
        fixture.listeners.fire(.deviceList, on: Self.systemObject)

        fixture.system.inputDevices = [2]
        fixture.listeners.fire(.deviceList, on: Self.systemObject)

        #expect(!fixture.listeners.isListening(to: .isRunningSomewhere, on: 1))
        #expect(fixture.listeners.isListening(to: .isRunningSomewhere, on: 2))
    }

    @Test("watches a device again when it is reattached")
    func watchesAReattachedDevice() {
        let fixture = Self.makeObserver()

        for devices: [AudioObjectID] in [[1, 2], [1], [1, 2]] {
            fixture.system.inputDevices = devices
            fixture.listeners.fire(.deviceList, on: Self.systemObject)
        }

        #expect(fixture.listeners.isListening(to: .isRunningSomewhere, on: 2))
    }

    /// A registration can fail while the HAL settles after a wake. The device
    /// must not be recorded as watched, or it is never tried again.
    @Test("retries a device whose listener failed to register on the next device-list change")
    func retriesADeviceWhoseListenerFailed() {
        let fixture = Self.makeObserver()
        fixture.listeners.refusedObjects = [2]
        fixture.system.inputDevices = [1, 2]
        fixture.listeners.fire(.deviceList, on: Self.systemObject)
        #expect(!fixture.listeners.isListening(to: .isRunningSomewhere, on: 2))

        fixture.listeners.refusedObjects = []
        fixture.listeners.fire(.deviceList, on: Self.systemObject)

        #expect(fixture.listeners.isListening(to: .isRunningSomewhere, on: 2))
    }

    /// Stopping forgets which devices were watched, so starting again cannot
    /// mistake every device for one that is already covered.
    @Test("listens again after observation is restarted")
    func listensAgainAfterRestart() {
        let fixture = Self.makeObserver()

        fixture.observer.stopObserving()
        fixture.observer.startObserving { _ in }

        #expect(fixture.listeners.isListening(to: .deviceList, on: Self.systemObject))
        #expect(fixture.listeners.isListening(to: .isRunningSomewhere, on: 1))
    }

    @Test("releases every listener when observation stops")
    func stopObservingReleasesEveryListener() {
        let fixture = Self.makeObserver()
        fixture.system.setRunning(1, true)
        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        fixture.observer.stopObserving()

        #expect(fixture.listeners.isEmpty)
    }

    /// After teardown the observer owes its former listener nothing, even if
    /// CoreAudio delivers a straggling notification.
    @Test("stays silent after observation stops")
    func emitsNothingAfterStopping() {
        var emissions: [RecordingSession?] = []
        let fixture = Self.makeObserver { emissions.append($0) }
        fixture.observer.stopObserving()

        fixture.system.setRunning(1, true)
        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        #expect(emissions.isEmpty)
    }
}

/// CoreAudio's subscription surface, faked: registrations are recorded so the
/// test can assert what is being watched, and fired on demand so nothing waits
/// on a driver.
///
/// It also counts how often each listener was registered. The fake replaces by
/// key just as the real listeners now do, so the active set alone could never
/// show the observer re-registering on every change — which is exactly how the
/// runaway went unnoticed while every test here passed.
@MainActor
private final class FakeAudioPropertyListeners: AudioPropertyListening {
    private struct Key: Hashable {
        let property: AudioProperty
        let object: AudioObjectID
    }

    private var blocks: [Key: @MainActor () -> Void] = [:]
    private var registrationCounts: [Key: Int] = [:]

    /// Devices whose running-state listener the driver refuses to register.
    var refusedObjects: Set<AudioObjectID> = []

    var count: Int { blocks.count }
    var isEmpty: Bool { blocks.isEmpty }

    func listen(
        to property: AudioProperty,
        on object: AudioObjectID,
        changed: @escaping @MainActor () -> Void
    ) -> Bool {
        let key = Key(property: property, object: object)
        registrationCounts[key, default: 0] += 1
        guard refusedObjects.contains(object) == false else { return false }
        blocks[key] = changed
        return true
    }

    func stopListening(to property: AudioProperty, on object: AudioObjectID) {
        blocks[Key(property: property, object: object)] = nil
    }

    func removeAll() {
        blocks.removeAll()
    }

    func isListening(to property: AudioProperty, on object: AudioObjectID) -> Bool {
        blocks[Key(property: property, object: object)] != nil
    }

    func registrationCount(for property: AudioProperty, on object: AudioObjectID) -> Int {
        registrationCounts[Key(property: property, object: object)] ?? 0
    }

    func fire(_ property: AudioProperty, on object: AudioObjectID) {
        blocks[Key(property: property, object: object)]?()
    }
}
