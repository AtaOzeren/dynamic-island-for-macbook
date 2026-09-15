import CoreGraphics

/// The fixed sizing budget for the overlay window. Per `docs/04-overlay-window.md`
/// the panel's frame is allocated once at its maximum expanded size and only
/// recomputed on a display change, so the window server is never asked to resize
/// during an expand or collapse.
public struct PanelMetrics: Equatable, Sendable {
    /// The window is allocated once at this size and mostly transparent while
    /// collapsed, so height here costs nothing until something fills it. 260 was
    /// low enough that a single agent with a handful of sessions already hit the
    /// ceiling and had to scroll; growing first and scrolling only past this is
    /// the behaviour the island is meant to have.
    public static let `default` = PanelMetrics(
        maximumExpandedSize: CGSize(width: 640, height: 460),
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

/// The compact pill's drawn shape: how big it is, and where the notch sits
/// inside it.
///
/// Each flank is only as wide as the slots it actually carries, so a pill with
/// two icons on one side and none on the other does not grow an empty stub on
/// the empty side. That makes the pill asymmetric about the notch, which is why
/// the notch's position has to be carried alongside the size rather than assumed
/// to be the middle: the drawn capsule is centred on the panel, so whoever draws
/// it has to shift it back by `notchCentreOffset` to put the hardware cutout
/// where the hardware actually is.
public struct CompactPillGeometry: Equatable, Sendable {
    /// The pill's drawn size.
    public let size: CGSize
    /// Signed distance from the pill's own horizontal centre to the centre of
    /// the notch region. Zero when the flanks are balanced.
    public let notchCentreOffset: CGFloat

    public init(size: CGSize, notchCentreOffset: CGFloat) {
        self.size = size
        self.notchCentreOffset = notchCentreOffset
    }

    /// How far to move the drawn pill so its notch region lands on the hardware
    /// notch, given that the panel it sits in is itself centred on that notch.
    public var drawingOffset: CGFloat { -notchCentreOffset }
}

/// The compact arrangement the expanded panel takes its width from: two icons
/// on each flank, which is where the pill settles in ordinary use.
public let expandedPanelReferenceSlotCount = 2

/// How much wider the expanded panel is than that pill.
///
/// Enough to read as the pill having grown rather than as a second, unrelated
/// surface, and enough to give the cards room to breathe — but not so much that
/// opening the island throws a wall across the screen.
public let expandedPanelWidthGrowth: CGFloat = 1.12

/// The expanded panel's width.
///
/// Fixed rather than fitted to the widest card. The panel is the compact pill
/// grown, and a width that tracked its contents would make the island a
/// different shape depending on whether music happened to be playing — the same
/// twitch the compact flanks are sized to avoid, one state up.
///
/// Derived from the pill rather than written down as a number because the notch
/// it grows out of is not the same width on every Mac, and a constant tuned on
/// one would be visibly wrong on another.
public func expandedPanelWidth(
    notchSize: CGSize,
    compactMetrics: CompactPillMetrics = .default,
    panelMetrics: PanelMetrics = .default
) -> CGFloat {
    let reference = compactPillSize(
        leadingSlotCount: expandedPanelReferenceSlotCount,
        trailingSlotCount: expandedPanelReferenceSlotCount,
        notchSize: notchSize,
        metrics: compactMetrics
    ).width
    return min(reference * expandedPanelWidthGrowth, panelMetrics.maximumExpandedSize.width)
}

/// The pill's geometry for `leadingSlotCount` slots before the notch and
/// `trailingSlotCount` after it.
public func compactPillGeometry(
    leadingSlotCount: Int,
    trailingSlotCount: Int,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CompactPillGeometry {
    let leadingWidth = compactSideWidth(slotCount: leadingSlotCount, metrics: metrics)
    let trailingWidth = compactSideWidth(slotCount: trailingSlotCount, metrics: metrics)

    // The gap to the notch belongs to a flank that has something in it. Keeping
    // it on an empty flank is the stub this geometry exists to remove.
    let leadingGap = leadingWidth > 0 ? metrics.slotSpacing : 0
    let trailingGap = trailingWidth > 0 ? metrics.slotSpacing : 0

    let width =
        metrics.edgeInset * 2
        + leadingWidth + leadingGap
        + notchSize.width
        + trailingGap + trailingWidth
    let notchCentreFromLeading =
        metrics.edgeInset + leadingWidth + leadingGap + notchSize.width / 2

    return CompactPillGeometry(
        size: CGSize(width: width, height: notchSize.height),
        notchCentreOffset: notchCentreFromLeading - width / 2
    )
}

/// Drawn compact size for a pill carrying `leadingSlotCount` slots before the
/// notch and `trailingSlotCount` after it, including the opaque notch width.
public func compactPillSize(
    leadingSlotCount: Int,
    trailingSlotCount: Int,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    compactPillGeometry(
        leadingSlotCount: leadingSlotCount,
        trailingSlotCount: trailingSlotCount,
        notchSize: notchSize,
        metrics: metrics
    ).size
}

/// The width a pill would need if both flanks were allocated the busier one's
/// width — the symmetric shape, used where the drawn element has to stay centred
/// on the notch regardless of how the slots divide.
public func balancedCompactPillSize(
    leadingSlotCount: Int,
    trailingSlotCount: Int,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    let sideSlots = max(max(leadingSlotCount, 0), max(trailingSlotCount, 0))
    return compactPillSize(
        leadingSlotCount: sideSlots,
        trailingSlotCount: sideSlots,
        notchSize: notchSize,
        metrics: metrics
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
    let pill = compactPillGeometry(
        leadingSlotCount: leadingSlotCount,
        trailingSlotCount: trailingSlotCount,
        notchSize: notchSize,
        metrics: pillMetrics
    )
    let notchCentreX = hardwareNotch?.midX ?? screen.frame.midX
    // The pill is drawn shifted so its notch region lands on the hardware notch,
    // which means its own centre is no longer the notch's centre. Following that
    // shift is what keeps the hover target under the pixels the user sees.
    let pillCentreX = notchCentreX + pill.drawingOffset

    let width = min(pill.size.width + metrics.compactHitPadding * 2, panel.width)
    let height = min(pill.size.height + metrics.compactHitPadding, panel.height)
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
