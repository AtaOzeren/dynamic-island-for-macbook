import Foundation
import KerNotchProviders

/// Why the watchdog is not running on this launch.
///
/// Separate from `CPUWatchdogSupervisor.shouldStart` because the log line has to
/// say which of the two reasons applied: "the watchdog is off" without the cause
/// sends a support conversation looking for a crash that never happened.
enum WatchdogStartRefusal: Equatable {
    case uiTesting
    case disabledBySetting

    static func reason(isUITesting: Bool, isDisabledBySetting: Bool) -> Self? {
        guard CPUWatchdogSupervisor.shouldStart(
            isUITesting: isUITesting,
            isDisabledBySetting: isDisabledBySetting
        ) == false else {
            return nil
        }
        return isUITesting ? .uiTesting : .disabledBySetting
    }

    var logDescription: String {
        switch self {
        case .uiTesting:
            return "UI testing"
        case .disabledBySetting:
            return "cpuWatchdogDisabled is set"
        }
    }
}

/// What the launch after a watchdog episode owes the user.
///
/// The island announcement is the whole story when a notification already
/// carried it; when it did not — a quit, or a process the user never authorized
/// notifications for — the episode also gets a modal, because a pill that has
/// come and gone is not something the user can go back and read.
struct WatchdogLaunchNotice {
    struct Alert: Equatable {
        let message: String
        let detail: String
    }

    let didRelaunch: Bool

    private let reportPath: String?

    init?(event: WatchdogEventMarker.Event?) {
        guard let event else { return nil }
        didRelaunch = event.action == .relaunch
        reportPath = event.reportPath
    }

    /// The modal, or `nil` when the island and the notification between them
    /// have already said it.
    func alert(isNotificationAuthorized: Bool) -> Alert? {
        guard didRelaunch == false || isNotificationAuthorized == false else { return nil }
        return Alert(message: message, detail: Self.agentSessionsDetail)
    }

    private var message: String {
        let path = reportPath ?? Self.missingReportPlaceholder
        guard didRelaunch else {
            return String(
                format: String(
                    localized: "Last time, KerNotch quit itself because CPU stayed high after three restarts. Report: %@",
                    comment: "Post-launch alert after the watchdog quit the app."
                ),
                path
            )
        }
        return String(
            format: String(
                localized: "KerNotch restarted itself after sustained high CPU use. Report: %@",
                comment: "Post-launch alert after the watchdog restarted the app."
            ),
            path
        )
    }

    /// Both the session ledger and the activity model start empty in a fresh
    /// process, so an island with no agents on it is the expected state rather
    /// than a broken hook — which is what the user would otherwise conclude.
    private static var agentSessionsDetail: String {
        String(
            localized: "Agent sessions are not carried across a restart. Each one reappears on its next event.",
            comment: "Post-launch alert detail: why the island shows no agent sessions yet."
        )
    }

    private static var missingReportPlaceholder: String {
        String(
            localized: "not saved",
            comment: "Stands in for the report path when the diagnostics report could not be written."
        )
    }
}
