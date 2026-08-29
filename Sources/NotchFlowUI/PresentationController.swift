import AppKit
import NotchFlowCore

/// The three visual states of the island, per the state table in
/// `docs/04-overlay-window.md`.
public enum PresentationState: Sendable, Equatable {
    /// Ordered out. The window occupies no compositor layer and no animation
    /// may run, which is what buys the idle budget in `docs/02-performance-contract.md`.
    case hidden
    /// Ordered in, drawing the pill that hugs the notch.
    case compact
    /// Ordered in, drawing full activity detail below the notch.
    case expanded
}

/// Drives the panel between hidden, compact, and expanded.
///
/// The window is ordered in when, and only when, the manager's active set is
/// non-empty, and ordered out the instant it empties — the single rule
/// `docs/01-architecture.md` names as the guarantee behind the idle budget.
@MainActor
public final class PresentationController {
    /// Supplies the screen to present on, re-read on every order-in so a
    /// display change between activities lands the panel on the right notch.
    public typealias ScreenProvider = @MainActor () -> ScreenDescription?

    private let panel: NotchPanel
    private let manager: ActivityManager
    private let screen: ScreenProvider

    public private(set) var state: PresentationState = .hidden {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    public var onStateChange: ((PresentationState) -> Void)?

    public init(
        panel: NotchPanel,
        manager: ActivityManager,
        screen: @escaping ScreenProvider
    ) {
        self.panel = panel
        self.manager = manager
        self.screen = screen
    }

    public func start() {
        manager.onActivitiesChanged = { [weak self] in
            self?.synchronize()
        }
        synchronize()
    }

    public func stop() {
        manager.onActivitiesChanged = nil
        hide()
    }

    /// Grows the content to the expanded geometry. Ignored while hidden: an
    /// activity arriving off screen orders the window in at its resting compact
    /// geometry first, and only a later transition animates.
    public func expand() {
        guard state == .compact else { return }
        state = .expanded
    }

    /// Returns the content to the compact pill without ordering the window out.
    public func collapse() {
        guard state == .expanded else { return }
        state = .compact
    }

    private func synchronize() {
        guard manager.activeActivities.isEmpty == false else {
            hide()
            return
        }
        guard state == .hidden else { return }
        show()
    }

    private func show() {
        guard let screen = screen() else { return }
        panel.reposition(on: screen)
        panel.orderFrontRegardless()
        state = .compact
    }

    private func hide() {
        panel.orderOut(nil)
        state = .hidden
    }
}
