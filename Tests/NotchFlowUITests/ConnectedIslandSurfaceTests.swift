import CoreGraphics
import Testing

@testable import NotchFlowUI

@Suite("ConnectedIslandSurface")
struct ConnectedIslandSurfaceTests {
    private static let geometry = ConnectedIslandGeometry(
        compactSize: CGSize(width: 248, height: 37),
        expandedContentSize: CGSize(width: 300, height: 84)
    )

    /// The body is the content's width; the flare adds one radius either side.
    @Test("the expanded surface is the body plus its flare")
    func expandedSizeIsBodyPlusFlare() {
        let flare = ConnectedIslandGeometry.topFlareRadius

        #expect(Self.geometry.expandedBodyWidth == 300)
        #expect(Self.geometry.expandedSize.width == 300 + flare * 2)
        #expect(Self.geometry.expandedSize.height == 121)
    }

    @Test("the notch strip and the detail body are one hit shape")
    func neckAndBodyStayConnected() {
        let bounds = CGRect(origin: .zero, size: Self.geometry.expandedSize)

        #expect(Self.geometry.contains(CGPoint(x: bounds.midX, y: 8), in: bounds))
        #expect(Self.geometry.contains(CGPoint(x: bounds.midX, y: 48), in: bounds))
        #expect(Self.geometry.contains(CGPoint(x: bounds.midX, y: 110), in: bounds))
    }

    @Test("expanded surface remains centered at the top of the panel")
    func surfaceFrameIsTopCentered() {
        let panel = CGRect(x: 100, y: 400, width: 640, height: 260)

        let frame = Self.geometry.expandedScreenFrame(in: panel)

        #expect(frame.midX == panel.midX)
        #expect(frame.maxY == panel.maxY)
        #expect(frame.size == Self.geometry.expandedSize)
    }

    // MARK: - Flared at the top, rounded at the bottom

    /// The panel is at its widest along its very top edge and narrows to the
    /// body just below it. That is the whole point of the outward turn: the
    /// island reads as flowing into the menu bar instead of sitting under it.
    @Test("the top corners turn outwards")
    func topCornersTurnOutwards() {
        let geometry = ConnectedIslandGeometry(
            compactSize: CGSize(width: 220, height: 37),
            expandedContentSize: CGSize(width: 320, height: 180)
        )
        let bounds = CGRect(origin: .zero, size: geometry.expandedSize)
        let flare = ConnectedIslandGeometry.topFlareRadius
        let bodyMinX = bounds.minX + flare
        let bodyMaxX = bounds.maxX - flare

        // Just outside the body, high up: inside the flare.
        #expect(geometry.contains(CGPoint(x: bodyMinX - 2, y: 2), in: bounds))
        #expect(geometry.contains(CGPoint(x: bodyMaxX + 2, y: 2), in: bounds))

        // The same distance outside the body, below the flare: past the edge.
        #expect(!geometry.contains(CGPoint(x: bodyMinX - 2, y: flare + 10), in: bounds))
        #expect(!geometry.contains(CGPoint(x: bodyMaxX + 2, y: flare + 10), in: bounds))
    }

    /// The bottom corners still turn inwards, or it is not a card at all.
    @Test("the bottom corners stay rounded")
    func bottomCornersStayRounded() {
        let geometry = ConnectedIslandGeometry(
            compactSize: CGSize(width: 220, height: 37),
            expandedContentSize: CGSize(width: 320, height: 180)
        )
        let bounds = CGRect(origin: .zero, size: geometry.expandedSize)
        let flare = ConnectedIslandGeometry.topFlareRadius
        let radius = ConnectedIslandGeometry.expandedCornerRadius

        #expect(!geometry.contains(CGPoint(x: bounds.minX + flare + 1, y: bounds.maxY - 1), in: bounds))
        #expect(!geometry.contains(CGPoint(x: bounds.maxX - flare - 1, y: bounds.maxY - 1), in: bounds))
        #expect(
            geometry.contains(
                CGPoint(x: bounds.minX + flare + radius, y: bounds.maxY - radius),
                in: bounds
            )
        )
    }

    /// Both radii are point values, so the island keeps the same shape on every
    /// display. A proportional radius would round more on a large panel than a
    /// small one, and change again as rows appeared.
    @Test("the silhouette does not vary with the panel's size")
    func silhouetteIsSizeIndependent() {
        let flare = ConnectedIslandGeometry.topFlareRadius
        let radius = ConnectedIslandGeometry.expandedCornerRadius

        for contentHeight in [80.0, 200.0, 420.0] as [CGFloat] {
            for contentWidth in [280.0, 360.0, 620.0] as [CGFloat] {
                let geometry = ConnectedIslandGeometry(
                    compactSize: CGSize(width: 220, height: 32),
                    expandedContentSize: CGSize(width: contentWidth, height: contentHeight)
                )
                let bounds = CGRect(origin: .zero, size: geometry.expandedSize)
                let label = "\(contentWidth)x\(contentHeight)"

                // A corner arc of radius R cuts the diagonal out to about
                // 0.293R. Probing at 0.4R in from the bottom-left corner is
                // therefore filled at this radius and cut by any noticeably
                // larger one, which pins the radius without reading the path.
                let probe = radius * 0.4
                #expect(
                    !geometry.contains(
                        CGPoint(x: bounds.minX + flare + 1, y: bounds.maxY - 1),
                        in: bounds
                    ),
                    "bottom corner not cut on a \(label) panel"
                )
                #expect(
                    geometry.contains(
                        CGPoint(x: bounds.minX + flare + probe, y: bounds.maxY - probe),
                        in: bounds
                    ),
                    "bottom radius grew on a \(label) panel"
                )
                // The flare stays one radius wide however wide the panel gets.
                #expect(
                    geometry.contains(CGPoint(x: bounds.minX + flare - 2, y: 2), in: bounds),
                    "flare shrank on a \(label) panel"
                )
            }
        }
    }

    /// A panel smaller than its own radii must still produce a drawable shape
    /// rather than an inverted one — the degraded case a very short screen or a
    /// single tiny row could produce.
    @Test("a panel smaller than its radii stays drawable")
    func tinyPanelStaysDrawable() {
        let geometry = ConnectedIslandGeometry(
            compactSize: CGSize(width: 20, height: 8),
            expandedContentSize: CGSize(width: 20, height: 10)
        )
        let bounds = CGRect(origin: .zero, size: geometry.expandedSize)

        #expect(geometry.contains(CGPoint(x: bounds.midX, y: bounds.midY), in: bounds))
        #expect(!geometry.contains(CGPoint(x: bounds.midX, y: bounds.maxY + 5), in: bounds))
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
