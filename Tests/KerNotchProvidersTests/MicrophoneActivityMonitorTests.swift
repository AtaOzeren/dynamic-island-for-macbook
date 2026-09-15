import CoreAudio
import Foundation
import Testing

@testable import KerNotchProviders

/// The shared microphone monitor with CoreAudio faked. What CI can check is the
/// bookkeeping around the driver: that attribution is read only while someone
/// asked for it and the microphone is running, that its process listeners come
/// off the moment either stops being true, and that several observers share one
/// set of listeners. Whether CoreAudio attributes another app's input correctly
/// is the hardware half, per `docs/11-testing-strategy.md`.
@Suite("MicrophoneActivityMonitor")
@MainActor
struct MicrophoneActivityMonitorTests {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private static let discordHelper: AudioObjectID = 101
    private static let browser: AudioObjectID = 102
    private static let recorderTool: AudioObjectID = 103

    @MainActor
    private final class AudioSystem {
        var inputDevices: [AudioObjectID] = [1]
        var runningDevices: Set<AudioObjectID> = []
        var processes: [AudioObjectID]? = [discordHelper, browser, recorderTool]
        var processesRunningInput: Set<AudioObjectID> = []
        var processReads = 0
        var settlingReads: [@MainActor () -> Void] = []
        let bundleIdentifiers: [AudioObjectID: String] = [
            discordHelper: "com.hnc.Discord.helper.Renderer",
            browser: "com.google.Chrome.helper",
        ]

        var hardware: MicrophoneHardware {
            MicrophoneHardware(
                inputDeviceIdentifiers: { MainActor.assumeIsolated { self.inputDevices } },
                isDeviceRunning: { device in MainActor.assumeIsolated { self.runningDevices.contains(device) } },
                processIdentifiers: {
                    MainActor.assumeIsolated {
                        self.processReads += 1
                        return self.processes
                    }
                },
                processBundleIdentifier: { process in MainActor.assumeIsolated { self.bundleIdentifiers[process] } },
                isProcessRunningInput: { process in
                    MainActor.assumeIsolated { self.processesRunningInput.contains(process) }
                }
            )
        }
    }

    @MainActor
    private struct Fixture {
        let monitor: MicrophoneActivityMonitor
        let system: AudioSystem
        let listeners: FakeAudioPropertyListeners

        /// Starts the microphone with `processes` holding it, the way CoreAudio
        /// reports it: the device edge and then each process's input edge.
        func startRecording(by processes: Set<AudioObjectID>) {
            system.runningDevices = [1]
            listeners.fire(.isRunningSomewhere, on: 1)
            system.processesRunningInput = processes
            for process in processes {
                listeners.fire(.processDevices, on: process)
            }
        }

        func stopRecording() {
            system.runningDevices = []
            system.processesRunningInput = []
            listeners.fire(.isRunningSomewhere, on: 1)
        }
    }

    private static func makeFixture() -> Fixture {
        let system = AudioSystem()
        let listeners = FakeAudioPropertyListeners()
        let monitor = MicrophoneActivityMonitor(
            hardware: system.hardware,
            listeners: listeners,
            scheduleSettlingRead: { system.settlingReads.append($0) }
        )
        return Fixture(monitor: monitor, system: system, listeners: listeners)
    }

    @Test("listens to nothing until someone observes")
    func idleWithoutObservers() {
        let fixture = Self.makeFixture()

        #expect(fixture.listeners.isEmpty)
    }

    @Test("delivers the current state to a new observer at once")
    func deliversCurrentStateOnObserve() {
        let fixture = Self.makeFixture()
        var readings: [MicrophoneActivity] = []

        fixture.monitor.observeRunningState { readings.append($0) }

        #expect(readings == [.idle])
    }

    /// The running-state observer is what the recording indicator uses when no
    /// integration is on, so it must cost what the indicator always cost.
    @Test("a running-state observer never reads or listens to processes")
    func runningStateNeedsNoProcesses() {
        let fixture = Self.makeFixture()
        var readings: [MicrophoneActivity] = []
        fixture.monitor.observeRunningState { readings.append($0) }

        fixture.startRecording(by: [Self.discordHelper])

        #expect(readings.last == MicrophoneActivity(isRunning: true, clients: nil))
        #expect(fixture.system.processReads == 0)
        #expect(fixture.listeners.listenedObjects(for: .processIsRunningInput).isEmpty)
        #expect(fixture.listeners.isListening(to: .processList, on: Self.systemObject) == false)
    }

