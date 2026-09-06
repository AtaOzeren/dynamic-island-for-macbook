import AppKit
import Foundation
import NotchFlowCore
import NotchFlowProviders
import UserNotifications
import os

// MARK: - Collaborators

/// The island, as the watchdog needs it: two calls, both on the main thread.
///
/// Narrow on purpose. Nothing here can switch mouse observing off, because a
/// degraded island that stops answering hover and clicks reads as a crashed
/// app — the exact report the watchdog exists to prevent.
protocol IslandMotionDegrading: AnyObject, Sendable {
    @MainActor func enterDegradedMode()
    @MainActor func exitDegradedMode()
}

/// Where the degrade path's UI work is enqueued; injectable so a test can hold
/// the block and prove the diagnostics snapshot was written before it ran.
protocol WatchdogMainThreadDispatching: Sendable {
    func dispatch(_ work: @escaping @MainActor @Sendable () -> Void)
}

protocol WatchdogDiagnosticsWriting: Sendable {
    func writeDegradeSnapshot(
        cpuPercent: Double,
        samples: [CPUSample],
        mainThreadResponsive: Bool,
        context: CPUWatchdogSupervisor.Context
    )

    /// The saved report's URL, or `nil` when writing failed. The alarm path
    /// carries on either way: a restart without a report still beats a heater.
    func writeAlarmReport(
        reason: String,
        cpuPercent: Double,
        samples: [CPUSample],
        mainThreadResponsive: Bool,
        context: CPUWatchdogSupervisor.Context
    ) -> URL?
}

protocol WatchdogEventRecording: Sendable {
    func write(_ event: WatchdogEventMarker.Event)
}

protocol WatchdogNotifying: Sendable {
    func requestAuthorizationIfNeeded()
    func post(body: String)
}

protocol WatchdogApplicationRelaunching: Sendable {
    /// Completion runs on an arbitrary queue and carries the failure, if any.
    func relaunch(completion: @escaping @Sendable (Error?) -> Void)
}

// MARK: - Supervisor

/// Turns `CPUWatchdog`'s decisions into the things that actually happen to the
/// running app: a degraded island, a diagnostics report, a relaunch, a quit.
///
/// **The thread contract is the point of this type.** Every alarm step runs on
/// the watchdog queue and none of them may wait on the main thread — an alarm
/// fires precisely when the main thread may be unable to answer, so a hop to
/// main would deadlock the recovery it is meant to perform. Only `.degrade` and
/// `.restore` touch main, because only they touch UI, and they are the two
/// actions the app is still healthy enough to serve.
final class CPUWatchdogSupervisor: @unchecked Sendable {
    /// The two facts a diagnostics report wants that only the main thread
    /// knows. Cached rather than read at alarm time, for the reason above.
    struct Context: Sendable {
        var displayTarget: String
        var activityKinds: [String]

        static let unknown = Context(displayTarget: "unknown", activityKinds: [])
    }

    /// The notification bodies, injected so the tests do not depend on the
    /// catalog and the catalog does not depend on the tests.
    struct NotificationCopy: Sendable {
        let degrade: String
        let restart: String
        let quit: @Sendable (String?) -> String

        static var standard: NotificationCopy {
            NotificationCopy(
                degrade: String(
                    localized: "NotchFlow is using more CPU than expected. Animations are paused while it recovers."
                ),
                restart: String(
                    localized: "NotchFlow is restarting because CPU stayed high despite protective measures. A diagnostic report was saved."
                ),
                quit: { reportPath in
                    String(
                        format: String(
                            localized: "NotchFlow quit itself: CPU stayed high after 3 restarts within an hour. Diagnostic report: %@"
                        ),
                        reportPath ?? "—"
                    )
                }
            )
        }
    }

    private static let logger = Logger(
        subsystem: "com.notchflow.NotchFlow",
        category: "cpu-watchdog"
    )
    /// How many samples a report carries. Six covers both the 30 s degrade
    /// window and the run-up to an alarm at the 5 s sample interval.
    private static let retainedSampleCount = 6

