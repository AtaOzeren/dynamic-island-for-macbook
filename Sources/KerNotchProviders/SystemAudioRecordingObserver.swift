import CoreAudio
import Foundation

/// The microphone-in-use signal KerNotch is actually allowed to see, as a
/// recording session.
///
/// `docs/12-api-feasibility-matrix.md` row 15 is blunt about this: there is no
/// documented Apple API whose stated purpose is "is any process using the
/// microphone", and the orange-dot indicator behind that question is not
/// exposed for third parties to read. The permission the row names —
/// `kTCCServiceMicrophone` — governs *KerNotch's own* capture, and
/// `docs/09-security-privacy-permissions.md` forbids the recording indicators
/// from requiring it: an indicator that demands the capability it reports on is
/// a worse trade than a narrower indicator. `MicrophoneActivityMonitor` reads
/// the permission-free CoreAudio state this observer is built on.
///
/// An integration with its own activity — Discord, while it is enabled — takes
/// its application out of this indicator, so a Discord call is not reported
/// twice. The exclusion is conservative by construction: the session ends only
/// when every client of the microphone is known and excluded. A microphone
/// nobody can attribute is still a microphone in use, and an extra indicator is
/// the cheaper failure than a missed recording.
@MainActor
public final class SystemAudioRecordingObserver: RecordingObserving {
    private let monitor: MicrophoneActivityMonitor
    private let now: () -> Date

    private var latch = RecordingSessionLatch()
    private var observer: RecordingSessionObserver?
    private var observation: MicrophoneActivityMonitor.Observation?
    private var isExcluded: (@Sendable (String) -> Bool)?

    public init(monitor: MicrophoneActivityMonitor, now: @escaping () -> Date = Date.init) {
        self.monitor = monitor
        self.now = now
    }

    convenience init(
        inputDeviceIdentifiers: @escaping @Sendable () -> [AudioObjectID],
        isDeviceRunning: @escaping @Sendable (AudioObjectID) -> Bool,
        listeners: any AudioPropertyListening,
        now: @escaping () -> Date = Date.init
    ) {
        let hardware = MicrophoneHardware(
            inputDeviceIdentifiers: inputDeviceIdentifiers,
            isDeviceRunning: isDeviceRunning,
            processIdentifiers: { nil },
            processBundleIdentifier: { _ in nil },
            isProcessRunningInput: { _ in false }
        )
        self.init(
            monitor: MicrophoneActivityMonitor(hardware: hardware, listeners: listeners),
            now: now
        )
    }

    public func startObserving(_ observer: @escaping RecordingSessionObserver) {
        stopObserving()
        self.observer = observer
        subscribe()
    }

    public func stopObserving() {
        if let observation {
            monitor.removeObservation(observation)
        }
        observation = nil
        latch.reset()
        observer = nil
    }

    /// Leaves the applications `isExcluded` matches out of this indicator.
    public func excludeApplications(where isExcluded: @escaping @Sendable (String) -> Bool) {
        self.isExcluded = isExcluded
        resubscribe()
    }

    /// Reports every client of the microphone again.
    public func includeAllApplications() {
        guard isExcluded != nil else { return }
        isExcluded = nil
        resubscribe()
    }

    /// Only an observer that excludes someone asks the monitor who is using the
    /// microphone, so without an exclusion this costs what it always did.
    private func subscribe() {
        let deliver: MicrophoneActivityMonitor.Observer = { [weak self] activity in
            self?.apply(activity)
        }
        observation =
            isExcluded == nil
            ? monitor.observeRunningState(deliver)
            : monitor.observeClients(deliver)
    }

    /// The new observation is taken before the old one is released, so the
    /// monitor never sees zero observers and never tears down the device
    /// listeners in between.
    private func resubscribe() {
        guard observer != nil else { return }

        let previous = observation
        subscribe()
        if let previous {
            monitor.removeObservation(previous)
        }
    }

    private func apply(_ activity: MicrophoneActivity) {
        guard let observer else { return }
        guard latch.update(isRecording: isReportable(activity), at: now) else { return }

        observer(latch.session)
    }

    private func isReportable(_ activity: MicrophoneActivity) -> Bool {
        guard activity.isRunning else { return false }
        guard let isExcluded, let clients = activity.clients, clients.isEmpty == false else {
            return true
        }

        return clients.contains { client in
            switch client {
            case .application(let bundleIdentifier): isExcluded(bundleIdentifier) == false
            case .unidentifiedProcess: true
            }
        }
    }
}