    @Test("an idle microphone is never attributed, however many observers ask")
    func idleMicrophoneReadsNoProcesses() {
        let fixture = Self.makeFixture()

        fixture.monitor.observeClients { _ in }

        #expect(fixture.system.processReads == 0)
        #expect(fixture.listeners.listenedObjects(for: .processIsRunningInput).isEmpty)
        #expect(fixture.monitor.activity == .idle)
    }

    @Test("names the applications holding a running microphone")
    func attributesRunningMicrophone() {
        let fixture = Self.makeFixture()
        fixture.monitor.observeClients { _ in }

        fixture.startRecording(by: [Self.discordHelper, Self.browser])

        #expect(
            fixture.monitor.activity.clients == [
                .application(bundleIdentifier: "com.hnc.Discord.helper.Renderer"),
                .application(bundleIdentifier: "com.google.Chrome.helper"),
            ]
        )
        for property in [AudioProperty.processDevices, .processIsRunningInput] {
            #expect(
                fixture.listeners.listenedObjects(for: property)
                    == [Self.discordHelper, Self.browser, Self.recorderTool]
            )
        }
        #expect(fixture.listeners.isListening(to: .processList, on: Self.systemObject))
    }

    @Test("reports a process with no bundle as a client rather than dropping it")
    func keepsUnidentifiedProcesses() {
        let fixture = Self.makeFixture()
        fixture.monitor.observeClients { _ in }

        fixture.startRecording(by: [Self.recorderTool])

        #expect(fixture.monitor.activity.clients == [.unidentifiedProcess])
    }

    @Test("follows a second application joining the microphone")
    func followsProcessInputEdges() {
        let fixture = Self.makeFixture()
        var readings: [MicrophoneActivity] = []
        fixture.monitor.observeClients { readings.append($0) }
        fixture.startRecording(by: [Self.discordHelper])

        fixture.system.processesRunningInput.insert(Self.browser)
        fixture.listeners.fire(.processIsRunningInput, on: Self.browser)

        #expect(readings.last?.clients?.count == 2)
    }

    /// Measured on macOS 26: the documented input-state listener never fires,
    /// while the device list changes on every edge. Both must lead to a re-read.
    @Test(
        "re-reads on either the device-list or the input-state notification",
        arguments: [AudioProperty.processDevices, .processIsRunningInput]
    )
    func followsEitherProcessNotification(property: AudioProperty) {
        let fixture = Self.makeFixture()
        fixture.monitor.observeClients { _ in }
        fixture.system.runningDevices = [1]
        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        fixture.system.processesRunningInput = [Self.browser]
        fixture.listeners.fire(property, on: Self.browser)

        #expect(fixture.monitor.activity.clients == [.application(bundleIdentifier: "com.google.Chrome.helper")])
    }

    @Test("releases a process that took only some of its listeners, to retry it whole")
    func retriesPartiallyWatchedProcesses() {
        let fixture = Self.makeFixture()
        fixture.monitor.observeClients { _ in }
        fixture.listeners.refusedObjects = [Self.recorderTool]

        fixture.startRecording(by: [Self.discordHelper])

        #expect(fixture.listeners.isListening(to: .processDevices, on: Self.recorderTool) == false)
        #expect(fixture.listeners.isListening(to: .processIsRunningInput, on: Self.recorderTool) == false)
    }

    @Test("watches a process that became an audio client mid-call")
    func watchesNewProcesses() {
        let fixture = Self.makeFixture()
        fixture.monitor.observeClients { _ in }
        fixture.startRecording(by: [Self.discordHelper])

        fixture.system.processes?.append(104)
        fixture.listeners.fire(.processList, on: Self.systemObject)

        #expect(fixture.listeners.isListening(to: .processIsRunningInput, on: 104))
    }

    /// The whole point of gating: a long day with the microphone idle carries
    /// no process listeners at all.
    @Test("takes every process listener off when the microphone stops")
    func releasesProcessListenersWhenIdle() {
        let fixture = Self.makeFixture()
        fixture.monitor.observeClients { _ in }
        fixture.startRecording(by: [Self.discordHelper])

        fixture.stopRecording()

        #expect(fixture.listeners.listenedObjects(for: .processIsRunningInput).isEmpty)
        #expect(fixture.listeners.listenedObjects(for: .processDevices).isEmpty)
        #expect(fixture.listeners.isListening(to: .processList, on: Self.systemObject) == false)
        #expect(fixture.listeners.isListening(to: .isRunningSomewhere, on: 1))
        #expect(fixture.monitor.activity == .idle)
    }

    @Test("drops attribution when the last observer that wanted it leaves")
    func releasesProcessListenersWhenNoLongerWanted() {
        let fixture = Self.makeFixture()
        fixture.monitor.observeRunningState { _ in }
        let clients = fixture.monitor.observeClients { _ in }
        fixture.startRecording(by: [Self.discordHelper])

        fixture.monitor.removeObservation(clients)

        #expect(fixture.monitor.activity == MicrophoneActivity(isRunning: true, clients: nil))
        #expect(fixture.listeners.listenedObjects(for: .processIsRunningInput).isEmpty)
    }

    @Test("reports a running microphone it cannot attribute as unattributed")
    func unattributableSystems() {
        let fixture = Self.makeFixture()
        fixture.system.processes = nil
        fixture.monitor.observeClients { _ in }

        fixture.startRecording(by: [])

        #expect(fixture.monitor.activity == MicrophoneActivity(isRunning: true, clients: nil))
        #expect(fixture.listeners.isListening(to: .processList, on: Self.systemObject) == false)
    }

    @Test("several observers share one set of listeners")
    func observersShareListeners() {
        let fixture = Self.makeFixture()
        fixture.monitor.observeRunningState { _ in }
        fixture.monitor.observeClients { _ in }
        fixture.monitor.observeClients { _ in }

        #expect(fixture.listeners.registrationCount(for: .deviceList, on: Self.systemObject) == 1)
        #expect(fixture.listeners.registrationCount(for: .isRunningSomewhere, on: 1) == 1)
    }

    @Test("an unchanged re-read tells nobody anything")
    func unchangedReadsAreSilent() {
        let fixture = Self.makeFixture()
        var readings: [MicrophoneActivity] = []
        fixture.monitor.observeClients { readings.append($0) }
        fixture.startRecording(by: [Self.discordHelper])
        let count = readings.count

        fixture.listeners.fire(.isRunningSomewhere, on: 1)
        fixture.listeners.fire(.processIsRunningInput, on: Self.browser)

        #expect(readings.count == count)
    }

    /// The device can report running a moment before the process that opened
    /// it reports its input, and only the read that follows attaches the
    /// listener that would hear it.
    @Test("reads an unattributed start once more, and finds who it was")
    func settlesUnattributedStart() {
        let fixture = Self.makeFixture()
        fixture.monitor.observeClients { _ in }
        fixture.system.runningDevices = [1]
        fixture.listeners.fire(.isRunningSomewhere, on: 1)
        #expect(fixture.monitor.activity.clients == [])
        #expect(fixture.system.settlingReads.count == 1)

        fixture.system.processesRunningInput = [Self.discordHelper]
        fixture.system.settlingReads.removeFirst()()

        #expect(fixture.monitor.activity.clients == [.application(bundleIdentifier: "com.hnc.Discord.helper.Renderer")])
    }

    @Test("settles at most once per stretch of the microphone running, never polls")
    func settlesOncePerRun() {
        let fixture = Self.makeFixture()
        fixture.monitor.observeClients { _ in }
        fixture.system.runningDevices = [1]
        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        fixture.system.settlingReads.removeFirst()()
        fixture.listeners.fire(.processDevices, on: Self.browser)
        #expect(fixture.system.settlingReads.isEmpty)

        fixture.stopRecording()
        fixture.system.runningDevices = [1]
        fixture.listeners.fire(.isRunningSomewhere, on: 1)
        #expect(fixture.system.settlingReads.count == 1)
    }

    @Test("a start already attributed needs no second look")
    func attributedStartDoesNotSettle() {
        let fixture = Self.makeFixture()
        fixture.monitor.observeClients { _ in }
        fixture.system.processesRunningInput = [Self.discordHelper]

        fixture.system.runningDevices = [1]
        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        #expect(fixture.system.settlingReads.isEmpty)
    }

    @Test("releases every listener when the last observer leaves")
    func releasesEverythingWithLastObserver() {
        let fixture = Self.makeFixture()
        let running = fixture.monitor.observeRunningState { _ in }
        let clients = fixture.monitor.observeClients { _ in }
        fixture.startRecording(by: [Self.discordHelper])

        fixture.monitor.removeObservation(running)
        fixture.monitor.removeObservation(clients)

        #expect(fixture.listeners.isEmpty)
        #expect(fixture.monitor.activity == .idle)
    }
}
