import CoreAudio
import Foundation
import KerNotchCore
import Testing

@testable import KerNotchProviders

/// How the microphone indicator steps aside for an integration that reports the
/// same microphone on its own — and, just as much, when it must not.
@Suite("SystemAudioRecordingObserver exclusions")
@MainActor
struct SystemAudioRecordingObserverExclusionTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)
    private static let discordHelper: AudioObjectID = 101
    private static let browser: AudioObjectID = 102
    private static let recorderTool: AudioObjectID = 103

    @MainActor
    private final class AudioSystem {
        var isDeviceRunning = false
        var processesRunningInput: Set<AudioObjectID> = []
        let bundleIdentifiers: [AudioObjectID: String] = [
            discordHelper: "com.hnc.Discord.helper.Renderer",
            browser: "com.google.Chrome.helper",
        ]
    }

    @MainActor
    private struct Fixture {
        let observer: SystemAudioRecordingObserver
        let system: AudioSystem
        let listeners: FakeAudioPropertyListeners

        func capture(by processes: Set<AudioObjectID>) {
            system.isDeviceRunning = processes.isEmpty == false
            system.processesRunningInput = processes
            listeners.fire(.isRunningSomewhere, on: 1)
        }
    }

    private static func makeFixture(onSession: @escaping RecordingSessionObserver) -> Fixture {
        let system = AudioSystem()
        let listeners = FakeAudioPropertyListeners()
        let processes = [discordHelper, browser, recorderTool]
        let hardware = MicrophoneHardware(
            inputDeviceIdentifiers: { [1] },
            isDeviceRunning: { _ in MainActor.assumeIsolated { system.isDeviceRunning } },
            processIdentifiers: { processes },
            processBundleIdentifier: { process in MainActor.assumeIsolated { system.bundleIdentifiers[process] } },
            isProcessRunningInput: { process in
                MainActor.assumeIsolated { system.processesRunningInput.contains(process) }
            },
            processInputDevices: { process in
                MainActor.assumeIsolated { system.processesRunningInput.contains(process) ? [1] : [] }
            }
        )
        let observer = SystemAudioRecordingObserver(
            monitor: MicrophoneActivityMonitor(
                hardware: hardware,
                listeners: listeners,
                scheduleSettlingRead: { _ in }
            ),
            now: { start }
        )
        observer.startObserving(onSession)
        return Fixture(observer: observer, system: system, listeners: listeners)
    }

    private static func excludingDiscord(_ fixture: Fixture) {
        fixture.observer.excludeApplications(where: DiscordApplication.owns(bundleIdentifier:))
    }

    @Test("reports Discord's microphone while nothing excludes it")
    func reportsEveryoneByDefault() {
        var sessions: [RecordingSession?] = []
        let fixture = Self.makeFixture { sessions.append($0) }

        fixture.capture(by: [Self.discordHelper])

        #expect(sessions == [RecordingSession(startedAt: Self.start)])
    }

    @Test("stays quiet while only an excluded application holds the microphone")
    func silentForExcludedApplication() {
        var sessions: [RecordingSession?] = []
        let fixture = Self.makeFixture { sessions.append($0) }
        Self.excludingDiscord(fixture)

        fixture.capture(by: [Self.discordHelper])

        #expect(sessions.isEmpty)
    }

    @Test("reports another application sharing the microphone with an excluded one")
    func reportsSharedMicrophone() {
        var sessions: [RecordingSession?] = []
        let fixture = Self.makeFixture { sessions.append($0) }
        Self.excludingDiscord(fixture)

        fixture.capture(by: [Self.discordHelper, Self.browser])

        #expect(sessions == [RecordingSession(startedAt: Self.start)])
    }

    @Test("reports a process with no bundle, which no exclusion can claim")
    func reportsUnidentifiedProcess() {
        var sessions: [RecordingSession?] = []
        let fixture = Self.makeFixture { sessions.append($0) }
        Self.excludingDiscord(fixture)

        fixture.capture(by: [Self.discordHelper, Self.recorderTool])

        #expect(sessions.count == 1)
    }

    /// A microphone running with no client anyone can name is still a
    /// microphone in use.
    @Test("reports a running microphone nobody can attribute")
    func reportsUnattributedMicrophone() {
        var sessions: [RecordingSession?] = []
        let fixture = Self.makeFixture { sessions.append($0) }
        Self.excludingDiscord(fixture)

        fixture.system.isDeviceRunning = true
        fixture.listeners.fire(.isRunningSomewhere, on: 1)

        #expect(sessions.count == 1)
    }

    @Test("ends the session when the other application leaves an excluded one behind")
    func endsWhenOnlyExcludedRemains() {
        var sessions: [RecordingSession?] = []
        let fixture = Self.makeFixture { sessions.append($0) }
        Self.excludingDiscord(fixture)
        fixture.capture(by: [Self.discordHelper, Self.browser])

        fixture.system.processesRunningInput = [Self.discordHelper]
        fixture.listeners.fire(.processDevices, on: Self.browser)

        #expect(sessions == [RecordingSession(startedAt: Self.start), nil])
    }

    @Test("turning the exclusion off mid-call brings the indicator back at once")
    func includingAgainReportsImmediately() {
        var sessions: [RecordingSession?] = []
        let fixture = Self.makeFixture { sessions.append($0) }
        Self.excludingDiscord(fixture)
        fixture.capture(by: [Self.discordHelper])

        fixture.observer.includeAllApplications()

        #expect(sessions == [RecordingSession(startedAt: Self.start)])
        #expect(fixture.listeners.listenedObjects(for: .processIsRunningInput).isEmpty)
        #expect(fixture.listeners.listenedObjects(for: .processDevices).isEmpty)
    }

    @Test("turning the exclusion on mid-call takes the indicator away at once")
    func excludingMidCallEndsSession() {
        var sessions: [RecordingSession?] = []
        let fixture = Self.makeFixture { sessions.append($0) }
        fixture.capture(by: [Self.discordHelper])

        Self.excludingDiscord(fixture)

        #expect(sessions == [RecordingSession(startedAt: Self.start), nil])
    }

    /// Swapping observations must never let the monitor see zero observers, or
    /// every device listener would be torn down and rebuilt on each toggle.
    @Test("switching the exclusion keeps the device listeners in place")
    func togglingKeepsDeviceListeners() {
        let fixture = Self.makeFixture { _ in }

        Self.excludingDiscord(fixture)
        fixture.observer.includeAllApplications()

        #expect(fixture.listeners.registrationCount(for: .isRunningSomewhere, on: 1) == 1)
    }

    @Test("releases every listener when observation stops mid-call")
    func stopReleasesProcessListeners() {
        let fixture = Self.makeFixture { _ in }
        Self.excludingDiscord(fixture)
        fixture.capture(by: [Self.discordHelper])

        fixture.observer.stopObserving()

        #expect(fixture.listeners.isEmpty)
    }
}
