import AppKit
import NotchFlowCore
import SwiftUI

/// The single borderless overlay window that draws the island, specified by the
/// property table in `docs/04-overlay-window.md`.
///
/// Created once at launch and never deallocated. Its frame is allocated at the
/// maximum expanded size and only recomputed on a display change, so expanding
/// and collapsing animate SwiftUI content inside an unchanging window instead of
/// paying a window-server resize on every transition.
@MainActor
public final class NotchPanel: NSPanel {
    /// One step above the menu bar: high enough that the menu bar and ordinary
    /// windows never draw over the island, low enough to stay under
    /// system-critical UI such as the screen-lock overlay.
    public static let level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)

    private let metrics: PanelMetrics

    public init(metrics: PanelMetrics = .default, content: some View) {
        self.metrics = metrics
        super.init(
            contentRect: CGRect(origin: .zero, size: metrics.maximumExpandedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = Self.level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = true

        // The panel outlives every close and is positioned only by `reposition`,
        // so neither AppKit's release-on-close nor its state restoration and
        // order-in fade apply.
        isReleasedWhenClosed = false
        isRestorable = false
        animationBehavior = .none

        contentView = NSHostingView(rootView: content)
    }

    /// A click on the island must never take focus from the app the user is
    /// typing in, so the panel is ineligible to become key or main.
    public override var canBecomeKey: Bool { false }

    public override var canBecomeMain: Bool { false }

    /// Moves the panel under the notch of `screen`, or under the centre of its
    /// menu bar when that screen has no notch.
    public func reposition(on screen: ScreenDescription) {
        setFrame(panelFrame(for: screen, metrics: metrics), display: false)
    }
}
