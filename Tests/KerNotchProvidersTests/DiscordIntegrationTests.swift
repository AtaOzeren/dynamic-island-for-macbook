import CoreAudio
import Foundation
import KerNotchCore
import Testing

@testable import KerNotchProviders

private let discordHelper: AudioObjectID = 101
private let browser: AudioObjectID = 102

@MainActor
private final class IdleTickScheduler: TickScheduling {
    private var tick: (@MainActor () -> Void)?

    var isScheduled: Bool { tick != nil }

    func schedule(_ tick: @escaping @MainActor () -> Void) {
        self.tick = tick
    }

    func cancel() {
        tick = nil
    }
}

/// The integration end to end against faked CoreAudio and a faked Discord: the
/// user-visible promises from the settings switch down to the island's activity
/// set.
@Suite("Discord integration")
@MainActor
struct DiscordIntegrationTests {
    @MainActor
    private final class Fixture {
        let manager = ActivityManager(sleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
        let listeners = FakeAudioPropertyListeners()
        let transport = FakeDiscordIPCTransport()
        let credentials = FakeDiscordCredentialStore()
        let workspace = FakeDiscordWorkspace()
        let reconnect = FakeDiscordReconnectScheduler()
        var capturing: Set<AudioObjectID> = []
        var inVoiceChannel = false

        lazy var monitor = MicrophoneActivityMonitor(
            hardware: MicrophoneHardware(
                inputDeviceIdentifiers: { [1] },
                isDeviceRunning: { [unowned self] _ in MainActor.assumeIsolated { capturing.isEmpty == false } },
                processIdentifiers: { [discordHelper, browser] },
                processBundleIdentifier: { process in
                    process == discordHelper ? "com.hnc.Discord.helper.Renderer" : "com.google.Chrome.helper"
                },
                isProcessRunningInput: { [unowned self] process in
                    MainActor.assumeIsolated { capturing.contains(process) }
                }
            ),
            listeners: listeners
        )
        lazy var recordingObserver = SystemAudioRecordingObserver(monitor: monitor)
        lazy var recordingProvider = RecordingProvider(
            source: .audio,
            sessions: recordingObserver,
            scheduler: IdleTickScheduler()
        )
        lazy var session = DiscordVoiceSession(
            dependencies: DiscordVoiceSessionDependencies(
                transport: transport,
                socketPaths: { ["/tmp/discord-ipc-0"] },
                tokens: FakeDiscordTokenExchange(),
                credentials: credentials,
                reconnect: reconnect,
                now: { Date(timeIntervalSinceReferenceDate: 0) }
            )
        )
        lazy var integration = DiscordIntegration(
            manager: manager,
            microphoneMonitor: monitor,
            microphoneRecording: recordingObserver,
            session: session,
            workspace: workspace
        )

        init() {
            transport.respond = { [unowned self] sent in
                switch sent.command {
                case "GET_SELECTED_VOICE_CHANNEL":
                    return .data(inVoiceChannel ? ["id": "10", "name": "Lobby", "guild_id": "20"] : nil)
                case "GET_GUILD":
                    return .data(["id": "20", "name": "Ocean View Hotel"])
                case "GET_VOICE_SETTINGS":
                    return .data(["mute": false])
                default:
                    return .data(nil)
                }
            }
            recordingProvider.startObserving { [unowned self] (activity: RecordingActivity?) in
                if let activity {
                    manager.register(activity)
                } else {
                    manager.end(RecordingActivity.identity(for: .audio))
                }
            }
        }

        func capture(by processes: Set<AudioObjectID>) {
            capturing = processes
            listeners.fire(.isRunningSomewhere, on: 1)
        }

        var activeKinds: Set<ActivityKind> {
            Set(manager.activeActivities.map(\.kind))
        }

        var call: DiscordCallActivity? {
            manager.activeActivities.lazy.compactMap { $0 as? DiscordCallActivity }.first
        }
    }

    private static let enabled = DiscordIntegrationPreferences(isEnabled: true, clientID: .testApplication)

    @Test("while off, a Discord call is the ordinary microphone indicator")
    func offShowsMicrophone() {
        let fixture = Fixture()
        fixture.integration.apply(.default)

        fixture.capture(by: [discordHelper])

        #expect(fixture.activeKinds == [.recording])
    }

    @Test("while on, a Discord call replaces the microphone indicator")
    func onShowsCallOnly() {
        let fixture = Fixture()
        fixture.integration.apply(Self.enabled)

        fixture.capture(by: [discordHelper])

        #expect(fixture.activeKinds == [.discordCall])
        #expect(fixture.call == DiscordCallActivity(channel: nil, isMuted: nil))
    }

    @Test("while on, Discord and another app on the microphone show side by side")
    func sharedMicrophoneShowsBoth() {
        let fixture = Fixture()
        fixture.integration.apply(Self.enabled)

        fixture.capture(by: [discordHelper, browser])

        #expect(fixture.activeKinds == [.discordCall, .recording])
    }

    @Test("while on, another app alone is the ordinary microphone indicator")
    func otherAppAloneShowsMicrophone() {
        let fixture = Fixture()
        fixture.integration.apply(Self.enabled)

        fixture.capture(by: [browser])

        #expect(fixture.activeKinds == [.recording])
    }

