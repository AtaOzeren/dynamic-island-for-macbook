import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

@Suite("TimerActivityView")
@MainActor
struct TimerActivityViewTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    private static func countdown(
        seconds: Int,
        after elapsed: TimeInterval = 0
    ) -> TimerActivity {
        TimerActivity
            .started(.countdown(duration: .seconds(seconds)), at: start)
            .advanced(to: start.addingTimeInterval(elapsed))
    }

    private static func stopwatch(after elapsed: TimeInterval) -> TimerActivity {
        TimerActivity
            .started(.stopwatch, at: start)
            .advanced(to: start.addingTimeInterval(elapsed))
    }

    private static func presentation(_ activity: TimerActivity) -> TimerPresentation {
        TimerPresentation(activity: activity)
    }

    @Test("draws a countdown's remaining time, not its elapsed time")
    func countdownShowsRemaining() {
        let view = Self.presentation(Self.countdown(seconds: 300, after: 1))

        #expect(view.time == "04:59")
        #expect(view.title == "Countdown")
    }

    @Test("draws a stopwatch's elapsed time")
    func stopwatchShowsElapsed() {
        #expect(Self.presentation(Self.stopwatch(after: 65)).time == "01:05")
        #expect(Self.presentation(Self.stopwatch(after: 65)).title == "Stopwatch")
    }

    /// The narrow "mm:ss" is what the pill is sized for, so the hour field has
    /// to stay absent until there are actually hours to show.
    @Test("adds the hour field only once there are hours")
    func hoursAppearOnlyWhenPresent() {
        #expect(Self.presentation(Self.stopwatch(after: 3599)).time == "59:59")
        #expect(Self.presentation(Self.stopwatch(after: 3600)).time == "1:00:00")
        #expect(Self.presentation(Self.stopwatch(after: 3723)).time == "1:02:03")
    }

    /// Sub-second precision would be a lie given the tick's leeway, so the face
    /// truncates rather than rounding up to a second that has not arrived.
    @Test("shows whole seconds and never a second early")
    func truncatesToWholeSeconds() {
        #expect(Self.presentation(Self.stopwatch(after: 1.9)).time == "00:01")
        #expect(Self.presentation(Self.countdown(seconds: 10, after: 0.4)).time == "00:09")
    }

    @Test("reads zero and announces the finish once expired")
    func expiredCountdownReadsZero() {
        let view = Self.presentation(Self.countdown(seconds: 10, after: 30))

        #expect(view.time == "00:00")
        #expect(view.title == "Time's up")
        #expect(view.isExpiring)
    }

    @Test("offers pause and stop while running")
    func runningOffersPauseAndStop() {
        let controls = Self.presentation(Self.countdown(seconds: 60)).controls

        #expect(controls.map(\.command) == [.pause, .stop])
        #expect(controls.first?.symbolName == "pause.fill")
    }

    @Test("offers resume and stop while paused")
    func pausedOffersResumeAndStop() {
        let paused = Self.countdown(seconds: 60).paused(at: Self.start.addingTimeInterval(10))
        let controls = Self.presentation(paused).controls

        #expect(controls.map(\.command) == [.resume, .stop])
        #expect(controls.first?.symbolName == "play.fill")
    }

    /// An expired countdown has nothing left to pause — acknowledging it is the
    /// only gesture left, so it is the only one drawn.
    @Test("offers only acknowledgement once expired")
    func expiredOffersOnlyDismiss() {
        let controls = Self.presentation(Self.countdown(seconds: 10, after: 30)).controls

        #expect(controls.map(\.command) == [.stop])
        #expect(controls.first?.accessibilityLabel == "Dismiss timer")
    }

    @Test("dispatches a control's command through the view")
    func viewDispatchesCommands() {
        var received: [TimerControlCommand] = []
        let view = TimerExpandedView(activity: Self.countdown(seconds: 60)) { command in
            received.append(command)
        }

        for control in view.presentation.controls {
            view.perform(control)
        }

        #expect(received == [.pause, .stop])
    }

    @Test("announces the time rather than the generic kind label")
    func compactSlotAnnouncesTheTime() {
        let slot = timerCompactSlot(for: Self.countdown(seconds: 300, after: 1))

        #expect(slot.symbolName == compactSymbolName(.timer))
        #expect(slot.accessibilityLabel == "Countdown, 04:59")
        #expect(slot.accessibilityLabel != compactAccessibilityLabel(.timer))
    }

    @Test("marks a paused timer in its accessibility label")
    func pausedAccessibilityLabel() {
        let paused = Self.countdown(seconds: 300, after: 1)
            .paused(at: Self.start.addingTimeInterval(1))

        #expect(Self.presentation(paused).accessibilityLabel == "Paused: Countdown, 04:59")
    }

    @Test("announces an expired timer as finished")
    func expiredAccessibilityLabel() {
        #expect(
            Self.presentation(Self.countdown(seconds: 10, after: 30)).accessibilityLabel
                == "Timer finished"
        )
    }

    /// The panel frame is allocated once and never resized, so the drawn size
    /// must stay inside it or be silently clipped.
    @Test("clamps its drawn size to the panel's allocated maximum")
    func sizeClampsToPanelMaximum() {
        let panelMetrics = PanelMetrics.default
        let size = timerExpandedSize(panelMetrics: panelMetrics)

        #expect(size.width <= panelMetrics.maximumExpandedSize.width)
        #expect(size.height <= panelMetrics.maximumExpandedSize.height)
    }
}
