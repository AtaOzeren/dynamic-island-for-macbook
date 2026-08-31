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
    private let metrics: PanelMetrics
    private let mouse: any MouseLocationObserving
    private let screen: ScreenProvider
    private let motion: IslandMotion
    private let reduceMotion: any ReduceMotionQuerying

    /// The pill's hit area on the screen the panel was last ordered in on, which
    /// is the only region a collapsed panel may accept a click in.
    private var hitRect: CGRect = .zero
    private var lastPointerLocation: CGPoint?

    public private(set) var state: PresentationState = .hidden {
        didSet {
            guard state != oldValue else { return }
            transition = islandAnimationCurve(
                from: oldValue,
                to: state,
                motion: motion,
                reduceMotion: reduceMotion.prefersReducedMotion
            )
            onStateChange?(state)
            synchronizeMouseHandling()
        }
    }

    /// How the most recent state change should be drawn. Assigned before
    /// `onStateChange` fires so a view reacting to the new state already knows
    /// which curve carried it there, rather than having to re-derive it.
    public private(set) var transition: IslandAnimationCurve = .none

    /// Whether the pointer is over the compact pill. Distinct from `state`: the
    /// pill peeks on hover without committing to `.expanded`, so this can be true
    /// while compact.
    public private(set) var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            peek = islandPeekCurve(
                in: state,
                motion: motion,
                reduceMotion: reduceMotion.prefersReducedMotion
            )
            onHoverChange?(isHovered)
            synchronizeMouseHandling()
            synchronizeHoverExpansion()
        }
    }

    private var hoverExpansionTimer: Timer?

    /// How the most recent hover change should be drawn, on the same
    /// assigned-before-the-callback contract as `transition`.
    public private(set) var peek: IslandAnimationCurve = .none

    /// Keeps the pill on screen with an empty active set. Re-synchronizes on
    /// assignment so turning it off while nothing is running orders the window
    /// out immediately rather than at the next activity change.
    public var keepBarAlwaysVisible = false {
        didSet {
            guard keepBarAlwaysVisible != oldValue else { return }
            synchronize()
        }
    }

    public var onStateChange: ((PresentationState) -> Void)?
    public var onHoverChange: ((Bool) -> Void)?

    /// Fired after every re-read of the manager's active set, including the ones
    /// that leave `state` untouched.
    ///
    /// A track change or a timer tick mutates what the island must draw without
    /// moving it between hidden, compact, and expanded, so `onStateChange` alone
    /// would leave the panel showing the previous activity. A presenter listens
    /// here to keep its content in step.
    public var onSynchronize: (() -> Void)?

    public init(
        panel: NotchPanel,
        manager: ActivityManager,
        metrics: PanelMetrics = .default,
        mouse: any MouseLocationObserving,
        motion: IslandMotion = .default,
        reduceMotion: any ReduceMotionQuerying = SystemReduceMotion(),
        screen: @escaping ScreenProvider
    ) {
        self.panel = panel
        self.manager = manager
        self.metrics = metrics
        self.mouse = mouse
        self.motion = motion
        self.reduceMotion = reduceMotion
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

    /// Orders the panel out before sleep without losing the manager state.
    public func suspend() {
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
        panel.endInteractiveMode()
        state = .compact
        refreshHoverFromLastPointerLocation()
    }

    /// Enables keyboard focus only after an explicit click or command.
    public func beginInteractiveMode() {
        guard state == .expanded else { return }
        panel.beginInteractiveMode()
    }

    /// Re-evaluates visibility and geometry after display topology changes.
    public func screenConfigurationDidChange() {
        guard let targetScreen = screen() else {
            hide()
            return
        }

        guard manager.activeActivities.isEmpty == false || keepBarAlwaysVisible else {
            hide()
            return
        }

        if state == .hidden {
            show(on: targetScreen)
        } else {
            panel.reposition(on: targetScreen)
            updateHitRect(on: targetScreen)
        }
    }

    /// Re-resolves the target screen and moves the panel onto it.
    ///
    /// `show()` resolves the screen once, on order-in, which is right for the
    /// common case and wrong for every case where the geometry changes while
    /// the island is already up: a display unplugged, a resolution changed, a
    /// wake, or the display-target preference edited with an activity running.
    /// Without this the panel stays at coordinates that may belong to a screen
    /// that no longer exists.
    ///
    /// Does nothing while hidden — a hidden panel resolves its screen on the
    /// next order-in anyway, so repositioning it would be work with no
    /// observable effect. The state is never changed here: this moves the
    /// window, it does not decide whether the window should be up.
    @discardableResult
    public func repositionOnCurrentScreen() -> Bool {
        guard state != .hidden, let screen = screen() else { return false }
        panel.reposition(on: screen)
        updateHitRect(on: screen)
        return true
    }

    private func synchronize() {
        defer { onSynchronize?() }
        guard manager.activeActivities.isEmpty == false || keepBarAlwaysVisible else {
            hide()
            return
        }

        if manager.activeActivities.isEmpty, state == .expanded {
            collapse()
        }

        guard let targetScreen = screen() else {
            hide()
            return
        }

        guard state == .hidden else {
            updateHitRect(on: targetScreen)
            return
        }
        show(on: targetScreen)
    }

    private func show(on screen: ScreenDescription) {
        panel.reposition(on: screen)
        updateHitRect(on: screen)
        panel.orderFrontRegardless()
        state = .compact
        mouse.startObserving { [weak self] location in
            self?.pointerMoved(to: location)
        }
    }

    /// Hidden is entered before hover is dropped so the hover release resolves
    /// its curve against `.hidden` and animates nothing. Clearing hover first
    /// would schedule a peek-out on a window that has already been ordered out.
    private func hide() {
        hoverExpansionTimer?.invalidate()
        hoverExpansionTimer = nil
        mouse.stopObserving()
        panel.endInteractiveMode()
        panel.orderOut(nil)
        state = .hidden
        isHovered = false
        lastPointerLocation = nil
    }

    /// Hover only decides hit-testing while the pill is the whole target. Once
    /// expanded the panel must keep accepting the mouse wherever the pointer
    /// goes, because the click that collapses it lands outside its own bounds.
    private func pointerMoved(to location: CGPoint) {
        lastPointerLocation = location
        guard state != .expanded else { return }
        isHovered = hitRect.contains(location)
    }

    private func refreshHoverFromLastPointerLocation() {
        isHovered = lastPointerLocation.map(hitRect.contains) ?? false
    }

    private func updateHitRect(on screen: ScreenDescription) {
        hitRect = compactHitRect(
            for: screen,
            slotCount: compactSlots(for: manager.compactPresentation).count,
            metrics: metrics
        )
    }

    private func synchronizeMouseHandling() {
        panel.ignoresMouseEvents = state != .expanded && isHovered == false
    }

    private func synchronizeHoverExpansion() {
        hoverExpansionTimer?.invalidate()
        hoverExpansionTimer = nil

        guard isHovered else {
            collapse()
            return
        }
        // Expanding with nothing to show would open onto a blank surface: the
        // always-visible bar can be up with an empty active set, and hover is
        // then only ever a peek.
        guard state == .compact, manager.activeActivities.isEmpty == false else { return }

        hoverExpansionTimer = Timer.scheduledTimer(
            withTimeInterval: motion.hoverExpansionDelay,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isHovered else { return }
                self.expand()
            }
        }
    }
}
