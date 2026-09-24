import AppKit
import KerNotchCore
import KerNotchProviders

/// The menu bar's timer shortcuts: one start item per preset, a stop item, and
/// the separator that sets them apart from the rest of the menu.
///
/// Follows the Activities pane's timer switch. A switched-off timer is not
/// observed, so a start item left in the menu would begin a countdown nothing
/// draws — hiding the items and stopping the timer is one gesture for that
/// reason.
@MainActor
final class TimerMenuControls: NSObject {
    private static let presets: [(minutes: Int, title: String)] = [
        (5, String(localized: "Start 5-Minute Timer")),
        (10, String(localized: "Start 10-Minute Timer")),
        (25, String(localized: "Start 25-Minute Timer")),
    ]

    private let timerProvider: TimerProvider

    /// In menu order, ready to be appended to a menu as they are.
    private(set) var items: [NSMenuItem] = []

    init(timerProvider: TimerProvider) {
        self.timerProvider = timerProvider
        super.init()
        items = makeItems()
    }

    func showControls() {
        for item in items {
            item.isHidden = false
        }
    }

    func hideControlsAndStopTimer() {
        for item in items {
            item.isHidden = true
        }
        timerProvider.handle(.stop)
    }

    private func makeItems() -> [NSMenuItem] {
        let startItems = Self.presets.map { preset in
            let item = NSMenuItem(
                title: preset.title,
                action: #selector(startTimer(_:)),
                keyEquivalent: ""
            )
            item.tag = preset.minutes
            item.target = self
            return item
        }

        let stopItem = NSMenuItem(
            title: String(localized: "Stop Timer"),
            action: #selector(stopTimer),
            keyEquivalent: ""
        )
        stopItem.target = self

        return startItems + [stopItem, .separator()]
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        timerProvider.handle(
            .start(.countdown(duration: .seconds(sender.tag * 60)))
        )
    }

    @objc private func stopTimer() {
        timerProvider.handle(.stop)
    }
}
