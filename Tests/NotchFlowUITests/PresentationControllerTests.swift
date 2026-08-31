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
        reduceMotion: Bool = false,
        motion: IslandMotion = .default
    ) -> Harness {
        let manager = ActivityManager()
        let panel = NotchPanel(metrics: metrics, content: Color.clear)
        let mouse = FakeMouseLocationObserver()
        let controller = PresentationController(
            panel: panel,
            manager: manager,
            metrics: metrics,
            mouse: mouse,
            motion: motion,
            reduceMotion: FakeReduceMotion(prefersReducedMotion: reduceMotion),
            screen: { screen }
        )
        controller.start()
        return Harness(manager: manager, panel: panel, controller: controller, mouse: mouse)
    }

    private static var insideTheHitRect: CGPoint {
        let hit = compactHitRect(for: notchedScreen, slotCount: 1, metrics: metrics)
        return CGPoint(x: hit.midX, y: hit.midY)
    }

    private static var overTheMenuBarBesideTheNotch: CGPoint {
        let hit = compactHitRect(for: notchedScreen, slotCount: 1, metrics: metrics)
        return CGPoint(x: hit.minX - 1, y: hit.midY)
    }

    private static func activity(_ name: String) -> StubPresentedActivity {
        StubPresentedActivity(
            identity: ActivityIdentity(name),
            kind: .timer,
            priority: .normal
        )
    }

    @Test("starts compact so the island never disappears while the app is running")
    func startsCompact() {
        let harness = Self.makeHarness()

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
    }

    @Test("orders the window in as compact when the first activity registers")
    func firstActivityOrdersIn() {
        let harness = Self.makeHarness()

        harness.manager.register(Self.activity("timer.focus"))

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
    }

    @Test("keeps the compact island visible when the last activity ends")
    func idleRemainsCompact() {
        let harness = Self.makeHarness()
        let activity = Self.activity("timer.focus")

        harness.manager.register(activity)
        #expect(harness.panel.isVisible)

        harness.manager.end(activity.identity)

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
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

    @Test("refuses to expand an empty compact island")
    func refusesToExpandWhileEmpty() {
        let harness = Self.makeHarness()

        harness.controller.expand()

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
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

    @Test("collapses from expanded when the last activity ends")
    func collapsesFromExpandedWhenEmpty() {
        let harness = Self.makeHarness()
        let activity = Self.activity("timer.focus")
        harness.manager.register(activity)
        harness.controller.expand()

        harness.manager.end(activity.identity)

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
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

        #expect(observed == [.expanded, .compact])
    }

    @Test("stops presenting once torn down")
    func stopUnsubscribes() {
        let harness = Self.makeHarness()

        harness.controller.stop()
        harness.manager.register(Self.activity("timer.focus"))

        #expect(harness.controller.state == .hidden)
        #expect(harness.panel.isVisible == false)
    }

    @Test("an empty compact island stays click-through away from the pill")
    func emptyCompactIslandIsClickThrough() {
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

    @Test("keeps the compact island interactive when the last activity ends")
    func endingLastActivityPreservesCompactIsland() {
        let harness = Self.makeHarness()
        let activity = Self.activity("timer.focus")
        harness.manager.register(activity)
        harness.mouse.move(to: Self.insideTheHitRect)

        harness.manager.end(activity.identity)

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
        #expect(harness.controller.isHovered)
        #expect(harness.panel.ignoresMouseEvents == false)
    }

    @Test("keeps an empty pill on screen without a configurable opt-out")
    func alwaysKeepsAnEmptyPillUp() {
        let harness = Self.makeHarness()

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
    }

    @Test("the compact pill survives the last activity ending")
    func compactPillSurvivesActivitiesEnding() {
        let harness = Self.makeHarness()
        let activity = Self.activity("timer.focus")
        harness.manager.register(activity)

        harness.manager.end(activity.identity)

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.isVisible)
    }

    @Test("hovering an empty pill never expands it")
    func hoveringAnEmptyPillDoesNotExpand() {
        let harness = Self.makeHarness(
            motion: IslandMotion(hoverExpansionDelay: 0.01)
        )

        harness.mouse.move(to: Self.insideTheHitRect)
        Self.runMainRunLoop(for: 0.05)

        #expect(harness.controller.state == .compact)
    }

    @Test("resting on the pill expands it after the hover delay")
    func hoverExpandsAfterTheDelay() {
        let harness = Self.makeHarness(
            motion: IslandMotion(hoverExpansionDelay: 0.01)
        )
        harness.manager.register(Self.activity("timer.focus"))

        harness.mouse.move(to: Self.insideTheHitRect)
        Self.runMainRunLoop(for: 0.05)

        #expect(harness.controller.state == .expanded)
    }

    @Test("crossing the pill without resting never expands it")
    func passingOverThePillDoesNotExpandIt() {
        let harness = Self.makeHarness(motion: IslandMotion(hoverExpansionDelay: 10))
        harness.manager.register(Self.activity("timer.focus"))

        harness.mouse.move(to: Self.insideTheHitRect)
        harness.mouse.move(to: Self.overTheMenuBarBesideTheNotch)
        Self.runMainRunLoop(for: 0.05)

        #expect(harness.controller.state == .compact)
    }

    /// Drains the main run loop long enough for a scheduled `Timer` with a
    /// shorter interval to have fired, without sleeping the test thread itself.
    private static func runMainRunLoop(for interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    @Test("keeps watching the pointer while the compact island is on screen")
    func observesTheMouseWhileCompact() {
        let harness = Self.makeHarness()
        #expect(harness.mouse.isObserving)
        let activity = Self.activity("timer.focus")

        harness.manager.register(activity)
        #expect(harness.mouse.isObserving)

        harness.manager.end(activity.identity)
        #expect(harness.mouse.isObserving)
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

    @Test("ending the last expanded activity animates back to compact")
    func endingLastActivityCollapses() {
        let harness = Self.makeHarness()
        let activity = Self.activity("timer.focus")
        harness.manager.register(activity)
        harness.controller.expand()

        harness.manager.end(activity.identity)

        #expect(harness.controller.state == .compact)
        #expect(harness.controller.transition == .spring(response: 0.35, dampingFraction: 0.8))
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
