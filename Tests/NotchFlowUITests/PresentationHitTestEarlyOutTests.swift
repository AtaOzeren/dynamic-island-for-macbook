import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// Pins the expanded hit test's answer for every class of pointer position, so
/// the cheap reject added in front of it can be proved to be a pure
/// optimisation rather than a behaviour change.
@Suite("PresentationController expanded hit test", .serialized)
@MainActor
struct PresentationHitTestEarlyOutTests {
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

    private static var panel: CGRect { panelFrame(for: notchedScreen, metrics: metrics) }

    /// Dead centre of the compact pill, which the expanded silhouette keeps as
    /// its neck.
    private static var onTheNeck: CGPoint {
        let hit = compactHitRect(for: notchedScreen, slotCount: 1, metrics: metrics)
        return CGPoint(x: hit.midX, y: hit.midY)
    }

    /// On the expanded card, below the neck.
    private static var onTheExpandedCard: CGPoint {
        CGPoint(x: panel.midX, y: panel.maxY - 45)
    }

    /// Inside the panel window and level with the island, but off to its side.
    private static var besideTheExpandedIsland: CGPoint {
        CGPoint(x: panel.minX + 1, y: panel.maxY - 10)
    }

    /// Directly below the island, far enough down that no arrangement of
    /// activities could ever reach it.
    private static var farBelowOnTheSameScreen: CGPoint {
        CGPoint(x: panel.midX, y: panel.maxY - metrics.maximumExpandedSize.height - 200)
    }

    private struct Harness {
        let manager: ActivityManager
        let controller: PresentationController
        let mouse: FakeMouse
        let probe: GeometryProbe
    }

    private static func makeHarness(
        showing activities: [StubHitTestActivity] = [
            StubHitTestActivity(
                identity: ActivityIdentity("timer.focus"),
                kind: .timer,
                priority: .normal
            )
        ]
    ) -> Harness {
        let manager = ActivityManager()
        let panel = NotchPanel(metrics: metrics, content: Color.clear)
        let mouse = FakeMouse()
        let probe = GeometryProbe()
        let controller = PresentationController(
            panel: panel,
            manager: manager,
            metrics: metrics,
            mouse: mouse,
            screen: { notchedScreen },
            disclosedInstances: {
                probe.disclosedInstanceReads += 1
                return []
            },
            registrationTimes: {
                probe.registrationTimeReads += 1
                return [:]
            }
        )
        controller.start()
        // The shared hover coordinator owns collapse in the real app; keeping it
        // off here isolates the hit test from the collapse it would otherwise
        // trigger the moment the pointer leaves.
        controller.automaticallyExpandsOnHover = false
        for activity in activities {
            manager.register(activity)
        }
        controller.expand()
        return Harness(manager: manager, controller: controller, mouse: mouse, probe: probe)
    }

    @Test("reports the pointer as on the island while it rests on the compact neck")
    func neckIsInside() {
        let harness = Self.makeHarness()

        harness.mouse.move(to: Self.onTheNeck)

        #expect(harness.controller.state == .expanded)
        #expect(harness.controller.isHovered)
    }

    @Test("reports the pointer as on the island while it rests on the expanded card")
    func expandedCardIsInside() {
        let harness = Self.makeHarness()

        harness.mouse.move(to: Self.onTheExpandedCard)

        #expect(harness.controller.state == .expanded)
        #expect(harness.controller.isHovered)
    }

    @Test("reports the pointer as off the island beside the expanded card")
    func besideTheCardIsOutside() {
        let harness = Self.makeHarness()
        harness.mouse.move(to: Self.onTheNeck)

        harness.mouse.move(to: Self.besideTheExpandedIsland)

        #expect(harness.controller.state == .expanded)
        #expect(harness.controller.isHovered == false)
    }

    @Test("reports the pointer as off the island far below it on the same screen")
    func farBelowIsOutside() {
        let harness = Self.makeHarness()
        harness.mouse.move(to: Self.onTheNeck)

        harness.mouse.move(to: Self.farBelowOnTheSameScreen)

        #expect(harness.controller.state == .expanded)
        #expect(harness.controller.isHovered == false)
    }

