import CoreGraphics

/// The fixed sizing budget for the overlay window. Per `docs/04-overlay-window.md`
/// the panel's frame is allocated once at its maximum expanded size and only
/// recomputed on a display change, so the window server is never asked to resize
/// during an expand or collapse.
public struct PanelMetrics: Equatable, Sendable {
    public static let `default` = PanelMetrics(
        maximumExpandedSize: CGSize(width: 640, height: 260),
        minimumBottomInset: 120
    )

    /// The largest content the expanded state can ever draw.
    public let maximumExpandedSize: CGSize
    /// Space reserved at the bottom of the screen so the expanded panel stays
    /// clear of the Dock.
    public let minimumBottomInset: CGFloat
    /// How far past the notch the compact pill may grow, and therefore how far
    /// past it the pointer still counts as hovering. Peeking widens the pill
    /// before the user clicks, so the hover target has to cover the peeked size
    /// or the pill would flicker at its own edge.
    public let compactHitPadding: CGFloat
    /// The compact pill's size on a screen with no notch, where there is no
    /// hardware rectangle to inherit — the degraded mode from
    /// `docs/03-display-and-notch.md`.
    public let compactFallbackSize: CGSize

    public init(
        maximumExpandedSize: CGSize,
        minimumBottomInset: CGFloat,
        compactHitPadding: CGFloat = 8,
        compactFallbackSize: CGSize = CGSize(width: 200, height: 32)
    ) {
        self.maximumExpandedSize = maximumExpandedSize
        self.minimumBottomInset = minimumBottomInset
        self.compactHitPadding = compactHitPadding
        self.compactFallbackSize = compactFallbackSize
    }
}

/// Fixed visual budget shared by compact rendering and AppKit hit testing.
public struct CompactPillMetrics: Equatable, Sendable {
    public static let `default` = CompactPillMetrics()

    public let slotWidth: CGFloat
    public let slotSpacing: CGFloat
    public let edgeInset: CGFloat
    public let symbolSize: CGFloat
    public let cornerRadius: CGFloat

    public init(
        slotWidth: CGFloat = 22,
        slotSpacing: CGFloat = 6,
        edgeInset: CGFloat = 10,
        symbolSize: CGFloat = 13,
        cornerRadius: CGFloat = 12
    ) {
        self.slotWidth = slotWidth
        self.slotSpacing = slotSpacing
        self.edgeInset = edgeInset
        self.symbolSize = symbolSize
        self.cornerRadius = cornerRadius
    }
}

/// Drawn compact size for `slotCount`, including opaque notch width.
public func compactPillSize(
    slotCount: Int,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    let slots = max(slotCount, 0)
    guard slots > 0 else {
        return CGSize(
            width: notchSize.width + metrics.edgeInset * 2,
            height: notchSize.height
        )
    }

    return CGSize(
        width: notchSize.width
            + CGFloat(slots) * (metrics.slotWidth + metrics.slotSpacing)
            + metrics.edgeInset * 2,
        height: notchSize.height
    )
}

/// The overlay window's frame on `screen`, in screen coordinates.
///
/// The panel is centred on the notch and flush with the top of the screen. On a
/// screen without a notch it centres on the menu bar instead — the degraded mode
/// from `docs/03-display-and-notch.md`, not an error state. The result is always
/// contained by the screen frame.
public func panelFrame(
    for screen: ScreenDescription,
    metrics: PanelMetrics = .default
) -> CGRect {
    let bounds = screen.frame
    let centreX = notchRect(for: screen)?.midX ?? bounds.midX

    let width = min(metrics.maximumExpandedSize.width, bounds.width)
    let height = min(
        metrics.maximumExpandedSize.height,
        max(bounds.height - metrics.minimumBottomInset, 0)
    )

    let originX = clamp(centreX - width / 2, lowerBound: bounds.minX, upperBound: bounds.maxX - width)

    return CGRect(x: originX, y: bounds.maxY - height, width: width, height: height)
}

/// The compact pill's hover and click target on `screen`, in screen coordinates.
///
/// The panel's own frame is allocated at the maximum expanded size and is mostly
/// empty while collapsed, so this — not the window frame — is the rectangle
/// `docs/04-overlay-window.md` means by "the compact pill's hit area". A pointer
/// outside it leaves the panel click-through, which is what lets a menu-bar item
/// beside the notch stay clickable. The result is always contained by
/// `panelFrame(for:metrics:)`.
public func compactHitRect(
    for screen: ScreenDescription,
    slotCount: Int = 0,
    metrics: PanelMetrics = .default,
    pillMetrics: CompactPillMetrics = .default
) -> CGRect {
    let panel = panelFrame(for: screen, metrics: metrics)
    let hardwareNotch = notchRect(for: screen)
    let notchSize = hardwareNotch?.size ?? metrics.compactFallbackSize
    let drawnSize = compactPillSize(
        slotCount: slotCount,
        notchSize: notchSize,
        metrics: pillMetrics
    )
    let pillCentreX = hardwareNotch?.midX ?? screen.frame.midX

    let width = min(drawnSize.width + metrics.compactHitPadding * 2, panel.width)
    let height = min(drawnSize.height + metrics.compactHitPadding, panel.height)
    let originX = clamp(
        pillCentreX - width / 2,
        lowerBound: panel.minX,
        upperBound: panel.maxX - width
    )

    return CGRect(x: originX, y: panel.maxY - height, width: width, height: height)
}

private func clamp(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
    min(max(value, lowerBound), max(lowerBound, upperBound))
}
