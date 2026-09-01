import CoreGraphics
import Testing

@testable import NotchFlowUI

@Suite("ConnectedIslandSurface")
struct ConnectedIslandSurfaceTests {
    private static let geometry = ConnectedIslandGeometry(
        compactSize: CGSize(width: 248, height: 37),
        expandedContentSize: CGSize(width: 300, height: 84)
    )

    @Test("expanded surface keeps the compact neck and grows downward")
    func expandedSizeKeepsTheCompactNeck() {
        #expect(Self.geometry.expandedSize.width == 300)
        #expect(Self.geometry.expandedSize.height == 121)
        #expect(Self.geometry.expandedSize.width >= Self.geometry.compactSize.width)
    }

    @Test("neck and detail body are one connected hit shape")
    func neckAndBodyStayConnected() {
        let bounds = CGRect(origin: .zero, size: Self.geometry.expandedSize)

        #expect(Self.geometry.contains(CGPoint(x: bounds.midX, y: 8), in: bounds))
        #expect(Self.geometry.contains(CGPoint(x: bounds.midX, y: 48), in: bounds))
        #expect(Self.geometry.contains(CGPoint(x: bounds.midX, y: 110), in: bounds))
    }

    @Test("transparent top corners do not count as island hover")
    func transparentTopCornersAreExcluded() {
        let bounds = CGRect(origin: .zero, size: Self.geometry.expandedSize)

        #expect(Self.geometry.contains(CGPoint(x: 2, y: 2), in: bounds) == false)
    }

    @Test("wide compact neck keeps stable expanded body corners")
    func wideNeckKeepsStableBodyCorners() {
        let geometry = ConnectedIslandGeometry(
            compactSize: CGSize(width: 360, height: 37),
            expandedContentSize: CGSize(width: 320, height: 150)
        )
        let bounds = CGRect(origin: .zero, size: geometry.expandedSize)

        #expect(geometry.contains(CGPoint(x: 1, y: 30), in: bounds))
        #expect(geometry.contains(CGPoint(x: 1, y: 1), in: bounds) == false)
    }

    @Test("expanded surface remains centered at the top of the panel")
    func surfaceFrameIsTopCentered() {
        let panel = CGRect(x: 100, y: 400, width: 640, height: 260)

        let frame = Self.geometry.expandedScreenFrame(in: panel)

        #expect(frame.midX == panel.midX)
        #expect(frame.maxY == panel.maxY)
        #expect(frame.size == Self.geometry.expandedSize)
    }

    // MARK: - One evenly rounded panel

    /// The expanded silhouette is a plain rounded rectangle.
    ///
    /// It used to be a neck the width of the compact pill flaring into a wider
    /// body, which left transparent wedges either side of the neck: the top
    /// corners of the bounds fell outside the shape. A single rectangle fills
    /// its bounds except for the four rounded corners.
    @Test("the expanded silhouette fills its bounds beside the notch")
    func expandedFillsBesideTheNotch() {
        let geometry = ConnectedIslandGeometry(
            compactSize: CGSize(width: 220, height: 32),
            expandedContentSize: CGSize(width: 360, height: 200)
        )
        let bounds = CGRect(origin: .zero, size: geometry.expandedSize)
        let radius = ConnectedIslandGeometry.expandedCornerRadius

        // Just inside the left edge, level with what used to be the neck: the
        // old shape excluded this, the new one includes it.
        #expect(geometry.contains(CGPoint(x: 2, y: radius + 4), in: bounds))
        #expect(geometry.contains(CGPoint(x: bounds.maxX - 2, y: radius + 4), in: bounds))
    }

    /// The corners are still cut, or it is not a rounded rectangle at all.
    @Test("the expanded silhouette rounds its corners")
    func expandedRoundsItsCorners() {
        let geometry = ConnectedIslandGeometry(
            compactSize: CGSize(width: 220, height: 32),
            expandedContentSize: CGSize(width: 360, height: 200)
        )
        let bounds = CGRect(origin: .zero, size: geometry.expandedSize)

        for corner in [
            CGPoint(x: bounds.minX + 1, y: bounds.minY + 1),
            CGPoint(x: bounds.maxX - 1, y: bounds.minY + 1),
            CGPoint(x: bounds.minX + 1, y: bounds.maxY - 1),
            CGPoint(x: bounds.maxX - 1, y: bounds.maxY - 1),
        ] {
            #expect(!geometry.contains(corner, in: bounds), "corner \(corner) was not cut")
        }
    }

    /// The radius is a point value, so the island keeps the same shape on every
    /// display. A proportional radius would round more on a large panel than a
    /// small one, and change as rows appeared.
    @Test("the corner radius does not vary with the panel's size")
    func cornerRadiusIsSizeIndependent() {
        let radius = ConnectedIslandGeometry.expandedCornerRadius

        for contentHeight in [80.0, 200.0, 420.0] as [CGFloat] {
            for contentWidth in [280.0, 360.0, 620.0] as [CGFloat] {
                let geometry = ConnectedIslandGeometry(
                    compactSize: CGSize(width: 220, height: 32),
                    expandedContentSize: CGSize(width: contentWidth, height: contentHeight)
                )
                let bounds = CGRect(origin: .zero, size: geometry.expandedSize)

                // A corner arc of radius R cuts the diagonal out to about
                // 0.293R. Probing at 0.4R is therefore filled at this radius
                // and cut by any noticeably larger one, which is what pins the
                // radius to a constant without reaching into the path.
                let probe = radius * 0.4
                #expect(!geometry.contains(CGPoint(x: 1, y: 1), in: bounds))
                #expect(
                    geometry.contains(CGPoint(x: probe, y: probe), in: bounds),
                    "radius grew with a \(contentWidth)x\(contentHeight) panel"
                )
            }
        }
    }

    /// A panel smaller than the radius must still produce a drawable shape
    /// rather than an inverted one — the degraded case a very short screen or a
    /// single tiny row could produce.
    @Test("a panel smaller than the radius degrades to a capsule")
    func tinyPanelStaysDrawable() {
        let geometry = ConnectedIslandGeometry(
            compactSize: CGSize(width: 20, height: 8),
            expandedContentSize: CGSize(width: 20, height: 10)
        )
        let bounds = CGRect(origin: .zero, size: geometry.expandedSize)

        #expect(geometry.contains(CGPoint(x: bounds.midX, y: bounds.midY), in: bounds))
        #expect(!geometry.contains(CGPoint(x: bounds.minX, y: bounds.minY), in: bounds))
    }

    /// The compact pill is untouched: still a true capsule, so its ends match
    /// the notch's own curvature whatever height the hardware reports.
    @Test("the compact pill is still a capsule")
    func compactRemainsACapsule() {
        for notchHeight in [24.0, 32.0, 37.0, 44.0] as [CGFloat] {
            let geometry = ConnectedIslandGeometry(
                compactSize: CGSize(width: 220, height: notchHeight),
                expandedContentSize: .zero
            )
            let bounds = CGRect(origin: .zero, size: geometry.compactSize)

            #expect(geometry.contains(CGPoint(x: bounds.midX, y: bounds.midY), in: bounds))
            #expect(!geometry.contains(CGPoint(x: bounds.minX + 0.5, y: bounds.minY + 0.5), in: bounds))
        }
    }
}
