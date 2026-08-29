import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import NotchFlowCore
@testable import NotchFlowUI

@Suite("NotchPanel", .serialized)
@MainActor
struct NotchPanelTests {
    private static let metrics = PanelMetrics(
        maximumExpandedSize: CGSize(width: 640, height: 260),
        minimumBottomInset: 120
    )

    private static func makePanel() -> NotchPanel {
        NotchPanel(metrics: metrics, content: Color.clear)
    }

    private static let notchedScreen = ScreenDescription(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: ScreenSafeAreaInsets(top: 37),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 656, height: 37),
        auxiliaryTopRightArea: CGRect(x: 856, y: 945, width: 656, height: 37),
        isBuiltIn: true
    )

    @Test("is borderless and non-activating")
    func styleMask() {
        #expect(Self.makePanel().styleMask == [.borderless, .nonactivatingPanel])
    }

    @Test("floats above ordinary windows and the menu bar")
    func floatsAboveTheMenuBar() {
        let panel = Self.makePanel()

        #expect(panel.isFloatingPanel)
        #expect(panel.level.rawValue > NSWindow.Level.mainMenu.rawValue)
    }

    @Test("draws no backing rectangle behind the island")
    func isTransparent() {
        let panel = Self.makePanel()

        #expect(panel.isOpaque == false)
        #expect(panel.backgroundColor == .clear)
        #expect(panel.hasShadow == false)
    }

    @Test("stays on screen and in place while another app is active")
    func staysPutWhileInactive() {
        let panel = Self.makePanel()

        #expect(panel.hidesOnDeactivate == false)
        #expect(panel.isMovable == false)
        #expect(panel.isMovableByWindowBackground == false)
    }

    @Test("joins every Space, survives full screen, and ignores Mission Control")
    func collectionBehavior() {
        #expect(Self.makePanel().collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary])
    }

    @Test("never steals keyboard focus")
    func neverTakesFocus() {
        let panel = Self.makePanel()

        #expect(panel.canBecomeKey == false)
        #expect(panel.canBecomeMain == false)
    }

    @Test("is click-through until a state change opts back in")
    func isClickThroughByDefault() {
        #expect(Self.makePanel().ignoresMouseEvents)
    }

    @Test("outlives being closed")
    func outlivesClose() {
        #expect(Self.makePanel().isReleasedWhenClosed == false)
    }

    @Test("positions itself under the notch of the given screen")
    func positionsUnderTheNotch() {
        let panel = Self.makePanel()

        panel.reposition(on: Self.notchedScreen)

        #expect(panel.frame == panelFrame(for: Self.notchedScreen, metrics: Self.metrics))
        #expect(panel.frame.midX == notchRect(for: Self.notchedScreen)?.midX)
        #expect(panel.frame.maxY == Self.notchedScreen.frame.maxY)
    }

    @Test("keeps its size across repositions so the window server never resizes it")
    func keepsItsSizeAcrossRepositions() {
        let panel = Self.makePanel()
        let externalScreen = ScreenDescription(
            frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
            safeAreaInsets: .zero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: false
        )

        panel.reposition(on: Self.notchedScreen)
        let sizeUnderTheNotch = panel.frame.size
        panel.reposition(on: externalScreen)

        #expect(panel.frame.size == sizeUnderTheNotch)
        #expect(panel.frame.midX == externalScreen.frame.midX)
    }
}