    private let island: any IslandMotionDegrading
    private let mainThread: any WatchdogMainThreadDispatching
    private let diagnostics: any WatchdogDiagnosticsWriting
    private let restartLedger: any RestartLedger
    private let marker: any WatchdogEventRecording
    private let notifications: any WatchdogNotifying
    private let relauncher: any WatchdogApplicationRelaunching
    private let copy: NotificationCopy
    private let now: @Sendable () -> ContinuousClock.Instant
    private let stopListener: @Sendable () -> Void
    private let terminate: @Sendable () -> Void
    private let contextProvider: (@MainActor @Sendable () -> Context)?

    private let lock = NSLock()
    private var recentSamples: [CPUSample] = []
    private var cachedContext: Context = .unknown
    /// One Tier 1 notification per episode: the state machine can re-enter
    /// `.degrade` after a failed recovery, and a notification per attempt is
    /// noise about a condition the user has already been told about.
    private var hasNotifiedThisEpisode = false

    private var sampler: ProcessCPUSampler?
    private var watchdog: CPUWatchdog?

    init(
        island: any IslandMotionDegrading,
        mainThread: any WatchdogMainThreadDispatching,
        diagnostics: any WatchdogDiagnosticsWriting,
        restartLedger: any RestartLedger,
        marker: any WatchdogEventRecording,
        notifications: any WatchdogNotifying,
        relauncher: any WatchdogApplicationRelaunching,
        copy: NotificationCopy,
        now: @escaping @Sendable () -> ContinuousClock.Instant,
        stopListener: @escaping @Sendable () -> Void,
        terminate: @escaping @Sendable () -> Void,
        contextProvider: (@MainActor @Sendable () -> Context)? = nil
    ) {
        self.island = island
        self.mainThread = mainThread
        self.diagnostics = diagnostics
        self.restartLedger = restartLedger
        self.marker = marker
        self.notifications = notifications
        self.relauncher = relauncher
        self.copy = copy
        self.now = now
        self.stopListener = stopListener
        self.terminate = terminate
        self.contextProvider = contextProvider
    }

    // MARK: Gate

    /// Whether this launch is one the watchdog belongs in.
    ///
    /// A UI test drives the app faster than any human and would trip the
    /// thresholds on purpose; the setting is the documented kill switch
    /// (`SettingsKey.cpuWatchdogDisabled`, no UI) for a user whose machine the
    /// watchdog misjudges.
    static func shouldStart(isUITesting: Bool, isDisabledBySetting: Bool) -> Bool {
        isUITesting == false && isDisabledBySetting == false
    }

    // MARK: Running

    /// Arms the sampler and starts feeding the state machine. Call from the
    /// main thread once the island is up; everything after this runs on the
    /// sampler's own watchdog queue.
    @MainActor
    func start(configuration: CPUWatchdog.Configuration, sampler: ProcessCPUSampler) {
        cacheContext(contextProvider?() ?? .unknown)

        let watchdog = CPUWatchdog(
            configuration: configuration,
            restartLedger: restartLedger,
            now: { [sampler] in sampler.now }
        )
        self.watchdog = watchdog
        self.sampler = sampler

        sampler.start { [weak self] sample in
            self?.receive(sample)
        }
        Self.logger.info("CPU watchdog armed.")
    }

    func stop() {
        sampler?.stop()
        sampler = nil
        watchdog = nil
    }

    /// One sample, on the watchdog queue.
    private func receive(_ sample: CPUSample) {
        lock.lock()
        recentSamples.append(sample)
        if recentSamples.count > Self.retainedSampleCount {
            recentSamples.removeFirst(recentSamples.count - Self.retainedSampleCount)
        }
        lock.unlock()

        guard let action = watchdog?.feed(sample) else { return }
        perform(action, for: sample)
    }

    // MARK: Actions

