import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import NotchFlowCore
@testable import NotchFlowUI

@Suite("PresentationController", .serialized)
@MainActor
struct PresentationControllerTests {
    private static let metrics = PanelMetrics(
        maximumExpandedSize: CGSize(width: 640, height: 260),
        minimumBottomInset: 120
    )

    private static let notchedScreen = ScreenDescription(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: ScreenSafeAreaInsets(top: 37),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 656, height: 37),
        auxiliaryTopRightArea: CGRect(x: 856, y: 945, width: 656, height: 37),
        isBuiltIn: true
    )

    private struct Harness {
        let manager: ActivityManager
        let panel: NotchPanel
        let controller: PresentationController
    }

    private static func makeHarness(screen: ScreenDescription? = notchedScreen) -> Harness {
        let manager = ActivityManager()
        let panel = NotchPanel(metrics: metrics, content: Color.clear)
        let controller = PresentationController(
            panel: panel,
            manager: manager,
            screen: { screen }
        )
        controller.start()
        return Harness(manager: manager, panel: panel, controller: controller)
    }

    private static func activity(_ name: String) -> StubPresentedActivity {
        StubPresentedActivity(
            identity: ActivityIdentity(name),
            kind: .timer,
            priority: .normal
        )
    }

    @Test("starts hidden with the window off screen")
    func startsHidden() {
        let harness = Self.makeHarness()

        #expect(harness.controller.state == .hidden)
        #expect(harness.panel.isVisible == false)
    }

    @Test("orders the window in as compact when the first activity registers")
    func firstActivityOrdersIn() {
        let harness = Self.makeHarness()

        harness.manager.register(Self.activity("timer.focus"))

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
    }

    @Test("orders the window out when the last activity ends")
    func idleOrdersOut() {
        let harness = Self.makeHarness()
        let activity = Self.activity("timer.focus")

        harness.manager.register(activity)
        #expect(harness.panel.isVisible)

        harness.manager.end(activity.identity)

        #expect(harness.controller.state == .hidden)
        #expect(harness.panel.isVisible == false)
    }

    @Test("stays compact while any activity remains")
    func staysCompactWhileActivitiesRemain() {
        let harness = Self.makeHarness()
        let first = Self.activity("timer.focus")
        let second = Self.activity("timer.break")

        harness.manager.register(first)
        harness.manager.register(second)
        harness.manager.end(first.identity)

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
    }

    @Test("positions the window under the notch before ordering it in")
    func repositionsBeforeOrderingIn() {
        let harness = Self.makeHarness()

        harness.manager.register(Self.activity("timer.focus"))

        #expect(harness.panel.frame == panelFrame(for: Self.notchedScreen, metrics: Self.metrics))
    }

    @Test("stays hidden when no screen is available to present on")
    func staysHiddenWithoutAScreen() {
        let harness = Self.makeHarness(screen: nil)

        harness.manager.register(Self.activity("timer.focus"))

        #expect(harness.controller.state == .hidden)
        #expect(harness.panel.isVisible == false)
    }

    @Test("expands from compact")
    func expandsFromCompact() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))

        harness.controller.expand()

        #expect(harness.controller.state == .expanded)
        #expect(harness.panel.isVisible)
    }

    @Test("refuses to expand while hidden, since no animation may start off screen")
    func refusesToExpandWhileHidden() {
        let harness = Self.makeHarness()

        harness.controller.expand()

        #expect(harness.controller.state == .hidden)
        #expect(harness.panel.isVisible == false)
    }

    @Test("collapses from expanded back to compact without ordering out")
    func collapsesToCompact() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))
        harness.controller.expand()

        harness.controller.collapse()

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
    }

    @Test("hides directly from expanded when the last activity ends")
    func hidesFromExpanded() {
        let harness = Self.makeHarness()
        let activity = Self.activity("timer.focus")
        harness.manager.register(activity)
        harness.controller.expand()

        harness.manager.end(activity.identity)

        #expect(harness.controller.state == .hidden)
        #expect(harness.panel.isVisible == false)
    }

    @Test("publishes every state change exactly once")
    func publishesStateChanges() {
        let harness = Self.makeHarness()
        var observed: [PresentationState] = []
        harness.controller.onStateChange = { observed.append($0) }
        let activity = Self.activity("timer.focus")

        harness.manager.register(activity)
        harness.manager.register(Self.activity("timer.break"))
        harness.controller.expand()
        harness.controller.expand()
        harness.controller.collapse()
        harness.manager.end(activity.identity)
        harness.manager.end(ActivityIdentity("timer.break"))

        #expect(observed == [.compact, .expanded, .compact, .hidden])
    }

    @Test("stops presenting once torn down")
    func stopUnsubscribes() {
        let harness = Self.makeHarness()

        harness.controller.stop()
        harness.manager.register(Self.activity("timer.focus"))

        #expect(harness.controller.state == .hidden)
        #expect(harness.panel.isVisible == false)
    }
}

private struct StubPresentedActivity: Activity {
    let identity: ActivityIdentity
    let kind: ActivityKind
    let priority: ActivityPriority
}
