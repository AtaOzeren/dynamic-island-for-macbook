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

    public func path(in bounds: CGRect) -> Path {
        let neckWidth = min(compactSize.width, bounds.width)
        let neckHeight = min(compactSize.height, bounds.height)
        guard neckWidth > 0, neckHeight > 0 else { return Path() }

        if bounds.height <= neckHeight + 0.5 {
            return Path(
                roundedRect: bounds,
                cornerRadius: min(bounds.width, bounds.height) / 2,
                style: .continuous
            )
        }

        if bounds.width <= neckWidth + 0.5 {
            return Path(
                roundedRect: bounds,
                cornerRadius: min(18, bounds.width / 2, bounds.height / 2),
                style: .continuous
            )
        }

        let neckMinX = bounds.midX - neckWidth / 2
        let neckMaxX = bounds.midX + neckWidth / 2
        let bodyMinX = bounds.minX
        let bodyMaxX = bounds.maxX
        let topRadius = min(neckHeight / 2, neckWidth / 2)
        let bodyRadius = min(18, bounds.width / 2, (bounds.height - neckHeight) / 2)
        let shoulderDepth = min(
            max(neckHeight * 0.32, 8),
            max((bounds.height - neckHeight) * 0.45, 0)
        )
        let neckShoulderY = max(
            bounds.minY + topRadius,
            bounds.minY + neckHeight - shoulderDepth / 2
        )
        let bodyStartY = min(
            bounds.minY + neckHeight + shoulderDepth,
            bounds.maxY - bodyRadius
        )

        var path = Path()
        path.move(to: CGPoint(x: neckMinX + topRadius, y: bounds.minY))
        path.addLine(to: CGPoint(x: neckMaxX - topRadius, y: bounds.minY))
        path.addQuadCurve(
            to: CGPoint(x: neckMaxX, y: bounds.minY + topRadius),
            control: CGPoint(x: neckMaxX, y: bounds.minY)
        )
        path.addLine(to: CGPoint(x: neckMaxX, y: neckShoulderY))
        path.addCurve(
            to: CGPoint(x: bodyMaxX, y: bodyStartY),
            control1: CGPoint(x: neckMaxX, y: bodyStartY),
            control2: CGPoint(x: bodyMaxX - shoulderDepth, y: bounds.minY + neckHeight)
        )
        path.addLine(to: CGPoint(x: bodyMaxX, y: bounds.maxY - bodyRadius))
        path.addQuadCurve(
            to: CGPoint(x: bodyMaxX - bodyRadius, y: bounds.maxY),
            control: CGPoint(x: bodyMaxX, y: bounds.maxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX + bodyRadius, y: bounds.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bodyMinX, y: bounds.maxY - bodyRadius),
            control: CGPoint(x: bodyMinX, y: bounds.maxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX, y: bodyStartY))
        path.addCurve(
            to: CGPoint(x: neckMinX, y: neckShoulderY),
            control1: CGPoint(x: bodyMinX + shoulderDepth, y: bounds.minY + neckHeight),
            control2: CGPoint(x: neckMinX, y: bodyStartY)
        )
        path.addLine(to: CGPoint(x: neckMinX, y: bounds.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: neckMinX + topRadius, y: bounds.minY),
            control: CGPoint(x: neckMinX, y: bounds.minY)
        )
        path.closeSubpath()
        return path
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
