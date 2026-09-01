import AppKit
import Foundation

protocol RunningApplicationDescribing {
    var bundleIdentifier: String? { get }
}

extension NSRunningApplication: RunningApplicationDescribing {}

private struct ApplicationLifecycleEdge: Sendable {
    let notificationName: Notification.Name
    let bundleIdentifier: String?
}

/// The screen-capture signal NotchFlow is actually allowed to see.
///
/// `docs/12-api-feasibility-matrix.md` row 14 records that the only public
/// account of an *active* screen-capture session is the one behind the Screen
/// Recording privacy category — and `docs/09-security-privacy-permissions.md`
/// forbids NotchFlow from asking for that permission, since an indicator that
/// demands the very capability it reports on is a worse trade than a narrower
/// indicator. What remains public *and* permission-free is the recording
/// process macOS itself runs: `NSWorkspace` reports the capture UI lifecycle,
/// while ReplayKit's open recording movie distinguishes video capture from a
/// still screenshot. Neither signal needs an entitlement or prompt.
///
/// So this observer reports the system's own screen recording — the one started
/// from the screenshot toolbar — and nothing else. What it cannot see is
/// recorded honestly in `.omo/evidence/task-46-notchflow-v1/detection-limits.md`
/// rather than papered over with a guess: a third-party recorder that leaves no
/// distinguishable process is simply not detected, and NotchFlow shows no
/// indicator instead of a fabricated one.
///
/// ReplayKit exposes no public start/stop notification for this system session.
/// A low-frequency probe therefore runs only while the capture UI exists. Idle
/// NotchFlow has no timer, and opening the screenshot toolbar produces no false
/// recording activity.
@MainActor
public final class SystemScreenRecordingObserver: RecordingObserving {
    /// The system screen-recording UI, which stays running for the duration of
    /// a screenshot-toolbar recording.
    public static let systemRecorderBundleIdentifiers: Set<String> = [
        "com.apple.screencaptureui"
    ]

    private let workspaceCenter: NotificationCenter
    private let runningBundleIdentifiers: @Sendable () -> Set<String>
    private let observeRunningApplications: (
        @escaping @MainActor @Sendable () -> Void
    ) -> NSKeyValueObservation?
    private let isScreenRecording: @MainActor () -> Bool
    private let scheduler: any TickScheduling
    private let recorderBundleIdentifiers: Set<String>
    private let now: () -> Date

    private let subscriptions = NotificationSubscriptionBag()
    private var runningApplicationsObservation: NSKeyValueObservation?
    private var sessionObserver: RecordingSessionObserver?
    private var latch = RecordingSessionLatch()

    public convenience init() {
        let workspace = NSWorkspace.shared
        let recordingProbe = ReplayScreenRecordingProbe()
        self.init(
            workspaceCenter: workspace.notificationCenter,
            runningBundleIdentifiers: {
                MainActor.assumeIsolated {
                    Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                }
            },
            observeRunningApplications: { reconciliation in
                workspace.observe(\.runningApplications, options: [.new]) { _, _ in
                    Task { @MainActor in
                        reconciliation()
                    }
                }
            },
            isScreenRecording: { recordingProbe.isRecording() },
            scheduler: DispatchTickScheduler()
        )
    }

    init(
        workspaceCenter: NotificationCenter,
        runningBundleIdentifiers: @escaping @Sendable () -> Set<String>,
        observeRunningApplications: @escaping (
            @escaping @MainActor @Sendable () -> Void
        ) -> NSKeyValueObservation? = { _ in nil },
        isScreenRecording: @escaping @MainActor () -> Bool = { false },
        scheduler: any TickScheduling = DispatchTickScheduler(),
        recorderBundleIdentifiers: Set<String> = SystemScreenRecordingObserver
            .systemRecorderBundleIdentifiers,
        now: @escaping () -> Date = Date.init
    ) {
        self.workspaceCenter = workspaceCenter
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.observeRunningApplications = observeRunningApplications
        self.isScreenRecording = isScreenRecording
        self.scheduler = scheduler
        self.recorderBundleIdentifiers = recorderBundleIdentifiers
        self.now = now
    }

    public func startObserving(_ observer: @escaping RecordingSessionObserver) {
        stopObserving()
        sessionObserver = observer

        subscribe(to: NSWorkspace.didLaunchApplicationNotification)
        subscribe(to: NSWorkspace.didTerminateApplicationNotification)
        runningApplicationsObservation = observeRunningApplications { [weak self] in
            self?.synchronizeCaptureUIState()
        }

        synchronizeCaptureUIState()
    }

    public func stopObserving() {
        subscriptions.removeAll()
        runningApplicationsObservation?.invalidate()
        runningApplicationsObservation = nil
        scheduler.cancel()
        sessionObserver = nil
        latch.reset()
    }

    private func subscribe(to name: Notification.Name) {
        let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? any RunningApplicationDescribing
            let edge = ApplicationLifecycleEdge(
                notificationName: notification.name,
                bundleIdentifier: application?.bundleIdentifier
            )
            MainActor.assumeIsolated { [weak self] in
                self?.handle(edge)
            }
        }

        subscriptions.add(token, to: workspaceCenter)
    }

    /// The launched/terminated application in the notification is authoritative
    /// for that edge. `runningApplications` can trail the notification by one
    /// run-loop turn, which would otherwise miss a recording that starts after
    /// NotchFlow.
    private func handle(_ edge: ApplicationLifecycleEdge) {
        guard
            let bundleIdentifier = edge.bundleIdentifier,
            recorderBundleIdentifiers.contains(bundleIdentifier)
        else {
            synchronizeCaptureUIState()
            return
        }

        switch edge.notificationName {
        case NSWorkspace.didLaunchApplicationNotification:
            synchronizeCaptureUI(isRunning: true)
        case NSWorkspace.didTerminateApplicationNotification:
            synchronizeCaptureUI(isRunning: false)
        default:
            synchronizeCaptureUIState()
        }
    }

    private func synchronizeCaptureUIState() {
        let isRunning = runningBundleIdentifiers().isDisjoint(with: recorderBundleIdentifiers) == false
        synchronizeCaptureUI(isRunning: isRunning)
    }

    private func synchronizeCaptureUI(isRunning: Bool) {
        guard isRunning else {
            scheduler.cancel()
            emit(isRecording: false)
            return
        }

        if scheduler.isScheduled == false {
            scheduler.schedule { [weak self] in
                self?.sampleRecordingState()
            }
        }

        sampleRecordingState()
    }

    private func sampleRecordingState() {
        emit(isRecording: isScreenRecording())
    }

    private func emit(isRecording: Bool) {
        guard latch.update(isRecording: isRecording, at: now) else { return }

        sessionObserver?(latch.session)
    }
}