    /// The optimisation's whole point: a pointer nowhere near the island must
    /// not rebuild the expanded panel size. `registrationTimes` and
    /// `disclosedInstances` are read nowhere else in the controller, so a read
    /// count that stays put is proof the expensive branch was skipped.
    @Test("a pointer far below the island never builds the expanded size")
    func farBelowSkipsSizeConstruction() {
        let harness = Self.makeHarness()
        harness.mouse.move(to: Self.onTheNeck)
        let readsBefore = harness.probe.registrationTimeReads

        harness.mouse.move(to: Self.farBelowOnTheSameScreen)

        #expect(harness.probe.registrationTimeReads == readsBefore)
        #expect(harness.probe.disclosedInstanceReads == readsBefore)
    }

    /// The complement, which is what stops the reject from being a silent
    /// no-op: a pointer level with the island still pays for the real
    /// silhouette test.
    @Test("a pointer level with the island still builds the expanded size")
    func besideTheCardStillBuildsTheSize() {
        let harness = Self.makeHarness()
        harness.mouse.move(to: Self.onTheNeck)
        let readsBefore = harness.probe.registrationTimeReads

        harness.mouse.move(to: Self.besideTheExpandedIsland)

        #expect(harness.probe.registrationTimeReads > readsBefore)
    }

    /// Documents why the reject is a vertical band rather than the panel frame
    /// the plan first proposed. `expandedPanelSize` clamps its content to the
    /// panel's width budget and the surface then adds a flare on each side, so
    /// the drawn island is wider than the window that carries it as soon as the
    /// pill it grows from reaches that budget — and a `panelFrame` reject would
    /// cut hover off at the island's own edge.
    @Test("the expanded silhouette can be wider than the panel frame")
    func expandedSilhouetteCanExceedThePanelFrame() {
        let narrowPanel = PanelMetrics(
            maximumExpandedSize: CGSize(width: 240, height: 260),
            minimumBottomInset: 120
        )
        let notchSize = notchRect(for: Self.notchedScreen)?.size ?? narrowPanel.compactFallbackSize
        let geometry = ConnectedIslandGeometry(
            compactSize: balancedCompactPillSize(
                leadingSlotCount: 1,
                trailingSlotCount: 1,
                notchSize: notchSize
            ),
            expandedContentSize: expandedPanelSize(
                for: [
                    StubHitTestActivity(
                        identity: ActivityIdentity("timer.focus"),
                        kind: .timer,
                        priority: .normal
                    )
                ],
                notchSize: notchSize,
                panelMetrics: narrowPanel,
                topInset: notchSize.height
            )
        )
        let frame = panelFrame(for: Self.notchedScreen, metrics: narrowPanel)

        #expect(geometry.expandedSize.width > frame.width)
    }

    /// The height budget the reject's lower edge is cut at.
    private static var bandHeight: CGFloat {
        let notchSize = notchRect(for: notchedScreen)?.size ?? metrics.compactFallbackSize
        return max(metrics.maximumExpandedSize.height, notchSize.height)
    }

    /// Enough rows to push the expanded content past the height budget, so the
    /// island reaches as far down the screen as it ever can.
    private static var saturatingActivities: [StubHitTestActivity] {
        (0..<8).map {
            StubHitTestActivity(
                identity: ActivityIdentity("timer.focus.\($0)"),
                kind: .timer,
                priority: .normal
            )
        }
    }

    /// A pointer one hair inside the reject's lower edge still costs the full
    /// silhouette test. Without this the edge is free to move anywhere between
    /// the card and the far-below probe.
    @Test("a pointer just inside the band's lower edge still builds the expanded size")
    func justInsideTheBandStillBuildsTheSize() {
        let harness = Self.makeHarness()
        harness.mouse.move(to: Self.onTheNeck)
        let readsBefore = harness.probe.registrationTimeReads

        harness.mouse.move(
            to: CGPoint(x: Self.panel.midX, y: Self.panel.maxY - Self.bandHeight + 0.5)
        )

        #expect(harness.probe.registrationTimeReads > readsBefore)
    }

