import AppKit
import Foundation
import SwiftUI
import Testing

@testable import KerNotch
@testable import KerNotchCore
@testable import KerNotchUI

/// The island stepping aside for a full-screen app is drawn, not only ordered
/// out: at rest after stepping aside it must draw nothing at all, and once it
/// is back it must draw the pill as it always has.
@Suite("IslandRootView withdrawal", .serialized)
@MainActor
struct IslandRootViewWithdrawalTests {
    private static let panelSize = CGSize(width: 640, height: 260)

    @Test("a stepped-aside island draws nothing")
    func steppedAsideIslandIsInvisible() {
        let model = Self.compactModel()
        model.applyWithdrawal(true, curve: .none)

        #expect(Self.drawnPixelCount(of: model) == 0)
    }

    @Test("an island that has come back draws its pill")
    func returnedIslandIsVisible() {
        let model = Self.compactModel()
        model.applyWithdrawal(true, curve: .none)
        model.applyWithdrawal(false, curve: .none)

        #expect(Self.drawnPixelCount(of: model) > 0)
    }

    @Test("stepping aside shrinks the island unless the curve only fades")
    func onlyTravellingCurvesShrink() {
        let model = Self.compactModel()

        model.applyWithdrawal(true, curve: .easeIn(duration: 0.2))
        #expect(model.withdrawalMovesGeometry)

        model.applyWithdrawal(false, curve: .crossFade(duration: 0.1))
        #expect(model.withdrawalMovesGeometry == false)
    }

    private static func compactModel() -> IslandViewModel {
        let model = IslandViewModel(
            compact: ActivityManager().compactPresentation,
            notchSize: CGSize(width: 200, height: 32),
            layout: .minimalist
        )
        model.state = .compact
        return model
    }

    /// Renders the island off screen and counts the pixels it covers.
    ///
    /// Hosted in a real window and given a run-loop turn first: before that,
    /// the layers SwiftUI builds are not attached and render blank whatever the
    /// island would draw.
    private static func drawnPixelCount(of model: IslandViewModel) -> Int {
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        let hostingView = NSHostingView(rootView: IslandRootView(model: model))
        hostingView.frame = CGRect(origin: .zero, size: panelSize)
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        guard
            let layer = hostingView.layer,
            let context = CGContext(
                data: nil,
                width: Int(panelSize.width),
                height: Int(panelSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return 0
        }
        layer.render(in: context)
        guard let data = context.data else { return 0 }

        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * context.height)
        var drawn = 0
        for row in 0..<context.height {
            for column in 0..<context.width where bytes[row * context.bytesPerRow + column * 4 + 3] > 0 {
                drawn += 1
            }
        }
        return drawn
    }
}