    /// Runs one decision. Called on the watchdog queue in production; the tests
    /// call it directly, which is the same contract minus the timer.
    func perform(_ action: CPUWatchdog.Action, for sample: CPUSample) {
        switch action {
        case .degrade:
            degrade(for: sample)
        case .restore:
            restore()
        case let .alarmAndRestart(reason):
            alarmAndRestart(reason: reason, sample: sample)
        case let .alarmAndQuit(reason):
            alarmAndQuit(reason: reason, sample: sample)
        }
    }

    /// The snapshot is written here, before the hop, so a main thread too busy
    /// to run the block still leaves evidence behind.
    ///
    /// There is deliberately no escalation timer on the dispatch: if the block
    /// has not run within 10 s the liveness probe already reports the main
    /// thread unresponsive, and the state machine escalates to an alarm on its
    /// own. A second timer here would race that one for the same outcome.
    private func degrade(for sample: CPUSample) {
        Self.logger.notice(
            "Degrading: CPU \(sample.cpuPercent, format: .fixed(precision: 1), privacy: .public)%"
        )
        diagnostics.writeDegradeSnapshot(
            cpuPercent: sample.cpuPercent,
            samples: samplesSnapshot(),
            mainThreadResponsive: sample.mainThreadResponsive,
            context: context()
        )

        mainThread.dispatch { [self] in
            island.enterDegradedMode()
            cacheContext(contextProvider?() ?? context())
            notifications.requestAuthorizationIfNeeded()
            guard claimEpisodeNotification() else { return }
            notifications.post(body: copy.degrade)
        }
    }

    private func restore() {
        Self.logger.notice("Recovered: restoring island motion.")
        mainThread.dispatch { [self] in
            island.exitDegradedMode()
            releaseEpisodeNotification()
        }
    }

    /// Six steps, all on the watchdog queue, in the order the next launch reads
    /// them: report, ledger, marker, notification, relaunch, exit. Do not
    /// "simplify" any of them onto the main thread — see the type's note.
    private func alarmAndRestart(reason: CPUWatchdog.AlarmReason, sample: CPUSample) {
        Self.logger.error(
            "Alarm (\(String(describing: reason), privacy: .public)): restarting."
        )
        let reportPath = writeAlarmReport(reason: reason, sample: sample)?.path
        restartLedger.recordRestart(at: now())
        writeMarker(.relaunch, reason: reason, reportPath: reportPath)
        notifications.post(body: copy.restart)

        relauncher.relaunch { [self] error in
            if let error {
                // The marker is rewritten rather than left claiming a relaunch
                // that never happened: the next launch — by login item or by
                // the user — has to describe what actually occurred.
                Self.logger.error(
                    "Relaunch refused: \(error.localizedDescription, privacy: .public)"
                )
                writeMarker(.quit, reason: reason, reportPath: reportPath)
            }
            stopListener()
            terminate()
        }
    }

    /// The restart budget is spent; this is the end of the episode, so no
    /// ledger entry and no relaunch.
    private func alarmAndQuit(reason: CPUWatchdog.AlarmReason, sample: CPUSample) {
        Self.logger.fault(
            "Alarm (\(String(describing: reason), privacy: .public)): quitting."
        )
        let reportPath = writeAlarmReport(reason: reason, sample: sample)?.path
        writeMarker(.quit, reason: reason, reportPath: reportPath)
        notifications.post(body: copy.quit(reportPath))

        stopListener()
        terminate()
    }

    // MARK: Helpers

    private func writeAlarmReport(reason: CPUWatchdog.AlarmReason, sample: CPUSample) -> URL? {
        diagnostics.writeAlarmReport(
            reason: String(describing: reason),
            cpuPercent: sample.cpuPercent,
            samples: samplesSnapshot(),
            mainThreadResponsive: sample.mainThreadResponsive,
            context: context()
        )
    }

    private func writeMarker(
        _ action: WatchdogEventMarker.Action,
        reason: CPUWatchdog.AlarmReason,
        reportPath: String?
    ) {
        marker.write(
            WatchdogEventMarker.Event(
                action: action,
                reason: String(describing: reason),
                at: Date(),
                reportPath: reportPath
            )
        )
    }

