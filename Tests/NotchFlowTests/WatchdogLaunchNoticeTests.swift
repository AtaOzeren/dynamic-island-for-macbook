import Foundation
import Testing
@testable import NotchFlow
@testable import NotchFlowProviders

/// The two decisions the launch after a watchdog episode makes.
///
/// Both are pure on purpose: the wiring in `NotchFlowApp` reads a file and puts
/// a modal on screen, neither of which a test can drive, so the judgement is
/// extracted to where it can be pinned — which episode the island announces,
/// and when the island alone is not enough to explain what happened.
@Suite("Watchdog launch notice")
struct WatchdogLaunchNoticeTests {
    // MARK: - Start gate

    @Test("names UI testing as the reason the watchdog stays off")
    func refusesUnderUITesting() {
        #expect(
            WatchdogStartRefusal.reason(isUITesting: true, isDisabledBySetting: false)
                == .uiTesting
        )
    }

    @Test("names the kill switch as the reason the watchdog stays off")
    func refusesWhenDisabled() {
        #expect(
            WatchdogStartRefusal.reason(isUITesting: false, isDisabledBySetting: true)
                == .disabledBySetting
        )
    }

    @Test("has no reason to refuse an ordinary launch")
    func allowsOrdinaryLaunch() {
        #expect(WatchdogStartRefusal.reason(isUITesting: false, isDisabledBySetting: false) == nil)
    }

    // MARK: - Notice

    @Test("an ordinary launch has no notice to make")
    func noMarkerMeansNoNotice() {
        #expect(WatchdogLaunchNotice(event: nil) == nil)
    }

    @Test("a relaunch marker announces a relaunch")
    func relaunchMarker() {
        #expect(WatchdogLaunchNotice(event: event(.relaunch))?.didRelaunch == true)
    }

    @Test("a quit marker announces a quit")
    func quitMarker() {
        #expect(WatchdogLaunchNotice(event: event(.quit))?.didRelaunch == false)
    }

    // MARK: - Alert fallback

    @Test("a relaunch the user was notified about needs no alert")
    func notifiedRelaunchIsSilent() {
        let notice = WatchdogLaunchNotice(event: event(.relaunch))
        #expect(notice?.alert(isNotificationAuthorized: true) == nil)
    }

    @Test("a relaunch nobody could be notified about raises an alert")
    func unnotifiedRelaunchAlerts() {
        let notice = WatchdogLaunchNotice(event: event(.relaunch))
        #expect(notice?.alert(isNotificationAuthorized: false) != nil)
    }

    @Test("a quit always raises an alert, notified or not")
    func quitAlwaysAlerts() {
        let notice = WatchdogLaunchNotice(event: event(.quit))
        #expect(notice?.alert(isNotificationAuthorized: true) != nil)
        #expect(notice?.alert(isNotificationAuthorized: false) != nil)
    }

    @Test("the alert names the saved report")
    func alertNamesTheReport() {
        let notice = WatchdogLaunchNotice(
            event: event(.quit, reportPath: "/tmp/notchflow-runaway.txt")
        )
        let alert = notice?.alert(isNotificationAuthorized: true)
        #expect(alert?.message.contains("/tmp/notchflow-runaway.txt") == true)
    }

    /// A report that could not be written must not leave the sentence hanging
    /// on an empty path — the alarm path carries on without a report by design.
    @Test("the alert still reads when no report was saved")
    func alertWithoutAReport() {
        let notice = WatchdogLaunchNotice(event: event(.quit, reportPath: nil))
        let alert = notice?.alert(isNotificationAuthorized: true)
        #expect(alert?.message.isEmpty == false)
        #expect(alert?.message.contains("Report: ") == true)
    }

    /// The session ledger and the activity model both start empty after a
    /// relaunch, so the alert has to say the agents are coming back rather than
    /// let an empty island imply the hooks broke.
    @Test("the alert explains that agent sessions return on their own")
    func alertMentionsAgentSessions() {
        let notice = WatchdogLaunchNotice(event: event(.relaunch))
        let alert = notice?.alert(isNotificationAuthorized: false)
        #expect(alert?.detail.isEmpty == false)
    }

    // MARK: - Helpers

    private func event(
        _ action: WatchdogEventMarker.Action,
        reportPath: String? = "/tmp/report.txt"
    ) -> WatchdogEventMarker.Event {
        WatchdogEventMarker.Event(
            action: action,
            reason: "sustainedHighCPU",
            at: Date(timeIntervalSince1970: 0),
            reportPath: reportPath
        )
    }
}
