import CoreGraphics
import Testing

@testable import NotchFlowCore

@Suite("PanelGeometry")
struct PanelGeometryTests {
    private static let metrics = PanelMetrics(
        maximumExpandedSize: CGSize(width: 640, height: 260),
        minimumBottomInset: 120
    )

    private static func notchedScreen(
        frame: CGRect = CGRect(x: 0, y: 0, width: 1512, height: 982),
        topInset: CGFloat = 37,
        notchWidth: CGFloat = 200
    ) -> ScreenDescription {
        let notchOriginX = frame.midX - notchWidth / 2
        return ScreenDescription(
            frame: frame,
            safeAreaInsets: ScreenSafeAreaInsets(top: topInset),
            auxiliaryTopLeftArea: CGRect(
                x: frame.minX,
                y: frame.maxY - topInset,
                width: notchOriginX - frame.minX,
                height: topInset
            ),
            auxiliaryTopRightArea: CGRect(
                x: notchOriginX + notchWidth,
                y: frame.maxY - topInset,
                width: frame.maxX - (notchOriginX + notchWidth),
                height: topInset
            ),
            isBuiltIn: true
        )
    }

    private static func externalScreen(
        frame: CGRect = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    ) -> ScreenDescription {
        ScreenDescription(
            frame: frame,
            safeAreaInsets: .zero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: false
        )
    }

    @Test("centres the panel on the notch")
    func centresOnNotch() {
        let screen = Self.notchedScreen()
        let frame = panelFrame(for: screen, metrics: Self.metrics)

        #expect(frame.midX == notchRect(for: screen)?.midX)
    }

    @Test("sits flush against the top of the screen so content can hug the notch")
    func flushWithScreenTop() {
        let screen = Self.notchedScreen()
        let frame = panelFrame(for: screen, metrics: Self.metrics)

        #expect(frame.maxY == screen.frame.maxY)
    }

    @Test("uses the maximum expanded size when the screen has room for it")
    func usesMaximumExpandedSize() {
        let frame = panelFrame(for: Self.notchedScreen(), metrics: Self.metrics)

        #expect(frame.size == Self.metrics.maximumExpandedSize)
    }

    @Test("centres on the menu bar when the screen has no notch")
    func fallsBackToMenuBarCentre() {
        let screen = Self.externalScreen()
        let frame = panelFrame(for: screen, metrics: Self.metrics)

        #expect(frame.midX == screen.frame.midX)
        #expect(frame.maxY == screen.frame.maxY)
        #expect(frame.size == Self.metrics.maximumExpandedSize)
    }

