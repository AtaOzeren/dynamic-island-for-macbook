import AppKit
import NotchFlowCore

/// The three visual states of the island, per the state table in
/// `docs/04-overlay-window.md`.
public enum PresentationState: Sendable, Equatable {
    /// Ordered out while presentation is suspended, stopped, or has no target
    /// screen. Normal app runtime rests in `.compact`, even with no activity.
    case hidden
    /// Ordered in, drawing the pill that hugs the notch.
    case compact
    /// Ordered in, drawing full activity detail below the notch.
    case expanded
}

/// Drives the panel between hidden, compact, and expanded.
///
/// The window stays ordered in at compact size for the app's lifetime. Activity
/// changes only decide whether the compact content can expand; they never make
/// the island disappear.
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
    private var activitiesObserverID: UUID?

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
            if automaticallyExpandsOnHover {
                synchronizeHoverExpansion()
            }
        }
    }

    private var hoverExpansionTimer: Timer?

    /// Multi-display presentation owns one shared hover timer. Standalone
    /// controllers keep the original automatic behaviour by default.
    public var automaticallyExpandsOnHover = true {
        didSet {
            guard automaticallyExpandsOnHover != oldValue else { return }
            hoverExpansionTimer?.invalidate()
            hoverExpansionTimer = nil
            if automaticallyExpandsOnHover {
                synchronizeHoverExpansion()
            }
        }
    }

    /// How the most recent hover change should be drawn, on the same
    /// assigned-before-the-callback contract as `transition`.
    public private(set) var peek: IslandAnimationCurve = .none

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

    /// Which agent instances have their sub-agent list open, read at hit-test
    /// time.
    ///
    /// A closure rather than a stored value because the disclosure lives in the
    /// view model this controller does not own — and an open list makes the
    /// island taller, so a hit test that missed it would treat the pointer as
    /// having left the island the moment it moved onto a sub-agent row.
    private let disclosedInstances: @MainActor () -> Set<ActivityIdentity>

    /// The registration times the panel numbers instances by, read here for the
    /// same reason: they decide how the sessions fold into cards, and therefore
    /// how tall the panel is.
    private let registrationTimes: @MainActor () -> [ActivityIdentity: Date]

    /// Music icons whose few seconds on screen have elapsed.
    ///
    /// A closure rather than a stored value because they live in the view model
    /// this controller does not own — and they change how wide the pill is
    /// drawn, so a hover target that ignored them would keep reporting the
    /// pointer as over an island that had already shrunk away from under it.
    private let hiddenMusicSlotIDs: @MainActor () -> Set<String>

    public init(
        panel: NotchPanel,
        manager: ActivityManager,
        metrics: PanelMetrics = .default,
        mouse: any MouseLocationObserving,
        motion: IslandMotion = .default,
        reduceMotion: any ReduceMotionQuerying = SystemReduceMotion(),
        screen: @escaping ScreenProvider,
        disclosedInstances: @escaping @MainActor () -> Set<ActivityIdentity> = { [] },
        registrationTimes: @escaping @MainActor () -> [ActivityIdentity: Date] = { [:] },
        hiddenMusicSlotIDs: @escaping @MainActor () -> Set<String> = { [] }
    ) {
        self.panel = panel
        self.manager = manager
        self.metrics = metrics
        self.mouse = mouse
        self.motion = motion
        self.reduceMotion = reduceMotion
        self.screen = screen
        self.disclosedInstances = disclosedInstances
        self.registrationTimes = registrationTimes
        self.hiddenMusicSlotIDs = hiddenMusicSlotIDs
    }

    public func start() {
        guard activitiesObserverID == nil else { return }
        activitiesObserverID = manager.observeActivitiesChanged { [weak self] in
            self?.synchronize()
        }
        synchronize()
    }

    public func stop() {
        if let activitiesObserverID {
            manager.removeActivitiesObserver(activitiesObserverID)
            self.activitiesObserverID = nil
        }
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
        guard state == .compact, manager.activeActivities.isEmpty == false else { return }
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
        guard let targetScreen = screen() else {
            hide()
            return
        }

        if manager.activeActivities.isEmpty, state == .expanded {
            collapse()
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

    /// Tracks the exact drawn silhouette in both states. The panel window keeps
    /// its maximum allocation, but transparent space around the island must not
    /// pin expansion or steal menu-bar clicks.
    private func pointerMoved(to location: CGPoint) {
        lastPointerLocation = location
        isHovered = pointerIsInsideIsland(location)
    }

    private func refreshHoverFromLastPointerLocation() {
        isHovered = lastPointerLocation.map(hitRect.contains) ?? false
    }

    private func updateHitRect(on screen: ScreenDescription) {
        let layout = compactSlotLayout(
            for: manager.compactPresentation,
            hiding: hiddenMusicSlotIDs()
        )
        hitRect = compactHitRect(
            for: screen,
            leadingSlotCount: layout.leading.count,
            trailingSlotCount: layout.trailing.count,
            metrics: metrics
        )
    }

    private func pointerIsInsideIsland(_ location: CGPoint) -> Bool {
        guard state == .expanded else { return hitRect.contains(location) }
        guard let currentScreen = screen() else { return false }

        let hardwareNotch = notchRect(for: currentScreen)
        let notchSize = hardwareNotch?.size ?? metrics.compactFallbackSize
        // Balanced, matching the collar the expanded surface actually draws:
        // this rectangle is only consulted while expanded, and the expanded
        // shape keeps its neck centred.
        let compactSize = balancedCompactPillSize(
            for: compactSlotLayout(
                for: manager.compactPresentation,
                hiding: hiddenMusicSlotIDs()
            ),
            notchSize: notchSize
        )
        let expandedContentSize = expandedPanelSize(
            for: manager.expandedActivities,
            disclosedInstances: disclosedInstances(),
            registrationTimes: registrationTimes(),
            notchSize: notchSize,
            panelMetrics: metrics,
            topInset: notchSize.height
        )
        let geometry = ConnectedIslandGeometry(
            compactSize: compactSize,
            expandedContentSize: expandedContentSize
        )
        let screenFrame = geometry.expandedScreenFrame(
            in: panelFrame(for: currentScreen, metrics: metrics)
        )
        guard screenFrame.contains(location) else { return false }

        let localPoint = CGPoint(
            x: location.x - screenFrame.minX,
            y: screenFrame.maxY - location.y
        )
        return geometry.contains(
            localPoint,
            in: CGRect(origin: .zero, size: screenFrame.size)
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
        // Expanding with nothing to show would open onto a blank surface. An
        // empty compact island therefore only provides hover feedback.
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
