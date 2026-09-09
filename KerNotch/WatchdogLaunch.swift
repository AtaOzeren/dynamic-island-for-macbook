import AppKit
import Foundation
import KerNotchCore
import KerNotchProviders
import os

extension IslandPresenter: IslandMotionDegrading {}

/// The CPU watchdog's half of the composition root: it owns the supervisor, the
/// sampler that feeds it, and the marker the previous run may have left behind.
///
/// One object rather than three loose locals because all three have the same
/// lifetime requirement — a supervisor that deallocates takes its sampler's
/// timer with it, which is indistinguishable from never having armed one.
@MainActor
final class WatchdogLaunch {
    private static let logger = Logger(
        subsystem: "com.kernotch.KerNotch",
        category: "cpu-watchdog"
    )

    private let island: IslandPresenter
    private let marker: WatchdogEventMarker
    private let sampler: ProcessCPUSampler
    private let supervisor: CPUWatchdogSupervisor
    private let configuration: CPUWatchdog.Configuration

    init(
        island: IslandPresenter,
        stopListener: @escaping @Sendable () -> Void,
        context: @escaping @MainActor @Sendable () -> CPUWatchdogSupervisor.Context
    ) {
        let marker = WatchdogEventMarker()
        // The sampler's cadence comes from the same configuration the state
        // machine's windows do, so a scaled clock scales both together.
        let configuration = Self.resolvedConfiguration()
        let sampler = ProcessCPUSampler(configuration: configuration)
        self.configuration = configuration
        self.island = island
        self.marker = marker
        self.sampler = sampler
        supervisor = CPUWatchdogSupervisor(
            island: island,
            mainThread: DispatchWatchdogMainThread(),
            diagnostics: RunawayDiagnosticsWriter(diagnostics: RunawayDiagnostics()),
            // Constructed once, and once only: the ledger anchors a single
            // instant-to-date pair so the restart budget survives the restart
            // it is counting. A per-call ledger would re-anchor and forget.
            restartLedger: RestartLedgerFile(),
            marker: marker,
            notifications: UserNotificationPoster(),
            relauncher: WorkspaceRelauncher(),
            copy: .standard,
            now: { sampler.now },
            stopListener: stopListener,
            // `exit` rather than `NSApp.terminate`: the alarm path runs on the
            // watchdog queue precisely because the main thread may be unable to
            // answer, and `terminate` is a main-thread round trip. The failure
            // status distinguishes a watchdog kill from the user quitting for
            // anything reading exit codes; it starts nothing, because the login
            // item is an `SMAppService.mainApp` registration with no KeepAlive.
            terminate: { exit(EXIT_FAILURE) },
            contextProvider: context
        )
    }

    /// Arms the watchdog, or says once why it stayed off.
    func startIfAllowed(isUITesting: Bool, isDisabledBySetting: Bool) {
        if let refusal = WatchdogStartRefusal.reason(
            isUITesting: isUITesting,
            isDisabledBySetting: isDisabledBySetting
        ) {
            Self.logger.notice(
                "CPU watchdog not started: \(refusal.logDescription, privacy: .public)"
            )
            return
        }
        if configuration.timeScale != 1 {
            Self.logger.notice(
                "CPU watchdog on a fast clock: every duration scaled by \(self.configuration.timeScale, privacy: .public)."
            )
        }
        supervisor.start(configuration: configuration, sampler: sampler)
    }

    /// The watchdog's durations for this launch.
    ///
    /// `--cpu-drill-fast-clock` divides every one of them by ten so a drill can
    /// reach the 15 min degrade-failure timeout and the 1 h restart-loop window
    /// inside a session. The flag is read here and only here, under `#if DEBUG`:
    /// a release build has no way to shorten the thresholds the user fixed.
    private static func resolvedConfiguration() -> CPUWatchdog.Configuration {
        #if DEBUG
        return CPUWatchdog.Configuration(
            timeScale: LaunchArguments.watchdogTimeScale(CommandLine.arguments)
        )
        #else
        return CPUWatchdog.Configuration()
        #endif
    }

    /// Says what the last run ended in, if it ended in a watchdog episode.
    ///
    /// The island carries it whenever there is something to carry. The modal is
    /// the fallback for the cases the island alone cannot cover: a quit, which
    /// the user has to be able to read after the pill has gone, and a process
    /// with no notification authorization, which had no other way to say it.
    func presentNoticeIfNeeded() {
        guard let notice = WatchdogLaunchNotice(event: marker.consume()) else { return }
        island.announceWatchdogNotice(didRelaunch: notice.didRelaunch)

        UserNotificationPoster.isAuthorized { isAuthorized in
            guard let alert = notice.alert(isNotificationAuthorized: isAuthorized) else { return }
            Task { @MainActor in
                Self.present(alert)
            }
        }
    }

    private static func present(_ alert: WatchdogLaunchNotice.Alert) {
        let panel = NSAlert()
        panel.messageText = alert.message
        panel.informativeText = alert.detail
        // An accessory app has no Dock icon to bring forward, so a modal it
        // never activates for opens behind whatever the user is looking at.
        NSApp.activate(ignoringOtherApps: true)
        panel.runModal()
    }
}
