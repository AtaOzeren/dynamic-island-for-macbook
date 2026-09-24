import KerNotchCore

/// Turns the two Discord signals into the call activity the manager registers.
///
/// A call is shown while Discord holds the microphone *or* the RPC connection
/// reports a voice channel. Either alone is enough: the microphone needs no
/// setup, and the channel covers a call whose input CoreAudio cannot attribute —
/// before macOS 14.2, or on a push-to-talk setup that closes the stream.
///
/// The microphone is observed only between `startObserving` and
/// `stopObserving`, which the integration ties to its own switch, so a user who
/// never enables Discord never pays for process attribution.
@MainActor
public final class DiscordCallProvider {
    /// Called when Discord takes the microphone — a sign its RPC socket is up,
    /// worth a reconnect for a session that had given up waiting.
    public var onDiscordCaptureStarted: (@MainActor () -> Void)?

    private let monitor: MicrophoneActivityMonitor

    private var observer: (@MainActor (DiscordCallActivity?) -> Void)?
    private var observation: MicrophoneActivityMonitor.Observation?
    private var isDiscordCapturing = false
    private var voiceState = DiscordVoiceState.unknown
    private var activity: DiscordCallActivity?

    public init(monitor: MicrophoneActivityMonitor) {
        self.monitor = monitor
    }

    public var currentActivity: DiscordCallActivity? { activity }

    public func startObserving(_ observer: @escaping @MainActor (DiscordCallActivity?) -> Void) {
        stopObserving()
        self.observer = observer
        observation = monitor.observeClients { [weak self] microphone in
            self?.microphoneDidChange(microphone)
        }
    }

    public func stopObserving() {
        if let observation {
            monitor.removeObservation(observation)
        }
        observation = nil
        observer = nil
        isDiscordCapturing = false
        activity = nil
    }

    public func voiceStateDidChange(_ voiceState: DiscordVoiceState) {
        self.voiceState = voiceState
        emitIfChanged()
    }

    private func microphoneDidChange(_ microphone: MicrophoneActivity) {
        let wasCapturing = isDiscordCapturing
        isDiscordCapturing =
            microphone.clients?.contains { client in
                guard case .application(let bundleIdentifier) = client else { return false }
                return DiscordApplication.owns(bundleIdentifier: bundleIdentifier)
            } ?? false
        emitIfChanged()

        if isDiscordCapturing, wasCapturing == false {
            onDiscordCaptureStarted?()
        }
    }

    private func emitIfChanged() {
        guard let observer else { return }

        let isInCall = isDiscordCapturing || voiceState.channel != nil
        let next =
            isInCall
            ? DiscordCallActivity(
                channel: voiceState.channel,
                isMuted: voiceState.isMuted,
                isDeafened: voiceState.isDeafened
            )
            : nil
        guard next != activity else { return }

        activity = next
        observer(next)
    }
}
