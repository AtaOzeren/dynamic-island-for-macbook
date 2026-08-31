import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// The screen an island is on can change while the island is up — a display
/// unplugged, a resolution changed, a wake, a display-target preference edited.
/// `show()` resolves the screen once, on order-in, so without
/// `repositionOnCurrentScreen()` the panel keeps coordinates that may belong to
/// a screen that no longer exists.
@Suite("PresentationController repositioning", .serialized)
@MainActor
struct PresentationControllerRepositionTests {
    private static let metrics = PanelMetrics(
        maximumExpandedSize: CGSize(width: 640, height: 260),
        minimumBottomInset: 120
    )

    private static let builtInNotchedScreen = ScreenDescription(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: ScreenSafeAreaInsets(top: 37),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 656, height: 37),
        auxiliaryTopRightArea: CGRect(x: 856, y: 945, width: 656, height: 37),
        isBuiltIn: true
    )

    /// The external 2560×1440 this machine actually runs as primary. No notch,
    /// so it also exercises the degraded mode in `docs/03-display-and-notch.md`.
    private static let externalScreenWithoutNotch = ScreenDescription(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        safeAreaInsets: ScreenSafeAreaInsets(top: 0),
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil,
        isBuiltIn: false
    )

    private final class MutableScreen {
        var current: ScreenDescription?

        init(_ screen: ScreenDescription?) {
            current = screen
        }
    }

    private struct Harness {
        let manager: ActivityManager
        let panel: NotchPanel
        let controller: PresentationController
        let screen: MutableScreen
        let mouse: RepositionTestMouse
    }

    private static func makeHarness(startingOn screen: ScreenDescription?) -> Harness {
        let manager = ActivityManager()
        let panel = NotchPanel(metrics: metrics, content: Color.clear)
        let mutableScreen = MutableScreen(screen)
        let mouse = RepositionTestMouse()
        let controller = PresentationController(
            panel: panel,
            manager: manager,
            metrics: metrics,
            mouse: mouse,
            reduceMotion: RepositionTestReduceMotion(),
            screen: { mutableScreen.current }
        )
        controller.start()
        return Harness(
            manager: manager,
            panel: panel,
            controller: controller,
            screen: mutableScreen,
            mouse: mouse
        )
    }

    private static func activity(_ name: String) -> RepositionTestActivity {
        RepositionTestActivity(
            identity: ActivityIdentity(name),
            kind: .timer,
            priority: .normal
        )
    }

    @Test("moves a visible panel onto the newly resolved screen")
    func repositionsVisiblePanel() {
        let harness = Self.makeHarness(startingOn: Self.builtInNotchedScreen)
        harness.manager.register(Self.activity("timer.focus"))
        #expect(
            harness.panel.frame
                == panelFrame(for: Self.builtInNotchedScreen, metrics: Self.metrics)
        )

        harness.screen.current = Self.externalScreenWithoutNotch
        let didReposition = harness.controller.repositionOnCurrentScreen()

        #expect(didReposition)
        #expect(
            harness.panel.frame
                == panelFrame(for: Self.externalScreenWithoutNotch, metrics: Self.metrics)
        )
    }

    @Test("leaves an expanded panel expanded while moving it")
    func repositioningDoesNotChangeState() {
        let harness = Self.makeHarness(startingOn: Self.builtInNotchedScreen)
        harness.manager.register(Self.activity("timer.focus"))
        harness.controller.expand()
        #expect(harness.controller.state == .expanded)

        harness.screen.current = Self.externalScreenWithoutNotch
        harness.controller.repositionOnCurrentScreen()

        #expect(harness.controller.state == .expanded)
        #expect(harness.panel.isVisible)
    }

    @Test("does nothing while hidden, since the next order-in resolves anyway")
    func ignoresRepositionWhileHidden() {
        let harness = Self.makeHarness(startingOn: Self.builtInNotchedScreen)
        let frameBefore = harness.panel.frame

        harness.screen.current = Self.externalScreenWithoutNotch
        let didReposition = harness.controller.repositionOnCurrentScreen()

        #expect(!didReposition)
        #expect(harness.controller.state == .hidden)
        #expect(harness.panel.frame == frameBefore)
    }

    @Test("leaves the panel where it was when every screen disappears")
    func survivesAnEmptyScreenSet() {
        let harness = Self.makeHarness(startingOn: Self.builtInNotchedScreen)
        harness.manager.register(Self.activity("timer.focus"))
        let frameBefore = harness.panel.frame

        harness.screen.current = nil
        let didReposition = harness.controller.repositionOnCurrentScreen()

        #expect(!didReposition)
        #expect(harness.panel.frame == frameBefore)
    }

    @Test("re-resolves the hit rect so the pill is clickable on the new screen")
    func repositionsTheHitRect() {
        let harness = Self.makeHarness(startingOn: Self.builtInNotchedScreen)
        harness.manager.register(Self.activity("timer.focus"))

        harness.screen.current = Self.externalScreenWithoutNotch
        harness.controller.repositionOnCurrentScreen()

        let hit = compactHitRect(for: Self.externalScreenWithoutNotch, metrics: Self.metrics)
        harness.mouse.move(to: CGPoint(x: hit.midX, y: hit.midY))

        #expect(harness.controller.isHovered)
    }
}

private struct RepositionTestActivity: Activity {
    let identity: ActivityIdentity
    let kind: ActivityKind
    let priority: ActivityPriority
}

@MainActor
private struct RepositionTestReduceMotion: ReduceMotionQuerying {
    let prefersReducedMotion = false
}

@MainActor
private final class RepositionTestMouse: MouseLocationObserving {
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
