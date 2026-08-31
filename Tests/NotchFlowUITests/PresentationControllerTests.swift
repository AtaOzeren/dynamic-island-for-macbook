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
        let mouse: FakeMouseLocationObserver
    }

    private static func makeHarness(
        screen: ScreenDescription? = notchedScreen,
        reduceMotion: Bool = false
    ) -> Harness {
        let manager = ActivityManager()
        let panel = NotchPanel(metrics: metrics, content: Color.clear)
        let mouse = FakeMouseLocationObserver()
        let controller = PresentationController(
            panel: panel,
            manager: manager,
            metrics: metrics,
            mouse: mouse,
            reduceMotion: FakeReduceMotion(prefersReducedMotion: reduceMotion),
            screen: { screen }
        )
        controller.start()
        return Harness(manager: manager, panel: panel, controller: controller, mouse: mouse)
    }

    private static var insideTheHitRect: CGPoint {
        let hit = compactHitRect(for: notchedScreen, metrics: metrics)
        return CGPoint(x: hit.midX, y: hit.midY)
    }

    private static var overTheMenuBarBesideTheNotch: CGPoint {
        let hit = compactHitRect(for: notchedScreen, metrics: metrics)
        return CGPoint(x: hit.minX - 1, y: hit.midY)
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

    @Test("stays click-through while hidden so nothing intercepts a menu-bar click")
    func hiddenIsClickThrough() {
        let harness = Self.makeHarness()

        #expect(harness.panel.ignoresMouseEvents)
        #expect(harness.controller.isHovered == false)
    }

    @Test("stays click-through in plain compact, where most of the frame draws nothing")
    func compactIsClickThrough() {
        let harness = Self.makeHarness()

        harness.manager.register(Self.activity("timer.focus"))

        #expect(harness.panel.ignoresMouseEvents)
    }

    @Test("accepts the mouse while the pointer is over the compact pill")
    func hoverAcceptsTheMouse() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))

        harness.mouse.move(to: Self.insideTheHitRect)

        #expect(harness.controller.isHovered)
        #expect(harness.panel.ignoresMouseEvents == false)
    }

    @Test("returns to click-through when the pointer leaves the pill without clicking")
    func leavingRevertsToClickThrough() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))
        harness.mouse.move(to: Self.insideTheHitRect)

        harness.mouse.move(to: Self.overTheMenuBarBesideTheNotch)

        #expect(harness.controller.isHovered == false)
        #expect(harness.panel.ignoresMouseEvents)
    }

    @Test("leaves a menu-bar click beside the notch untouched while compact")
    func menuBarBesideTheNotchStaysClickable() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))

        harness.mouse.move(to: Self.overTheMenuBarBesideTheNotch)

        #expect(harness.panel.ignoresMouseEvents)
    }

    @Test("accepts the mouse across the whole panel while expanded")
    func expandedAcceptsTheMouse() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))
        harness.controller.expand()

        #expect(harness.panel.ignoresMouseEvents == false)
    }

    @Test("keeps accepting the mouse when the pointer leaves an expanded panel, so click-outside can collapse it")
    func expandedIgnoresHover() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))
        harness.controller.expand()

        harness.mouse.move(to: Self.overTheMenuBarBesideTheNotch)

        #expect(harness.controller.state == .expanded)
        #expect(harness.panel.ignoresMouseEvents == false)
    }

    @Test("reverts to click-through when collapsing away from the pointer")
    func collapsingRevertsToClickThrough() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))
        harness.controller.expand()
        harness.mouse.move(to: Self.overTheMenuBarBesideTheNotch)

        harness.controller.collapse()

        #expect(harness.panel.ignoresMouseEvents)
    }

    @Test("stays accepting the mouse when collapsing under a pointer still on the pill")
    func collapsingUnderThePointerKeepsHover() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))
        harness.mouse.move(to: Self.insideTheHitRect)
        harness.controller.expand()

        harness.controller.collapse()

        #expect(harness.controller.isHovered)
        #expect(harness.panel.ignoresMouseEvents == false)
    }

    @Test("drops hover and click-through the moment the last activity ends")
    func hidingClearsHover() {
        let harness = Self.makeHarness()
        let activity = Self.activity("timer.focus")
        harness.manager.register(activity)
        harness.mouse.move(to: Self.insideTheHitRect)

        harness.manager.end(activity.identity)

        #expect(harness.controller.isHovered == false)
        #expect(harness.panel.ignoresMouseEvents)
    }

    @Test("watches the pointer only while the window is on screen")
    func observesTheMouseOnlyWhileVisible() {
        let harness = Self.makeHarness()
        #expect(harness.mouse.isObserving == false)
        let activity = Self.activity("timer.focus")

        harness.manager.register(activity)
        #expect(harness.mouse.isObserving)

        harness.manager.end(activity.identity)
        #expect(harness.mouse.isObserving == false)
    }

    @Test("stops watching the pointer once torn down")
    func stopUnsubscribesTheMouse() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))

        harness.controller.stop()

        #expect(harness.mouse.isObserving == false)
        #expect(harness.panel.ignoresMouseEvents)
    }

    @Test("publishes every hover change exactly once")
    func publishesHoverChanges() {
        let harness = Self.makeHarness()
        var observed: [Bool] = []
        harness.controller.onHoverChange = { observed.append($0) }
        harness.manager.register(Self.activity("timer.focus"))

        harness.mouse.move(to: Self.insideTheHitRect)
        harness.mouse.move(to: Self.insideTheHitRect)
        harness.mouse.move(to: Self.overTheMenuBarBesideTheNotch)
        harness.mouse.move(to: Self.overTheMenuBarBesideTheNotch)

        #expect(observed == [true, false])
    }

    @Test("starts with nothing to animate")
    func startsUnanimated() {
        let harness = Self.makeHarness()

        #expect(harness.controller.transition == .none)
        #expect(harness.controller.peek == .none)
    }

    @Test("ordering in on the first activity animates nothing")
    func orderingInIsUnanimated() {
        let harness = Self.makeHarness()

        harness.manager.register(Self.activity("timer.focus"))

        #expect(harness.controller.transition == .none)
    }

    @Test("ordering out on the last activity animates nothing")
    func orderingOutIsUnanimated() {
        let harness = Self.makeHarness()
        let activity = Self.activity("timer.focus")
        harness.manager.register(activity)
        harness.controller.expand()

        harness.manager.end(activity.identity)

        #expect(harness.controller.state == .hidden)
        #expect(harness.controller.transition == .none)
        #expect(harness.controller.peek == .none)
    }

    @Test("expanding and collapsing run the spring")
    func expandAndCollapseSpring() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))

        harness.controller.expand()
        #expect(harness.controller.transition == .spring(response: 0.35, dampingFraction: 0.8))

        harness.controller.collapse()
        #expect(harness.controller.transition == .spring(response: 0.35, dampingFraction: 0.8))
    }

    @Test("hovering the pill runs the peek")
    func hoverPeeks() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))

        harness.mouse.move(to: Self.insideTheHitRect)

        #expect(harness.controller.peek == .easeOut(duration: 0.15))
    }

    @Test("Reduce Motion cross-fades every transition instead of springing")
    func reduceMotionCrossFades() {
        let harness = Self.makeHarness(reduceMotion: true)
        harness.manager.register(Self.activity("timer.focus"))

        harness.mouse.move(to: Self.insideTheHitRect)
        #expect(harness.controller.peek.movesGeometry == false)

        harness.controller.expand()
        #expect(harness.controller.transition.movesGeometry == false)
        #expect(harness.controller.transition != .none)
    }

    @Test("the curve is settled before the state change is published")
    func curveIsSettledBeforePublishing() {
        let harness = Self.makeHarness()
        harness.manager.register(Self.activity("timer.focus"))
        var observed: [IslandAnimationCurve] = []
        harness.controller.onStateChange = { [weak controller = harness.controller] _ in
            guard let controller else { return }
            observed.append(controller.transition)
        }

        harness.controller.expand()

        #expect(observed == [.spring(response: 0.35, dampingFraction: 0.8)])
    }
}

@MainActor
private struct FakeReduceMotion: ReduceMotionQuerying {
    let prefersReducedMotion: Bool
}

@MainActor
private final class FakeMouseLocationObserver: MouseLocationObserving {
    private var observer: MouseLocationObserver?

    var isObserving: Bool { observer != nil }

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

private struct StubPresentedActivity: Activity {
    let identity: ActivityIdentity
    let kind: ActivityKind
    let priority: ActivityPriority
}
