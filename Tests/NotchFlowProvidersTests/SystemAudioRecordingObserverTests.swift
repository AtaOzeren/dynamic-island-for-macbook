import CoreAudio
import Foundation
import Testing

@testable import NotchFlowProviders

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

    /// A microphone already live when NotchFlow launches is a real state, not an
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

    @Test("releases every listener when observation stops")
    func stopObservingReleasesEveryListener() {
        let fixture = Self.makeObserver()
        fixture.system.setRunning(1, true)
        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        fixture.observer.stopObserving()

        #expect(fixture.listeners.count == 0)
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
@MainActor
private final class FakeAudioPropertyListeners: AudioPropertyListening {
    private struct Key: Hashable {
        let property: AudioProperty
        let object: AudioObjectID
    }

    private var blocks: [Key: () -> Void] = [:]

    var count: Int { blocks.count }

    func listen(
        to property: AudioProperty,
        on object: AudioObjectID,
        changed: @escaping @MainActor () -> Void
    ) {
        blocks[Key(property: property, object: object)] = changed
    }

    func removeAll() {
        blocks.removeAll()
    }

    func isListening(to property: AudioProperty, on object: AudioObjectID) -> Bool {
        blocks[Key(property: property, object: object)] != nil
    }

    func fire(_ property: AudioProperty, on object: AudioObjectID) {
        blocks[Key(property: property, object: object)]?()
    }
}
