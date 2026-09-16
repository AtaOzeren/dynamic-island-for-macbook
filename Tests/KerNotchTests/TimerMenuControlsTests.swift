import AppKit
import Foundation
import Testing

@testable import KerNotch
@testable import KerNotchCore
@testable import KerNotchProviders

/// The menu bar's timer shortcuts, and how they follow the Activities pane's
/// timer switch.
@Suite("Timer menu controls")
@MainActor
struct TimerMenuControlsTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    private static func makeControls() -> (TimerMenuControls, TimerProvider) {
        let provider = TimerProvider(now: { start })
        return (TimerMenuControls(timerProvider: provider), provider)
    }

    private static func press(_ item: NSMenuItem) {
        guard let action = item.action else {
            Issue.record("\(item.title) has no action")
            return
        }
        _ = (item.target as? NSObject)?.perform(action, with: item)
    }

    @Test("offers three presets, a stop item and a closing separator")
    func itemsAreInMenuOrder() {
        let (controls, _) = Self.makeControls()

        #expect(controls.items.count == 5)
        #expect(controls.items.prefix(3).map(\.tag) == [5, 10, 25])
        #expect(controls.items[3].isSeparatorItem == false)
        #expect(controls.items[4].isSeparatorItem)
        #expect(controls.items.allSatisfy { $0.isHidden == false })
    }

    @Test("a preset starts a countdown of that many minutes")
    func presetStartsCountdown() {
        let (controls, provider) = Self.makeControls()

        Self.press(controls.items[1])

        #expect(provider.currentActivity?.mode == .countdown(duration: .seconds(600)))
    }

    @Test("the stop item clears a running timer")
    func stopItemClearsTimer() {
        let (controls, provider) = Self.makeControls()
        Self.press(controls.items[0])

        Self.press(controls.items[3])

        #expect(provider.currentActivity == nil)
    }

    @Test("switching the timer off hides every item, separator included")
    func hidingCoversEveryItem() {
        let (controls, _) = Self.makeControls()

        controls.hideControlsAndStopTimer()

        #expect(controls.items.allSatisfy { $0.isHidden })
    }

    /// A timer left running while its activity is switched off would come back
    /// the moment the switch is turned on again, counting from a start the user
    /// has long forgotten.
    @Test("switching the timer off stops a timer already running")
    func hidingStopsRunningTimer() {
        let (controls, provider) = Self.makeControls()
        Self.press(controls.items[2])

        controls.hideControlsAndStopTimer()

        #expect(provider.currentActivity == nil)
    }

    @Test("switching the timer back on shows the items again")
    func showingRestoresItems() {
        let (controls, _) = Self.makeControls()
        controls.hideControlsAndStopTimer()

        controls.showControls()

        #expect(controls.items.allSatisfy { $0.isHidden == false })
    }
}
