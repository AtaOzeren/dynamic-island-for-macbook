import KerNotchCore

/// Everything the Discord integration is, switched on and off as one.
///
/// Enabling it does three things that only make sense together: the microphone
/// indicator stops reporting Discord, the call activity starts reporting it, and
/// the RPC session connects when there is a Client ID to connect with. Keeping
/// them behind one `apply` is what guarantees a Discord call is never shown
/// twice, and never shown not at all.
@MainActor
public final class DiscordIntegration {
    public var onStatusChange: (@MainActor (DiscordConnectionStatus) -> Void)?

    private let manager: ActivityManager
    private let microphoneRecording: SystemAudioRecordingObserver
    private let callProvider: DiscordCallProvider
    private let session: DiscordVoiceSession
    private let workspace: any DiscordWorkspaceObserving

    private var preferences = DiscordIntegrationPreferences.default

    public init(
        manager: ActivityManager,
        microphoneMonitor: MicrophoneActivityMonitor,
        microphoneRecording: SystemAudioRecordingObserver,
        session: DiscordVoiceSession = DiscordVoiceSession(),
        workspace: any DiscordWorkspaceObserving = NSWorkspaceDiscordObserver()
    ) {
        self.manager = manager
        self.microphoneRecording = microphoneRecording
        self.session = session
        self.workspace = workspace
        callProvider = DiscordCallProvider(monitor: microphoneMonitor)

        session.onVoiceStateChange = { [weak callProvider] voiceState in
            callProvider?.voiceStateDidChange(voiceState)
        }
        session.onStatusChange = { [weak self] status in
            self?.onStatusChange?(status)
        }
        callProvider.onDiscordCaptureStarted = { [weak session] in
            session?.discordBecameActive()
        }
    }

    public var status: DiscordConnectionStatus { session.status }

    public var isDiscordInstalled: Bool { workspace.isDiscordInstalled }

    /// Where the island's "Leave channel" press goes.
    public var voiceChannelLeaving: any DiscordVoiceChannelLeaving { session }

    public func apply(_ preferences: DiscordIntegrationPreferences) {
        let wasEnabled = self.preferences.isEnabled
        self.preferences = preferences

        guard preferences.isEnabled else {
            if wasEnabled {
                disable()
            }
            return
        }

        if wasEnabled == false {
            enable()
        }
        if let clientID = preferences.clientID {
            session.start(clientID: clientID)
        } else {
            session.stop()
        }
    }

    public func authorize() {
        session.authorize()
    }

    public func forgetAuthorization() {
        session.forgetAuthorization()
    }

    public func reconnect() {
        session.reconnect()
    }

    private func enable() {
        microphoneRecording.excludeApplications(where: DiscordApplication.owns(bundleIdentifier:))
        callProvider.startObserving { [weak manager] activity in
            guard let manager else { return }
            if let activity {
                manager.register(activity)
            } else {
                manager.end(DiscordCallActivity.identity)
            }
        }
        callProvider.voiceStateDidChange(session.voiceState)
        workspace.startObservingLaunches { [weak session] in
            session?.discordBecameActive()
        }
    }

    /// The call activity is ended here rather than left to the provider: a
    /// provider that stops observing owes nobody an emission, and a call left on
    /// the island after the switch is off would be a Discord call shown twice
    /// once the microphone indicator starts reporting it again.
    private func disable() {
        workspace.stopObservingLaunches()
        session.stop()
        callProvider.stopObserving()
        manager.end(DiscordCallActivity.identity)
        microphoneRecording.includeAllApplications()
    }
}
