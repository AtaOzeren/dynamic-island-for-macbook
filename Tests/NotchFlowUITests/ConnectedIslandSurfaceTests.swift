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

    @Test("expanded surface remains centered at the top of the panel")
    func surfaceFrameIsTopCentered() {
        let panel = CGRect(x: 100, y: 400, width: 640, height: 260)

        let frame = Self.geometry.expandedScreenFrame(in: panel)

        #expect(frame.midX == panel.midX)
        #expect(frame.maxY == panel.maxY)
        #expect(frame.size == Self.geometry.expandedSize)
    }
}
