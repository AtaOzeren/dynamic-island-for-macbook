import CoreGraphics
import SwiftUI

private struct DrawsOwnIslandSurfaceKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var drawsOwnIslandSurface: Bool {
        get { self[DrawsOwnIslandSurfaceKey.self] }
        set { self[DrawsOwnIslandSurfaceKey.self] = newValue }
    }
}

public extension View {
    /// Uses an ancestor's connected surface instead of drawing another card.
    func sharingIslandSurface() -> some View {
        environment(\.drawsOwnIslandSurface, false)
    }
}

/// Sizes and backs one expanded item, according to whether it owns its surface.
///
/// A standalone card keeps its intrinsic width and paints its own rounded
/// background. Inside the island there is no second background to paint — the
/// connected shape already did — and every item stretches to the panel's width
/// so the separators between them run edge to edge instead of leaving a ragged
/// stack of differently sized cards.
struct IslandCardLayout: ViewModifier {
    @Environment(\.drawsOwnIslandSurface) private var drawsOwnSurface

    let width: CGFloat
    let height: CGFloat?
    let alignment: Alignment
    let cornerRadius: CGFloat
    let surface: IslandSurface

    func body(content: Content) -> some View {
        if drawsOwnSurface {
            content
                .frame(width: width, height: height, alignment: alignment)
                .background {
                    surface.fill(
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                }
        } else {
            content
                .frame(maxWidth: .infinity, alignment: alignment)
                .frame(height: height, alignment: alignment)
        }
    }
}

extension View {
    /// Applies `IslandCardLayout`. Named for the call site's vocabulary — every
    /// expanded per-kind view is a card — rather than for the modifier.
    func islandCard(
        width: CGFloat,
        height: CGFloat? = nil,
        alignment: Alignment = .leading,
        cornerRadius: CGFloat,
        surface: IslandSurface
    ) -> some View {
        modifier(
            IslandCardLayout(
                width: width,
                height: height,
                alignment: alignment,
                cornerRadius: cornerRadius,
                surface: surface
            )
        )
    }
}

/// The hairline between two items inside a shared island surface.
///
/// Occupies the full `height` the panel's size model already reserves between
/// items, so adding separators changes what the gap looks like without changing
/// how tall the panel is.
struct IslandItemSeparator: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.10))
            .frame(height: 1)
            .frame(height: max(height, 1))
            .accessibilityHidden(true)
    }
}

/// Geometry for one island surface that keeps the compact notch extension
/// attached while its detail body grows below it.
public struct ConnectedIslandGeometry: Equatable, Sendable {
    public let compactSize: CGSize
    public let expandedContentSize: CGSize

    public init(compactSize: CGSize, expandedContentSize: CGSize) {
        self.compactSize = CGSize(
            width: max(compactSize.width, 0),
            height: max(compactSize.height, 0)
        )
        self.expandedContentSize = CGSize(
            width: max(expandedContentSize.width, 0),
            height: max(expandedContentSize.height, 0)
        )
    }

    public var expandedSize: CGSize {
        CGSize(
            width: max(compactSize.width, expandedContentSize.width),
            height: compactSize.height + expandedContentSize.height
        )
    }

    /// Screen-space frame for the expanded surface, centred and flush with the
    /// top edge of the panel just like the compact pill.
    public func expandedScreenFrame(in panelFrame: CGRect) -> CGRect {
        let size = expandedSize
        return CGRect(
            x: panelFrame.midX - size.width / 2,
            y: panelFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Hit testing uses the exact connected silhouette. This excludes the
    /// transparent corners beside the compact neck, so moving there counts as
    /// leaving the island even though the backing panel is much larger.
    public func contains(_ point: CGPoint, in bounds: CGRect) -> Bool {
        path(in: bounds).contains(point)
    }

    /// The expanded island's corner radius.
    ///
    /// A point value, not a fraction of the bounds. Points are already
    /// resolution independent — the same 26 renders identically at 1x and 2x —
    /// whereas a proportional radius would give the island a visibly different
    /// shape on a 13" panel than on a 16" one, and change it again every time a
    /// row appeared.
    public static let expandedCornerRadius: CGFloat = 26

    public func path(in bounds: CGRect) -> Path {
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let neckHeight = min(compactSize.height, bounds.height)

        // Compact: a true capsule, so the pill's ends match the notch's own
        // curvature whatever height the hardware reports.
        if neckHeight > 0, bounds.height <= neckHeight + 0.5 {
            return Path(
                roundedRect: bounds,
                cornerRadius: min(bounds.width, bounds.height) / 2,
                style: .continuous
            )
        }

        // Expanded: one evenly rounded rectangle.
        //
        // It used to be drawn as a neck the width of the compact pill flaring
        // into a wider body through a pair of shoulder curves. That silhouette
        // read as two shapes fused together — the flare landed at a different
        // place for every combination of pill width and row count — where a
        // single rounded rectangle reads as one panel hanging from the notch.
        //
        // Clamped to half the smaller side so a panel smaller than the radius
        // degrades to a capsule rather than producing an invalid path.
        return Path(
            roundedRect: bounds,
            cornerRadius: min(
                Self.expandedCornerRadius,
                bounds.width / 2,
                bounds.height / 2
            ),
            style: .continuous
        )
    }
}

/// SwiftUI shape for the shared black surface. Frame interpolation supplies the
/// grow/shrink animation; path topology remains one connected island.
public struct ConnectedIslandShape: Shape {
    private let geometry: ConnectedIslandGeometry

    public init(geometry: ConnectedIslandGeometry) {
        self.geometry = geometry
    }

    public func path(in rect: CGRect) -> Path {
        geometry.path(in: rect)
    }
}