    @Test("keeps the panel clear of the Dock on a short screen")
    func clampsHeightAboveTheDock() {
        let shortScreen = Self.notchedScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 300)
        )

        let frame = panelFrame(for: shortScreen, metrics: Self.metrics)

        #expect(frame.height == shortScreen.frame.height - Self.metrics.minimumBottomInset)
        #expect(frame.minY == shortScreen.frame.minY + Self.metrics.minimumBottomInset)
    }

    @Test("never grows wider than the screen")
    func clampsWidthToScreen() {
        let narrowScreen = Self.notchedScreen(
            frame: CGRect(x: 0, y: 0, width: 480, height: 982),
            notchWidth: 160
        )

        let frame = panelFrame(for: narrowScreen, metrics: Self.metrics)

        #expect(frame.width == narrowScreen.frame.width)
        #expect(frame.minX == narrowScreen.frame.minX)
    }

    @Test("stays inside a screen whose notch sits off centre")
    func clampsHorizontallyIntoScreenBounds() {
        let screen = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 900, height: 982),
            safeAreaInsets: ScreenSafeAreaInsets(top: 37),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 40, height: 37),
            auxiliaryTopRightArea: CGRect(x: 240, y: 945, width: 660, height: 37),
            isBuiltIn: true
        )

        let frame = panelFrame(for: screen, metrics: Self.metrics)

        #expect(frame.minX == screen.frame.minX)
        #expect(screen.frame.contains(frame))
    }

    @Test("is expressed in the coordinate space of a screen with a non-zero origin")
    func respectsScreenOrigin() {
        let screen = Self.externalScreen(
            frame: CGRect(x: -2560, y: 200, width: 2560, height: 1440)
        )

        let frame = panelFrame(for: screen, metrics: Self.metrics)

        #expect(frame.maxY == 1640)
        #expect(frame.midX == -1280)
    }

    @Test("returns the same frame for the same screen")
    func isPure() {
        let screen = Self.notchedScreen()

        #expect(
            panelFrame(for: screen, metrics: Self.metrics)
                == panelFrame(for: screen, metrics: Self.metrics)
        )
    }

    @Test("hugs the notch with the hover target, padded on every side the pill can grow")
    func hitRectHugsTheNotch() throws {
        let screen = Self.notchedScreen()
        let notch = try #require(notchRect(for: screen))
        let hit = compactHitRect(for: screen, metrics: Self.metrics)

        #expect(hit.midX == notch.midX)
        #expect(hit.maxY == screen.frame.maxY)
        #expect(
            hit.width
                == notch.width
                    + CompactPillMetrics.default.edgeInset * 2
                    + Self.metrics.compactHitPadding * 2
        )
        #expect(hit.height == notch.height + Self.metrics.compactHitPadding)
    }

    @Test("derives a symmetric capsule radius from every rendered pill height")
    func compactPillRadiusTracksRenderedHeight() {
        #expect(compactPillCornerRadius(for: CGSize(width: 200, height: 32)) == 16)
        #expect(compactPillCornerRadius(for: CGSize(width: 220, height: 37)) == 18.5)
        #expect(compactPillCornerRadius(for: CGSize(width: 20, height: 32)) == 10)
    }

    @Test("keeps the hover target inside the panel frame it lives in")
    func hitRectStaysInsideThePanel() {
        let screen = Self.notchedScreen()

        #expect(
            panelFrame(for: screen, metrics: Self.metrics)
                .contains(compactHitRect(for: screen, metrics: Self.metrics))
        )
    }

    @Test("grows the hover target with every visible activity slot")
    func hitRectTracksVisibleSlots() throws {
        let screen = Self.notchedScreen()
        let pillMetrics = CompactPillMetrics.default
        let slotCount = 3
        let hitRect = compactHitRect(
            for: screen,
            slotCount: slotCount,
            metrics: Self.metrics,
            pillMetrics: pillMetrics
        )
        let notch = try #require(notchRect(for: screen))
        let visibleWidth = compactPillSize(
            slotCount: slotCount,
            notchSize: notch.size,
            metrics: pillMetrics
        ).width

        #expect(hitRect.width == visibleWidth + Self.metrics.compactHitPadding * 2)
    }

    @Test("centres the hover target on the menu bar when the screen has no notch")
    func hitRectFallsBackToMenuBarCentre() {
        let screen = Self.externalScreen()
        let hit = compactHitRect(for: screen, metrics: Self.metrics)

        #expect(hit.midX == screen.frame.midX)
        #expect(hit.maxY == screen.frame.maxY)
        #expect(hit.isEmpty == false)
    }

    @Test("never lets the hover target spill off a narrow screen")
    func hitRectClampsToScreen() {
        let narrowScreen = Self.notchedScreen(
            frame: CGRect(x: 0, y: 0, width: 220, height: 982),
            notchWidth: 200
        )

        let hit = compactHitRect(for: narrowScreen, metrics: Self.metrics)

        #expect(narrowScreen.frame.contains(hit))
        #expect(panelFrame(for: narrowScreen, metrics: Self.metrics).contains(hit))
    }

    @Test("is expressed in the coordinate space of a screen with a non-zero origin")
    func hitRectRespectsScreenOrigin() {
        let screen = Self.externalScreen(
            frame: CGRect(x: -2560, y: 200, width: 2560, height: 1440)
        )

        let hit = compactHitRect(for: screen, metrics: Self.metrics)

        #expect(hit.midX == -1280)
        #expect(hit.maxY == 1640)
    }

    // MARK: - Uneven flanks

    /// The pill is centred on the notch, so both flanks must be allocated the
    /// width of the busier one. Sizing from the total instead under-allocates
    /// every uneven split: two agent icons on the trailing side received half
    /// the width they needed and the one nearest the notch fell outside the
    /// drawn capsule.
    @Test("allocates both flanks the width of the busier side")
    func unevenFlanksReserveTheBusierSide() {
        let notch = CGSize(width: 200, height: 32)
        let metrics = CompactPillMetrics()

        let allTrailing = compactPillSize(
            leadingSlotCount: 0,
            trailingSlotCount: 2,
            notchSize: notch,
            metrics: metrics
        )
        let allLeading = compactPillSize(
            leadingSlotCount: 2,
            trailingSlotCount: 0,
            notchSize: notch,
            metrics: metrics
        )
        let balanced = compactPillSize(
            leadingSlotCount: 2,
            trailingSlotCount: 2,
            notchSize: notch,
            metrics: metrics
        )

        #expect(allTrailing == allLeading)
        #expect(allTrailing == balanced)
    }

    /// The concrete guarantee: after the horizontal padding and the two gaps to
    /// the notch, each flank is left with room for every slot it carries.
    @Test("leaves each flank room for its own slots")
    func flanksFitTheirSlots() {
        let notch = CGSize(width: 200, height: 32)
        let metrics = CompactPillMetrics()

        for slots in 1...4 {
            let size = compactPillSize(
                leadingSlotCount: 0,
                trailingSlotCount: slots,
                notchSize: notch,
                metrics: metrics
            )
            let contentWidth = size.width - metrics.edgeInset * 2
            let perFlank = (contentWidth - notch.width - metrics.slotSpacing * 2) / 2
            let required =
                CGFloat(slots) * metrics.slotWidth
                + CGFloat(slots - 1) * metrics.slotSpacing

            #expect(perFlank >= required, "flank too narrow for \(slots) slots")
        }
    }

    @Test("an empty pill is just the notch and its padding")
    func emptyPillIsNotchWidth() {
        let notch = CGSize(width: 200, height: 32)
        let metrics = CompactPillMetrics()
        let size = compactPillSize(
            leadingSlotCount: 0,
            trailingSlotCount: 0,
            notchSize: notch,
            metrics: metrics
        )

        #expect(size.width == notch.width + metrics.edgeInset * 2)
        #expect(size.height == notch.height)
    }

    /// The hit target has to follow the drawn width, or the pointer leaves the
    /// island while still over it.
    @Test("the hit rect grows with the busier flank")
    func hitRectFollowsTheDrawnPill() {
        let screen = Self.notchedScreen()
        let narrow = compactHitRect(for: screen, leadingSlotCount: 0, trailingSlotCount: 1)
        let wide = compactHitRect(for: screen, leadingSlotCount: 0, trailingSlotCount: 2)

        #expect(wide.width > narrow.width)
    }
}
