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

    public init(maximumExpandedSize: CGSize, minimumBottomInset: CGFloat) {
        self.maximumExpandedSize = maximumExpandedSize
        self.minimumBottomInset = minimumBottomInset
    }
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

private func clamp(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
    min(max(value, lowerBound), max(lowerBound, upperBound))
}
