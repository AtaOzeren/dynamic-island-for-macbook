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

/// The screen-capture signal KerNotch is actually allowed to see.
///
/// `docs/12-api-feasibility-matrix.md` row 14 records that the only public
/// account of an *active* screen-capture session is the one behind the Screen
/// Recording privacy category — and `docs/09-security-privacy-permissions.md`
/// forbids KerNotch from asking for that permission, since an indicator that
/// demands the very capability it reports on is a worse trade than a narrower
/// indicator. What remains public *and* permission-free is the recording
/// process macOS itself runs: `NSWorkspace` reports the capture UI lifecycle,
/// while ReplayKit's open recording movie distinguishes video capture from a
/// still screenshot. Neither signal needs an entitlement or prompt.
///
/// So this observer reports the system's own screen recording — the one started
/// from the screenshot toolbar — and nothing else. What it cannot see is
/// recorded honestly in `.omo/evidence/task-46-kernotch-v1/detection-limits.md`
/// rather than papered over with a guess: a third-party recorder that leaves no
/// distinguishable process is simply not detected, and KerNotch shows no
/// indicator instead of a fabricated one.
///
/// ReplayKit exposes no public start/stop notification for this system session,
/// so the probe is read when observation starts and whenever the capture UI
/// comes or goes; while the toolbar is open or a recording is under way, a
/// low-frequency tick keeps reading it, so both ends of the recording are seen.
/// Idle KerNotch has no timer, and opening the screenshot toolbar produces no
/// false recording activity.
///
/// Only the probe decides whether a recording is running. The capture UI can
/// quit while one is under way, and an observer that read its absence as "not
/// recording" showed nothing for the rest of the session.
///
/// What this cannot see is a recording the capture UI was never part of — one
/// started from the menu bar, or by another application. The folder the system
/// records into would reveal it, but `~/Library/Group Containers/`
/// `group.com.apple.screencapture` answers "Operation not permitted" without
/// Full Disk Access, so neither reading it nor watching it is available; and
/// the only signal left, the probe, has nothing to wake it. Detecting those
/// recordings means either polling on a clock or asking for the Screen
/// Recording permission this app refuses to ask for, and both were weighed and
/// declined — see `docs/06-activity-providers.md`.
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
    private var isCaptureUIRunning = false

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
            self?.captureUIStateDidChange()
        }
        isCaptureUIRunning = isRecorderRunning()
        // Read once here, because a recording already under way when KerNotch
        // starts is a recording the user is in the middle of.
        sampleRecordingState()
    }

    public func stopObserving() {
        subscriptions.removeAll()
        runningApplicationsObservation?.invalidate()
        runningApplicationsObservation = nil
        scheduler.cancel()
        sessionObserver = nil
        isCaptureUIRunning = false
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
    /// KerNotch.
    private func handle(_ edge: ApplicationLifecycleEdge) {
        guard
            let bundleIdentifier = edge.bundleIdentifier,
            recorderBundleIdentifiers.contains(bundleIdentifier)
        else {
            captureUIStateDidChange()
            return
        }

        switch edge.notificationName {
        case NSWorkspace.didLaunchApplicationNotification:
            isCaptureUIRunning = true
        case NSWorkspace.didTerminateApplicationNotification:
            isCaptureUIRunning = false
        default:
            isCaptureUIRunning = isRecorderRunning()
        }

        sampleRecordingState()
    }

    /// The running set changes on every application launch and quit, which is
    /// far too often to read the probe on. Only the capture UI coming or going
    /// is worth a reading.
    private func captureUIStateDidChange() {
        let wasRunning = isCaptureUIRunning
        isCaptureUIRunning = isRecorderRunning()

        guard isCaptureUIRunning != wasRunning else {
            synchronizeSampling()
            return
        }

        sampleRecordingState()
    }

    private func isRecorderRunning() -> Bool {
        runningBundleIdentifiers().isDisjoint(with: recorderBundleIdentifiers) == false
    }

    private func sampleRecordingState() {
        emit(isRecording: isScreenRecording())
        synchronizeSampling()
    }

    /// The tick runs only while there is something to watch for: a recording to
    /// see the end of, or an open toolbar that may start one. Otherwise it is
    /// cancelled, which is the idle-cost rule in
    /// `docs/02-performance-contract.md`.
    private func synchronizeSampling() {
        guard isCaptureUIRunning || latch.session != nil else {
            scheduler.cancel()
            return
        }
        guard scheduler.isScheduled == false else { return }

        scheduler.schedule { [weak self] in
            self?.sampleRecordingState()
        }
    }

    private func emit(isRecording: Bool) {
        guard latch.update(isRecording: isRecording, at: now) else { return }

        sessionObserver?(latch.session)
    }
}