    private func samplesSnapshot() -> [CPUSample] {
        lock.lock()
        defer { lock.unlock() }
        return recentSamples
    }

    private func context() -> Context {
        lock.lock()
        defer { lock.unlock() }
        return cachedContext
    }

    private func cacheContext(_ context: Context) {
        lock.lock()
        cachedContext = context
        lock.unlock()
    }

    private func claimEpisodeNotification() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard hasNotifiedThisEpisode == false else { return false }
        hasNotifiedThisEpisode = true
        return true
    }

    private func releaseEpisodeNotification() {
        lock.lock()
        hasNotifiedThisEpisode = false
        lock.unlock()
    }
}

// MARK: - Production collaborators

struct DispatchWatchdogMainThread: WatchdogMainThreadDispatching {
    func dispatch(_ work: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(work) }
    }
}

/// Adapts `RunawayDiagnostics` to the two calls the supervisor makes, and
/// swallows write failures into a log line: a report that could not be saved
/// must not stop a recovery.
struct RunawayDiagnosticsWriter: WatchdogDiagnosticsWriting {
    private static let logger = Logger(
        subsystem: "com.notchflow.NotchFlow",
        category: "cpu-watchdog"
    )

    let diagnostics: RunawayDiagnostics

    func writeDegradeSnapshot(
        cpuPercent: Double,
        samples: [CPUSample],
        mainThreadResponsive: Bool,
        context: CPUWatchdogSupervisor.Context
    ) {
        do {
            try diagnostics.writeSnapshot(
                cpuPercent: cpuPercent,
                sampleHistory: samples,
                transitions: ["normal → degraded"],
                mainThreadResponsive: mainThreadResponsive,
                displayTarget: context.displayTarget,
                activityKinds: context.activityKinds
            )
        } catch {
            Self.logger.error(
                "Degrade snapshot failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func writeAlarmReport(
        reason: String,
        cpuPercent: Double,
        samples: [CPUSample],
        mainThreadResponsive: Bool,
        context: CPUWatchdogSupervisor.Context
    ) -> URL? {
        do {
            return try diagnostics.writeFullReport(
                cpuPercent: cpuPercent,
                sampleHistory: samples,
                transitions: ["degraded → alarmed"],
                mainThreadResponsive: mainThreadResponsive,
                displayTarget: context.displayTarget,
                activityKinds: context.activityKinds,
                reason: reason
            )
        } catch {
            Self.logger.error(
                "Alarm report failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}

extension WatchdogEventMarker: WatchdogEventRecording {}

/// Every `UNUserNotificationCenter` call is behind a bundle-identifier check:
/// the framework traps in a binary with no bundle, which is what `swift run`
/// produces.
struct UserNotificationPoster: WatchdogNotifying {
    private static let logger = Logger(
        subsystem: "com.notchflow.NotchFlow",
        category: "cpu-watchdog"
    )

    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// Whether the user would actually see a posted notification. Drives the
    /// post-launch alert: an unauthorized process has to say what happened some
    /// other way.
    static func isAuthorized(_ completion: @escaping @Sendable (Bool) -> Void) {
        guard isAvailable else {
            completion(false)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus == .authorized)
        }
    }

    func requestAuthorizationIfNeeded() {
        guard Self.isAvailable else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, error in
                if let error {
                    Self.logger.error(
                        "Notification authorization failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
    }

    func post(body: String) {
        guard Self.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "NotchFlow"
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        )
    }
}

/// The relaunch, in the shape `restartApplication()` already uses.
///
/// `NSWorkspace.openApplication` rather than `/usr/bin/open` through `Process`:
/// the sandboxed App Store build cannot spawn it.
struct WorkspaceRelauncher: WatchdogApplicationRelaunching {
    func relaunch(completion: @escaping @Sendable (Error?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            completion(error)
        }
    }
}
