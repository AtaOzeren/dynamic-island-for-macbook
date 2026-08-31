import AppKit
import CoreGraphics
import SwiftUI
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

@Suite("Presentation regressions", .serialized)
@MainActor
struct PresentationRegressionTests {
    private static let screen = ScreenDescription(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: ScreenSafeAreaInsets(top: 37),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 656, height: 37),
        auxiliaryTopRightArea: CGRect(x: 856, y: 945, width: 656, height: 37),
        isBuiltIn: true
    )

    @Test("the default hover dwell is exactly 250 milliseconds")
    func defaultHoverDwell() {
        #expect(IslandMotion.default.hoverExpansionDelay == 0.25)
    }

    @Test("an empty island collapses before accepting mouse events")
    func emptyIslandCollapses() {
        let harness = makeHarness(screen: Self.screen)
        let activity = RegressionActivity("timer.focus")
        harness.manager.register(activity)
        harness.controller.expand()

        harness.manager.end(activity.identity)

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.ignoresMouseEvents)
    }

    @Test("collapse recalculates stale hover after pointer left while expanded")
    func collapseRecalculatesHover() {
        let harness = makeHarness(screen: Self.screen)
        harness.manager.register(RegressionActivity("timer.focus"))
        let hitRect = compactHitRect(for: Self.screen, slotCount: 1)
        harness.mouse.move(to: CGPoint(x: hitRect.midX, y: hitRect.midY))
        harness.controller.expand()
        harness.mouse.move(to: CGPoint(x: Self.screen.frame.minX, y: Self.screen.frame.minY))

        harness.controller.collapse()

        #expect(!harness.controller.isHovered)
        #expect(harness.panel.ignoresMouseEvents)
    }

    @Test("presentation recovers when a selected screen becomes available")
    func recoversWhenScreenAppears() {
        let mutableScreen = RegressionScreen(nil)
        let harness = makeHarness(screen: mutableScreen)
        harness.manager.register(RegressionActivity("timer.focus"))
        #expect(harness.controller.state == .hidden)

        mutableScreen.value = Self.screen
        harness.controller.screenConfigurationDidChange()

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
    }

    @Test("presentation suspends while no screen exists and returns compact")
    func suspendsWithoutScreen() {
        let mutableScreen = RegressionScreen(Self.screen)
        let harness = makeHarness(screen: mutableScreen)
        harness.manager.register(RegressionActivity("timer.focus"))
        harness.controller.expand()

        mutableScreen.value = nil
        harness.controller.screenConfigurationDidChange()

        #expect(harness.controller.state == .hidden)
        #expect(!harness.panel.isVisible)

        mutableScreen.value = Self.screen
        harness.controller.screenConfigurationDidChange()

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
    }

    @Test("system sleep suspends presentation until screen reconciliation")
    func sleepSuspendsPresentation() {
        let harness = makeHarness(screen: Self.screen)
        harness.manager.register(RegressionActivity("timer.focus"))
        harness.controller.expand()

        harness.controller.suspend()

        #expect(harness.controller.state == .hidden)
        #expect(!harness.panel.isVisible)

        harness.controller.screenConfigurationDidChange()

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
    }

    @Test("explicit interaction enables key focus until collapse")
    func explicitInteractionControlsFocus() {
        let harness = makeHarness(screen: Self.screen)
        harness.manager.register(RegressionActivity("timer.focus"))
        harness.controller.expand()
        #expect(!harness.panel.canBecomeKey)

        harness.controller.beginInteractiveMode()
        #expect(harness.panel.canBecomeKey)

        harness.controller.collapse()
        #expect(!harness.panel.canBecomeKey)
    }

    private func makeHarness(screen: ScreenDescription?) -> RegressionHarness {
        makeHarness(screen: RegressionScreen(screen))
    }

    private func makeHarness(screen: RegressionScreen) -> RegressionHarness {
        let manager = ActivityManager()
        let panel = NotchPanel(content: Color.clear)
        let mouse = RegressionMouseObserver()
        let controller = PresentationController(
            panel: panel,
            manager: manager,
            mouse: mouse,
            screen: { screen.value }
        )
        controller.start()
        return RegressionHarness(manager: manager, panel: panel, controller: controller, mouse: mouse)
    }
}

@MainActor
private struct RegressionHarness {
    let manager: ActivityManager
    let panel: NotchPanel
    let controller: PresentationController
    let mouse: RegressionMouseObserver
}

private struct RegressionActivity: Activity {
    let identity: ActivityIdentity
    let kind = ActivityKind.timer
    let priority = ActivityPriority.normal

    init(_ identity: String) {
        self.identity = ActivityIdentity(identity)
    }
}

private final class RegressionScreen {
    var value: ScreenDescription?

    init(_ value: ScreenDescription?) {
        self.value = value
    }
}

@MainActor
private final class RegressionMouseObserver: MouseLocationObserving {
    private var observer: MouseLocationObserver?

    func startObserving(_ observer: @escaping MouseLocationObserver) {
        self.observer = observer
    }

    func stopObserving() {
        observer = nil
    }

    func move(to location: CGPoint) {
        observer?(location)
    }
}
