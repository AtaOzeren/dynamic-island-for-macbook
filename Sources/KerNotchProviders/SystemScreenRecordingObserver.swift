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
/// so the probe is read on three occasions rather than on a clock that runs
/// while nothing is happening: when observation starts, when the capture UI
/// comes or goes, and when the recordings folder changes. While a recording is
/// under way — or the toolbar is open — a low-frequency tick keeps reading it,
/// so the end is noticed too. Idle KerNotch has no timer, and opening the
/// screenshot toolbar produces no false recording activity.
///
/// Only the probe decides. The capture UI quits once recording is under way,
/// and an observer that read its absence as "not recording" showed nothing for
/// the whole session — and missed a recording that was already running when
/// KerNotch started.
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

    private let directoryWatcher: any RecordingsDirectoryWatching
    private let subscriptions = NotificationSubscriptionBag()
    private var runningApplicationsObservation: NSKeyValueObservation?
    private var sessionObserver: RecordingSessionObserver?
    private var latch = RecordingSessionLatch()
    private var isCaptureUIRunning = false
    /// Until when a change in the recordings folder keeps the probe being read.
    ///
    /// A recording announces itself in that folder before it is fully under
    /// way, so the first reading after the change can still say "no". Without a
    /// window to keep reading in, the tick was cancelled on that reading and
    /// the indicator waited for whatever happened to come next.
    private var settlingDeadline: Date?

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
            scheduler: DispatchTickScheduler(),
            directoryWatcher: ScreenRecordingsDirectoryWatcher()
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
        directoryWatcher: any RecordingsDirectoryWatching = InertRecordingsDirectoryWatcher(),
        recorderBundleIdentifiers: Set<String> = SystemScreenRecordingObserver
            .systemRecorderBundleIdentifiers,
        now: @escaping () -> Date = Date.init
    ) {
        self.workspaceCenter = workspaceCenter
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.observeRunningApplications = observeRunningApplications
        self.isScreenRecording = isScreenRecording
        self.scheduler = scheduler
        self.directoryWatcher = directoryWatcher
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
        directoryWatcher.startWatching { [weak self] in
            self?.recordingsDirectoryDidChange()
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
        directoryWatcher.stopWatching()
        scheduler.cancel()
        sessionObserver = nil
        isCaptureUIRunning = false
        settlingDeadline = nil
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

    /// How long the probe keeps being read after the recordings folder changes.
    /// Long enough for a recording to get going, short enough that a folder
    /// touched for any other reason costs a handful of readings.
    private static let settlingWindow: TimeInterval = 10

    private func recordingsDirectoryDidChange() {
        settlingDeadline = now().addingTimeInterval(Self.settlingWindow)
        sampleRecordingState()
    }

    private func isSettling() -> Bool {
        guard let settlingDeadline else { return false }
        return now() < settlingDeadline
    }

    private func isRecorderRunning() -> Bool {
        runningBundleIdentifiers().isDisjoint(with: recorderBundleIdentifiers) == false
    }

    private func sampleRecordingState() {
        emit(isRecording: isScreenRecording())
        synchronizeSampling()
    }

    /// The tick runs only while there is something to watch for: a recording to
    /// see the end of, an open toolbar that may start one, or a folder that just
    /// changed and may be a recording getting under way. Otherwise it is
    /// cancelled, which is the idle-cost rule in
    /// `docs/02-performance-contract.md`.
    private func synchronizeSampling() {
        guard isCaptureUIRunning || latch.session != nil || isSettling() else {
            scheduler.cancel()
            settlingDeadline = nil
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