    @Test("switching off mid-call hands the call back to the microphone indicator")
    func disablingMidCall() {
        let fixture = Fixture()
        fixture.integration.apply(Self.enabled)
        fixture.capture(by: [discordHelper])

        fixture.integration.apply(.default)

        #expect(fixture.activeKinds == [.recording])
        #expect(fixture.session.status == .inactive)
        #expect(fixture.workspace.isObservingLaunches == false)
    }

    @Test("the call ends when Discord releases the microphone")
    func callEndsWithMicrophone() {
        let fixture = Fixture()
        fixture.integration.apply(Self.enabled)
        fixture.capture(by: [discordHelper])

        fixture.capture(by: [])

        #expect(fixture.manager.activeActivities.isEmpty)
    }

    @Test("a connected call names its channel and offers to leave it")
    func connectedCallNamesChannel() async {
        let fixture = Fixture()
        fixture.credentials.stored[.testApplication] = .fresh
        fixture.inVoiceChannel = true

        fixture.integration.apply(Self.enabled)
        fixture.capture(by: [discordHelper])
        await settleDiscordTasks()

        #expect(fixture.call?.channel == DiscordVoiceChannel(name: "Lobby", serverName: "Ocean View Hotel"))
        #expect(fixture.call?.primaryAction?.intent == .leaveDiscordVoiceChannel)
    }

    /// Enabling without a Client ID is the no-setup layer: the call is shown
    /// from the microphone alone, and nothing connects to Discord.
    @Test("without a Client ID nothing connects, and the microphone still reports the call")
    func noClientIDStaysPassive() {
        let fixture = Fixture()
        fixture.integration.apply(DiscordIntegrationPreferences(isEnabled: true, clientID: nil))

        fixture.capture(by: [discordHelper])

        #expect(fixture.transport.openedPaths.isEmpty)
        #expect(fixture.session.status == .inactive)
        #expect(fixture.activeKinds == [.discordCall])
    }

    @Test("a Discord launch wakes a session that had given up")
    func launchReconnects() {
        let fixture = Fixture()
        fixture.transport.refusedPaths = ["/tmp/discord-ipc-0"]
        fixture.integration.apply(Self.enabled)
        for _ in DiscordVoiceSession.reconnectDelays {
            fixture.reconnect.fire()
        }

        fixture.workspace.launchDiscord()

        #expect(fixture.reconnect.hasPendingAttempt)
    }

    @Test("Discord taking the microphone wakes a session that had given up")
    func captureReconnects() {
        let fixture = Fixture()
        fixture.transport.refusedPaths = ["/tmp/discord-ipc-0"]
        fixture.integration.apply(Self.enabled)
        for _ in DiscordVoiceSession.reconnectDelays {
            fixture.reconnect.fire()
        }
        #expect(fixture.reconnect.hasPendingAttempt == false)

        fixture.capture(by: [discordHelper])

        #expect(fixture.reconnect.hasPendingAttempt)
    }

    @Test("forwards connection status changes")
    func forwardsStatus() async {
        let fixture = Fixture()
        var statuses: [DiscordConnectionStatus] = []
        fixture.integration.onStatusChange = { statuses.append($0) }

        fixture.integration.apply(Self.enabled)
        await settleDiscordTasks()

        #expect(statuses.last == .needsAuthorization)
    }
}

@Suite("DiscordCallProvider")
@MainActor
struct DiscordCallProviderTests {
    private static let lobby = DiscordVoiceChannel(name: "Lobby", serverName: "Ocean View Hotel")

    @Test("a channel alone is a call — input CoreAudio could not attribute")
    func channelAloneIsACall() {
        let monitor = MicrophoneActivityMonitor(
            hardware: MicrophoneHardware(
                inputDeviceIdentifiers: { [] },
                isDeviceRunning: { _ in false },
                processIdentifiers: { nil },
                processBundleIdentifier: { _ in nil },
                isProcessRunningInput: { _ in false }
            ),
            listeners: FakeAudioPropertyListeners()
        )
        let provider = DiscordCallProvider(monitor: monitor)
        var emissions: [DiscordCallActivity?] = []
        provider.startObserving { emissions.append($0) }

        provider.voiceStateDidChange(DiscordVoiceState(channel: Self.lobby, isMuted: true))
        provider.voiceStateDidChange(DiscordVoiceState(channel: Self.lobby, isMuted: true))
        provider.voiceStateDidChange(DiscordVoiceState(channel: nil, isMuted: true))

        #expect(emissions == [DiscordCallActivity(channel: Self.lobby, isMuted: true), nil])
    }

    @Test("emits nothing once stopped")
    func silentAfterStop() {
        let listeners = FakeAudioPropertyListeners()
        let monitor = MicrophoneActivityMonitor(
            hardware: MicrophoneHardware(
                inputDeviceIdentifiers: { [1] },
                isDeviceRunning: { _ in false },
                processIdentifiers: { [] },
                processBundleIdentifier: { _ in nil },
                isProcessRunningInput: { _ in false }
            ),
            listeners: listeners
        )
        let provider = DiscordCallProvider(monitor: monitor)
        var emissions: [DiscordCallActivity?] = []
        provider.startObserving { emissions.append($0) }

        provider.stopObserving()
        provider.voiceStateDidChange(DiscordVoiceState(channel: Self.lobby, isMuted: false))

        #expect(emissions.isEmpty)
        #expect(listeners.isEmpty)
    }
}
