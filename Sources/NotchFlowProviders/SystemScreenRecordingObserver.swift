import AppKit
import Foundation

/// The screen-capture signal NotchFlow is actually allowed to see.
///
/// `docs/12-api-feasibility-matrix.md` row 14 records that the only public
/// account of an *active* screen-capture session is the one behind the Screen
/// Recording privacy category — and `docs/09-security-privacy-permissions.md`
/// forbids NotchFlow from asking for that permission, since an indicator that
/// demands the very capability it reports on is a worse trade than a narrower
/// indicator. What remains public *and* permission-free is the recording
/// process macOS itself runs: `NSWorkspace`'s launch and termination
/// notifications, which need no entitlement and never prompt.
///
/// So this observer reports the system's own screen recording — the one started
/// from the screenshot toolbar — and nothing else. What it cannot see is
/// recorded honestly in `.omo/evidence/task-46-notchflow-v1/detection-limits.md`
/// rather than papered over with a guess: a third-party recorder that leaves no
/// distinguishable process is simply not detected, and NotchFlow shows no
/// indicator instead of a fabricated one.
///
/// Nothing here polls. Both notifications are edges, and the running-application
/// list is read once at start to establish the state the app launched into.
@MainActor
public final class SystemScreenRecordingObserver: RecordingObserving {
    /// The system screen-recording UI, which stays running for the duration of
    /// a screenshot-toolbar recording.
    public static let systemRecorderBundleIdentifiers: Set<String> = [
        "com.apple.screencaptureui"
    ]

    private let workspaceCenter: NotificationCenter
    private let runningBundleIdentifiers: @Sendable () -> Set<String>
    private let recorderBundleIdentifiers: Set<String>
    private let now: () -> Date

    private let subscriptions = NotificationSubscriptionBag()
    private var latch = RecordingSessionLatch()

    public convenience init() {
        self.init(
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            runningBundleIdentifiers: {
                MainActor.assumeIsolated {
                    Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                }
            }
        )
    }

    init(
        workspaceCenter: NotificationCenter,
        runningBundleIdentifiers: @escaping @Sendable () -> Set<String>,
        recorderBundleIdentifiers: Set<String> = SystemScreenRecordingObserver
            .systemRecorderBundleIdentifiers,
        now: @escaping () -> Date = Date.init
    ) {
        self.workspaceCenter = workspaceCenter
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.recorderBundleIdentifiers = recorderBundleIdentifiers
        self.now = now
    }

    public func startObserving(_ observer: @escaping RecordingSessionObserver) {
        stopObserving()

        subscribe(to: NSWorkspace.didLaunchApplicationNotification, notifying: observer)
        subscribe(to: NSWorkspace.didTerminateApplicationNotification, notifying: observer)

        // A recording already in progress when NotchFlow launches is a real
        // state, not an edge we missed, so it is read once here rather than
        // waited for.
        emitCurrentState(to: observer)
    }

    public func stopObserving() {
        subscriptions.removeAll()
        latch.reset()
    }

    private func subscribe(
        to name: Notification.Name,
        notifying observer: @escaping RecordingSessionObserver
    ) {
        let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.emitCurrentState(to: observer)
            }
        }

        subscriptions.add(token, to: workspaceCenter)
    }

    private func emitCurrentState(to observer: @escaping RecordingSessionObserver) {
        let isRecording = runningBundleIdentifiers().isDisjoint(with: recorderBundleIdentifiers) == false

        guard latch.update(isRecording: isRecording, at: now) else { return }

        observer(latch.session)
    }
}