    /// The matching half a hair the other side of the same edge.
    @Test("a pointer just below the band's lower edge never builds the expanded size")
    func justBelowTheBandSkipsSizeConstruction() {
        let harness = Self.makeHarness()
        harness.mouse.move(to: Self.onTheNeck)
        let readsBefore = harness.probe.registrationTimeReads

        harness.mouse.move(
            to: CGPoint(x: Self.panel.midX, y: Self.panel.maxY - Self.bandHeight - 0.5)
        )

        #expect(harness.probe.registrationTimeReads == readsBefore)
        #expect(harness.controller.isHovered == false)
    }

    /// The band's upper edge is the panel's top, which is also the screen's, so
    /// a pointer above it is off the island by construction.
    @Test("a pointer above the panel's top edge never builds the expanded size")
    func abovePanelTopSkipsSizeConstruction() {
        let harness = Self.makeHarness()
        harness.mouse.move(to: Self.onTheNeck)
        let readsBefore = harness.probe.registrationTimeReads

        harness.mouse.move(to: CGPoint(x: Self.panel.midX, y: Self.panel.maxY + 1))

        #expect(harness.probe.registrationTimeReads == readsBefore)
        #expect(harness.controller.isHovered == false)
    }

    /// Proves the budget the reject cuts at is the one the island actually
    /// spends: with the content clamp saturated the silhouette is exactly as
    /// tall as the band, so any smaller band would cut hover off partway down a
    /// card the user can see.
    @Test("a saturated expanded island is exactly as tall as the reject's band")
    func saturatedIslandFillsTheBand() {
        let notchSize = notchRect(for: Self.notchedScreen)?.size ?? Self.metrics.compactFallbackSize
        let geometry = ConnectedIslandGeometry(
            compactSize: balancedCompactPillSize(
                leadingSlotCount: 1,
                trailingSlotCount: 1,
                notchSize: notchSize
            ),
            expandedContentSize: expandedPanelSize(
                for: Self.saturatingActivities,
                notchSize: notchSize,
                panelMetrics: Self.metrics,
                topInset: notchSize.height
            )
        )

        #expect(geometry.expandedSize.height == Self.bandHeight)
    }

    /// The end-to-end version of the same claim, through the controller: the
    /// deepest point a real arrangement can reach is still reported as on the
    /// island.
    @Test("the deepest point a saturated island reaches is still on the island")
    func deepestReachablePointIsInside() {
        let harness = Self.makeHarness(showing: Self.saturatingActivities)
        harness.mouse.move(to: Self.onTheNeck)

        harness.mouse.move(
            to: CGPoint(x: Self.panel.midX, y: Self.panel.maxY - Self.bandHeight + 1)
        )

        #expect(harness.controller.state == .expanded)
        #expect(harness.controller.isHovered)
    }

    /// The other half of the same argument: the panel's height is trimmed by
    /// the Dock inset on a short screen while the expanded content is only
    /// clamped by the size budget, so the island can also reach below the
    /// window's bottom edge.
    @Test("the panel frame is shorter than the island's reach on a short screen")
    func panelFrameCanBeShorterThanTheIslandReach() {
        let shortScreen = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 300),
            safeAreaInsets: ScreenSafeAreaInsets(top: 37),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 263, width: 656, height: 37),
            auxiliaryTopRightArea: CGRect(x: 856, y: 263, width: 656, height: 37),
            isBuiltIn: true
        )

        let frame = panelFrame(for: shortScreen, metrics: Self.metrics)

        #expect(frame.height < Self.metrics.maximumExpandedSize.height)
    }
}

@MainActor
private final class GeometryProbe {
    var disclosedInstanceReads = 0
    var registrationTimeReads = 0
}

@MainActor
private final class FakeMouse: MouseLocationObserving {
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

private struct StubHitTestActivity: Activity {
    let identity: ActivityIdentity
    let kind: ActivityKind
    let priority: ActivityPriority
}
