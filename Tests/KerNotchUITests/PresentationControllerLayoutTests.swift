import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// Changing the island size while KerNotch runs: the window takes the new
/// budget, and hover follows the silhouette that is now drawn.
@Suite("PresentationController island layout", .serialized)
@MainActor
struct PresentationControllerLayoutTests {
    private static let notchedScreen = ScreenDescription(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: ScreenSafeAreaInsets(top: 37),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 656, height: 37),
        auxiliaryTopRightArea: CGRect(x: 856, y: 945, width: 656, height: 37),
        isBuiltIn: true
    )

    private static var notchSize: CGSize {
        notchRect(for: notchedScreen)?.size ?? PanelMetrics.default.compactFallbackSize
    }

    /// Level with the top of the card, horizontally past the minimalist
    /// island's edge but inside the large island's.
    private static var betweenTheTwoEdges: CGPoint {
        let minimalistHalfWidth =
            expandedPanelWidth(notchSize: notchSize, panelMetrics: IslandLayout.minimalist.panel) / 2
        let largeHalfWidth =
            expandedPanelWidth(notchSize: notchSize, panelMetrics: IslandLayout.large.panel) / 2
        let panel = panelFrame(for: notchedScreen, metrics: IslandLayout.minimalist.panel)
        return CGPoint(
            x: panel.midX + (minimalistHalfWidth + largeHalfWidth) / 2,
            y: panel.maxY - notchSize.height - 10
        )
    }

    /// Centred under the notch, just below where the minimalist card ends but
    /// above where the large card — taller rows, larger insets — does.
    private static var belowTheMinimalistCard: CGPoint {
        let panel = panelFrame(for: notchedScreen, metrics: IslandLayout.minimalist.panel)
        let minimalistHeight = cardHeight(IslandLayout.minimalist)
        let largeHeight = cardHeight(IslandLayout.large)
        return CGPoint(
            x: panel.midX,
            y: panel.maxY - notchSize.height - (minimalistHeight + largeHeight) / 2
        )
    }

    private static func cardHeight(_ layout: IslandLayout) -> CGFloat {
        expandedPanelSize(
            for: [ChargingActivity(state: .charging, level: BatteryLevel(fraction: 0.5))],
            notchSize: notchSize,
            metrics: layout.items,
            panelMetrics: layout.panel,
            topInset: notchSize.height
        ).height
    }

    private struct Harness {
        let manager: ActivityManager
        let panel: NotchPanel
        let controller: PresentationController
        let mouse: LayoutFakeMouse
    }

    private static func makeHarness() -> Harness {
        let manager = ActivityManager()
        let panel = NotchPanel(metrics: IslandLayout.minimalist.panel, content: Color.clear)
        let mouse = LayoutFakeMouse()
        let controller = PresentationController(
            panel: panel,
            manager: manager,
            layout: .minimalist,
            mouse: mouse,
            screen: { notchedScreen }
        )
        controller.automaticallyExpandsOnHover = false
        return Harness(manager: manager, panel: panel, controller: controller, mouse: mouse)
    }

    private static func expandedHarness() -> Harness {
        let harness = makeHarness()
        harness.controller.start()
        harness.manager.register(ChargingActivity(state: .charging, level: BatteryLevel(fraction: 0.5)))
        harness.controller.expand()
        return harness
    }

    /// The premise the next test relies on: at minimalist size this point is
    /// beside the island, not on it.
    @Test("a pointer past the minimalist island's edge is off it")
    func pointerPastMinimalistEdgeIsOutside() {
        let harness = Self.expandedHarness()

        harness.mouse.move(to: Self.betweenTheTwoEdges)

        #expect(harness.controller.state == .expanded)
        #expect(harness.controller.isHovered == false)
    }

    /// Hover has to be judged against the island that is drawn. Left on the
    /// minimalist silhouette, the large island would collapse under a pointer
    /// resting on its own outer edge.
    @Test("switching to large puts a pointer resting on the wider edge on the island")
    func largeLayoutWidensHover() {
        let harness = Self.expandedHarness()
        harness.mouse.move(to: Self.betweenTheTwoEdges)

        harness.controller.applyLayout(.large)

        #expect(harness.controller.state == .expanded)
        #expect(harness.controller.isHovered)
    }

    /// The height half of the same rule: the large card's rows are taller, and
    /// the silhouette has to be built from the card metrics that drew them.
    @Test("switching to large puts a pointer below the minimalist card on the island")
    func largeLayoutDeepensHover() {
        let harness = Self.expandedHarness()
        harness.mouse.move(to: Self.belowTheMinimalistCard)
        #expect(harness.controller.isHovered == false)

        harness.controller.applyLayout(.large)

        #expect(harness.controller.isHovered)
    }

    @Test("switching back to minimalist takes the wider edge away again")
    func minimalistLayoutNarrowsHover() {
        let harness = Self.expandedHarness()
        harness.controller.applyLayout(.large)
        harness.mouse.move(to: Self.betweenTheTwoEdges)

        harness.controller.applyLayout(.minimalist)

        #expect(harness.controller.isHovered == false)
    }

    @Test("a visible panel resizes to the new window budget at once")
    func visiblePanelResizes() {
        let harness = Self.expandedHarness()

        harness.controller.applyLayout(.large)

        #expect(harness.panel.frame == panelFrame(for: Self.notchedScreen, metrics: IslandLayout.large.panel))
    }

    /// A size picked while the island is ordered out still has to be the size
    /// it comes back at.
    @Test("a hidden panel comes back at the size picked while it was hidden")
    func hiddenPanelAdoptsLayoutOnShow() {
        let harness = Self.makeHarness()

        harness.controller.applyLayout(.large)
        harness.controller.start()

        #expect(harness.controller.state == .compact)
        #expect(harness.panel.frame == panelFrame(for: Self.notchedScreen, metrics: IslandLayout.large.panel))
    }
}

@MainActor
private final class LayoutFakeMouse: MouseLocationObserving {
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
