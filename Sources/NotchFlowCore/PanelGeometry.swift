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

    public init(
        slotWidth: CGFloat = 22,
        slotSpacing: CGFloat = 6,
        edgeInset: CGFloat = 10,
        symbolSize: CGFloat = 13
    ) {
        self.slotWidth = slotWidth
        self.slotSpacing = slotSpacing
        self.edgeInset = edgeInset
        self.symbolSize = symbolSize
    }
}

/// Width of one side's slot run, excluding the gap to the notch.
private func compactSideWidth(slotCount: Int, metrics: CompactPillMetrics) -> CGFloat {
    let slots = max(slotCount, 0)
    guard slots > 0 else { return 0 }
    return CGFloat(slots) * metrics.slotWidth + CGFloat(slots - 1) * metrics.slotSpacing
}

/// Drawn compact size for a pill carrying `leadingSlotCount` slots before the
/// notch and `trailingSlotCount` after it, including the opaque notch width.
///
/// Both sides are allocated the width of the *busier* one. The pill is centred
/// on the notch, so the two flanks have to be the same width or the notch stops
/// sitting in the middle of the drawn capsule. Sizing from the total instead —
/// which is what an earlier version did — under-allocates whenever the slots are
/// unevenly split: two agent icons on the trailing side got half the width they
/// needed, and the one nearest the notch was drawn outside the capsule.
public func compactPillSize(
    leadingSlotCount: Int,
    trailingSlotCount: Int,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    let sideSlots = max(max(leadingSlotCount, 0), max(trailingSlotCount, 0))
    guard sideSlots > 0 else {
        return CGSize(
            width: notchSize.width + metrics.edgeInset * 2,
            height: notchSize.height
        )
    }

    let sideWidth = compactSideWidth(slotCount: sideSlots, metrics: metrics)
    return CGSize(
        width: notchSize.width
            + (sideWidth + metrics.slotSpacing) * 2
            + metrics.edgeInset * 2,
        height: notchSize.height
    )
}

/// Drawn compact size for `slotCount` slots split evenly around the notch, the
/// balanced arrangement `compactSlotLayout` produces when no agent is present.
public func compactPillSize(
    slotCount: Int,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    let slots = max(slotCount, 0)
    return compactPillSize(
        leadingSlotCount: (slots + 1) / 2,
        trailingSlotCount: slots / 2,
        notchSize: notchSize,
        metrics: metrics
    )
}

/// Radius that turns the rendered compact bounds into a true capsule. Deriving
/// it from current bounds keeps top and bottom curvature identical across
/// hardware-notch and menu-bar fallback heights.
public func compactPillCornerRadius(for size: CGSize) -> CGFloat {
    let width = max(size.width, 0)
    let height = max(size.height, 0)
    return min(width, height) / 2
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
    leadingSlotCount: Int,
    trailingSlotCount: Int,
    metrics: PanelMetrics = .default,
    pillMetrics: CompactPillMetrics = .default
) -> CGRect {
    let panel = panelFrame(for: screen, metrics: metrics)
    let hardwareNotch = notchRect(for: screen)
    let notchSize = hardwareNotch?.size ?? metrics.compactFallbackSize
    let drawnSize = compactPillSize(
        leadingSlotCount: leadingSlotCount,
        trailingSlotCount: trailingSlotCount,
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

/// The hit target for `slotCount` slots split evenly around the notch.
public func compactHitRect(
    for screen: ScreenDescription,
    slotCount: Int = 0,
    metrics: PanelMetrics = .default,
    pillMetrics: CompactPillMetrics = .default
) -> CGRect {
    let slots = max(slotCount, 0)
    return compactHitRect(
        for: screen,
        leadingSlotCount: (slots + 1) / 2,
        trailingSlotCount: slots / 2,
        metrics: metrics,
        pillMetrics: pillMetrics
    )
}

private func clamp(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
    min(max(value, lowerBound), max(lowerBound, upperBound))
}
