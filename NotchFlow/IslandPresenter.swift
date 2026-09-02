import AppKit
import NotchFlowCore
import NotchFlowProviders
import NotchFlowUI
import SwiftUI

/// What the island draws, as a reference the presenter can mutate in place.
///
/// `PresentationController` decides *whether* the panel is on screen;
/// this decides *what* is inside it. They are separate objects because
/// `NotchPanel` hosts its SwiftUI content once, at construction, and can never
/// be handed a new root view — so the content has to read from something that
/// outlives every state change.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published var state: PresentationState = .hidden
    @Published var compact: CompactActivityPresentation
    @Published var expanded: [any Activity] = []
    /// When each active activity registered, so the expanded panel can number
    /// the concurrent sessions of one agent in the order they appeared.
    @Published var registrationTimes: [ActivityIdentity: Date] = [:]
    /// Which agent instances are showing their sub-agents.
    ///
    /// Held here rather than inside `ExpandedActivityView` because the island's
    /// surface is sized from this model: an open list the surface cannot see is
    /// a list drawn outside it.
    @Published var disclosedInstances: Set<ActivityIdentity> = []
    /// Music icons that have finished their few seconds on screen.
    ///
    /// Held here rather than inside the view because it decides how wide the
    /// pill is, and the pill's black surface and its hover target are sized from
    /// this model. While the view owned it privately, the icon vanished and the
    /// bar behind it stayed at full width.
    @Published var hiddenMusicSlotIDs: Set<String> = []
    @Published var notchSize: CGSize
    @Published var hoverScale: CGFloat = 1
    @Published var hoverOpacity: Double = 1
    @Published var transitionMovesGeometry = true

    /// Assigned by the presenter after the controller exists. The content view
    /// is built *before* the controller — the panel's initialiser demands it —
    /// so the collapse target cannot capture the controller directly.
    var onCollapse: () -> Void = {}
    var onExpand: () -> Void = {}
    var onBeginInteraction: () -> Void = {}
    /// Where a press inside the expanded island goes. Assigned by the
    /// composition root for the same reason `onCollapse` is: the view is built
    /// before the objects that execute these commands exist, and putting a
    /// provider reference in the view would push the backend into the UI layer.
    var onMusicTransport: (MusicTransportCommand) -> Void = { _ in }
    var onTimerCommand: (TimerControlCommand) -> Void = { _ in }
    var onPrimaryAction: (ActivityIdentity) -> Void = { _ in }

    init(compact: CompactActivityPresentation, notchSize: CGSize) {
        self.compact = compact
        self.notchSize = notchSize
    }
}

/// The panel's root view: one branch per presentation state.
///
/// `.hidden` still renders — the window is ordered out rather than torn down,
/// so the hosting view stays alive and simply draws nothing.
struct IslandRootView: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        ZStack(alignment: .top) {
            // Outside the mask on purpose: this is the click-anywhere-outside
            // collapse target from `docs/04-overlay-window.md`, and it has to
            // stay live over the whole window rather than only over the island.
            if model.state == .expanded {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: model.onCollapse)
            }

            ZStack(alignment: .top) {
                if model.state != .hidden {
                    connectedSurface
                }
                content
            }
            .mask(alignment: .top) { surfaceMask }
        }
        .offset(x: compactDrawingOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scaleEffect(model.state == .compact ? model.hoverScale : 1, anchor: .top)
        .opacity(model.state == .compact ? model.hoverOpacity : 1)
        .environment(\.colorScheme, .dark)
    }

    /// The compact pill's own geometry, whose flanks are only as wide as the
    /// slots they carry.
    private var compactPill: CompactPillGeometry {
        compactPillGeometry(
            for: compactSlotLayout(for: model.compact, hiding: model.hiddenMusicSlotIDs),
            notchSize: model.notchSize
        )
    }

    /// How far to slide the island so the notch region sits on the hardware
    /// cutout.
    ///
    /// Only while compact. The panel is centred on the notch, so a pill whose
    /// flanks differ would otherwise put its opaque middle beside the cutout
    /// rather than over it. Expanded, the body is centred on the notch by
    /// design and needs no correction.
    private var compactDrawingOffset: CGFloat {
        model.state == .compact ? compactPill.drawingOffset : 0
    }

    /// The expanded surface keeps a *balanced* collar.
    ///
    /// Its neck is drawn about the shape's own centre, so feeding it the
    /// asymmetric compact width would slide the cutout off the hardware notch
    /// the moment the island opened.
    private var geometry: ConnectedIslandGeometry {
        let compactSize = balancedCompactPillSize(
            for: compactSlotLayout(for: model.compact, hiding: model.hiddenMusicSlotIDs),
            notchSize: model.notchSize
        )
        let expandedContentSize = expandedPanelSize(
            for: model.expanded,
            disclosedInstances: model.disclosedInstances,
            registrationTimes: model.registrationTimes,
            notchSize: model.notchSize,
            topInset: model.notchSize.height
        )
        return ConnectedIslandGeometry(
            compactSize: compactSize,
            expandedContentSize: expandedContentSize
        )
    }

    /// What the island currently is, surface and silhouette alike.
    private var surfaceSize: CGSize {
        model.state == .expanded ? geometry.expandedSize : compactPill.size
    }

    private var connectedSurface: some View {
        ConnectedIslandShape(geometry: geometry)
            .fill(.black)
            .frame(width: surfaceSize.width, height: surfaceSize.height)
    }

    /// The island's silhouette, clipping everything drawn inside it.
    ///
    /// A view leaving through a transition keeps its full layout size while it
    /// fades, so collapsing drew the expanded cards at their old size for a few
    /// frames after the black surface had already shrunk past them — the panel
    /// appeared to close and leave its contents hanging outside it.
    ///
    /// Reads the same geometry the surface does and sits in the same stack, so
    /// the two animate as one shape: content is trimmed to whatever the island
    /// is at that instant, and nothing can be drawn beyond its edge.
    private var surfaceMask: some View {
        ConnectedIslandShape(geometry: geometry)
            .fill(.black)
            .frame(width: surfaceSize.width, height: surfaceSize.height)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .hidden:
            Color.clear
        case .compact:
            CompactActivityView(
                presentation: model.compact,
                notchSize: model.notchSize,
                hiddenMusicSlotIDs: $model.hiddenMusicSlotIDs
            )
            .sharingIslandSurface()
            .contentShape(Rectangle())
            .onTapGesture(perform: model.onExpand)
            .transition(contentTransition)
        case .expanded:
            ZStack(alignment: .top) {
                // Inset by the notch's own height so the panel hangs below the
                // physical cutout instead of behind it: the top of the window is
                // flush with the top of the screen, so content drawn there is
                // occluded by hardware and never reaches the user.
                ExpandedActivityView(
                    activities: model.expanded,
                    registrationTimes: model.registrationTimes,
                    disclosedInstances: $model.disclosedInstances,
                    notchSize: model.notchSize,
                    topInset: model.notchSize.height,
                    onPrimaryAction: model.onPrimaryAction,
                    onMusicTransport: model.onMusicTransport,
                    onTimerCommand: model.onTimerCommand
                )
                .sharingIslandSurface()
                .padding(.top, model.notchSize.height)
                .simultaneousGesture(
                    TapGesture().onEnded(model.onBeginInteraction)
                )
            }
            .transition(contentTransition)
        }
    }

    private var contentTransition: AnyTransition {
        guard model.transitionMovesGeometry else { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
    }
}

extension TimerControlCommand {
    /// The provider command this gesture means.
    ///
    /// The mapping lives here rather than in either module because
    /// `TimerControlCommand` is a UI vocabulary and `TimerCommand` is a
    /// provider vocabulary — `NotchFlowUI` does not depend on
    /// `NotchFlowProviders`, and the composition root is the one place that
    /// sees both.
    var timerCommand: TimerCommand {
        switch self {
        case .pause: .pause
        case .resume: .resume
        case .stop: .stop
        }
    }
}

/// Wires the activity manager to the overlay window.
///
/// This is the half of the composition root `docs/01-architecture.md` calls
/// "the manager to the UI". Everything it touches — the panel, the controller,
/// the mouse observer, the screen adapter — already exists in the modules; this
/// type only assembles them and keeps the view model in step.
@MainActor
final class IslandPresenter {
    private static let primaryHoverSourceID = "notchflow.primary-display"

    private let manager: ActivityManager
    private let settingsStore: SettingsStore
    private let metrics: PanelMetrics
    private let model: IslandViewModel
    private let panel: NotchPanel
    private let controller: PresentationController
    private let reduceMotion: ConfigurableReduceMotion
    private let screenChanges: any ScreenChangeObserving
    private let musicProvider: (any MusicProvider)?
    private let timerProvider: TimerProvider?
    private let primaryActions: any PrimaryActionDispatching
    private let hoverCoordinator = SynchronizedHoverCoordinator()
    private var secondaryPresentations: [String: SecondaryIslandPresentation] = [:]

    init(
        manager: ActivityManager,
        settingsStore: SettingsStore,
        metrics: PanelMetrics = .default,
        screenChanges: any ScreenChangeObserving = SystemScreenChangeObserver(),
        musicProvider: (any MusicProvider)? = nil,
        timerProvider: TimerProvider? = nil,
        primaryActions: any PrimaryActionDispatching = WorkspacePrimaryActionDispatcher()
    ) {
        self.manager = manager
        self.settingsStore = settingsStore
        self.metrics = metrics
        self.screenChanges = screenChanges
        self.musicProvider = musicProvider
        self.timerProvider = timerProvider
        self.primaryActions = primaryActions

        let reduceMotion = ConfigurableReduceMotion(
            override: settingsStore.generalPreferences.reducedMotionOverride
        )
        self.reduceMotion = reduceMotion

        let model = IslandViewModel(
            compact: manager.compactPresentation,
            notchSize: Self.notchSize(
                metrics: metrics,
                preference: settingsStore.generalPreferences.displayTarget
            )
        )
        self.model = model

        panel = NotchPanel(
            metrics: metrics,
            appearance: .dark,
            content: IslandRootView(model: model)
        )

        // Re-read on every order-in rather than captured once, so a display
        // change or a new display-target preference lands the panel on the
        // right notch without rebuilding the controller.
        let displayTarget = { [settingsStore] in
            settingsStore.generalPreferences.displayTarget
        }
        controller = PresentationController(
            panel: panel,
            manager: manager,
            metrics: metrics,
            mouse: SystemMouseLocationObserver(),
            reduceMotion: reduceMotion,
            screen: { Self.targetScreen(preference: displayTarget()) },
            disclosedInstances: { [model] in model.disclosedInstances },
            registrationTimes: { [model] in model.registrationTimes },
            hiddenMusicSlotIDs: { [model] in model.hiddenMusicSlotIDs }
        )
        controller.automaticallyExpandsOnHover = false
    }

    func start() {
        hoverCoordinator.onExpansionChange = { [weak self] isExpanded in
            guard let self else { return }
            if isExpanded {
                expandAllPresentations()
            } else {
                collapseAllPresentations()
            }
        }
        controller.onStateChange = { [weak self] state in
            guard let self else { return }
            let curve = controller.transition
            model.transitionMovesGeometry = curve.movesGeometry
            withAnimation(curve.animation) {
                model.state = state
            }
            // The provider arms its tick only while something is on screen to
            // redraw. Nothing called this before, so a running timer never
            // refreshed its face — the same never-wired defect class this
            // audit exists to close.
            timerProvider?.setPanelVisible(state != .hidden)
            refreshContent()
        }
        controller.onHoverChange = { [weak self] isHovered in
            guard let self else { return }
            let curve = controller.peek
            withAnimation(curve.animation) {
                model.hoverScale = isHovered && curve.movesGeometry ? 1.03 : 1
                model.hoverOpacity = isHovered ? 0.94 : 1
            }
            hoverCoordinator.setHovered(
                isHovered,
                sourceID: Self.primaryHoverSourceID
            )
        }
        controller.onSynchronize = { [weak self] in
            self?.refreshContent()
        }
        model.onCollapse = { [weak self] in self?.hoverCoordinator.collapseNow() }
        model.onExpand = { [weak self] in
            self?.hoverCoordinator.expandNow()
            self?.controller.beginInteractiveMode()
        }
        model.onBeginInteraction = { [weak self] in
            self?.controller.beginInteractiveMode()
        }
        model.onMusicTransport = { [weak self] command in
            self?.musicProvider?.send(command)
        }
        model.onTimerCommand = { [weak self] command in
            self?.timerProvider?.handle(command.timerCommand)
        }
        model.onPrimaryAction = { [weak self] identity in
            self?.performPrimaryAction(for: identity)
        }
        panel.onCancel = { [weak self] in self?.hoverCoordinator.collapseNow() }

        screenChanges.startObserving { [weak self] change in
            self?.screenSetChanged(change)
        }

        controller.start()
        reconcileSecondaryPresentations()
        refreshContent()
    }

    /// Executes the intent the pressed activity's `PrimaryAction` names.
    ///
    /// The activity is looked up rather than captured because the row that was
    /// drawn may be a state behind the manager by the time the click lands —
    /// a timer that expired between draw and press must be dismissed, not
    /// paused.
    ///
    /// Timer intents go to `TimerProvider`, not to the workspace dispatcher:
    /// they are routing, not system calls, and they must take the same path
    /// the expanded view's own pause/resume controls take.
    private func performPrimaryAction(for identity: ActivityIdentity) {
        guard
            let activity = manager.activeActivities.first(where: { $0.identity == identity }),
            let intent = activity.primaryAction?.intent
        else {
            return
        }

        switch intent {
        case .pauseTimer:
            timerProvider?.handle(.pause)
        case .resumeTimer:
            timerProvider?.handle(.resume)
        case .stopTimer:
            timerProvider?.handle(.stop)
        case .openApplicationNamed, .openAgentApplication:
            primaryActions.perform(intent)
        }
    }

    /// Puts the panel back under the right notch after the screen set changes.
    ///
    /// Sleep orders out without discarding activity state. Wake/display change
    /// reconciles visibility, allowing recovery even when activity set did not
    /// mutate while screens were unavailable.
    private func screenSetChanged(_ change: ScreenChange) {
        switch change.event {
        case .systemWillSleep:
            hoverCoordinator.collapseNow()
            controller.suspend()
            for secondary in secondaryPresentations.values {
                secondary.suspend()
            }
        case .screenParametersChanged, .systemDidWake:
            reconcileSecondaryPresentations()
            controller.screenConfigurationDidChange()
            for secondary in secondaryPresentations.values {
                secondary.screenConfigurationDidChange()
            }
        }
        refreshContent()
    }

    /// Restyles the live panel. The window is never rebuilt for a scheme change,
    /// so an appearance switch while the island is expanded does not blink it
    /// out and back.
    func applyAppearance(_: SettingsAppearance) {
        panel.applyAppearance(.dark)
        for secondary in secondaryPresentations.values {
            secondary.applyAppearance()
        }
    }

    func applyReducedMotion(_ preferenceOverride: Bool?) {
        reduceMotion.updateOverride(preferenceOverride)
    }

    func applyDisplayTarget() {
        controller.screenConfigurationDidChange()
        reconcileSecondaryPresentations()
        refreshContent()
    }

    private func refreshContent() {
        model.compact = manager.compactPresentation
        model.expanded = manager.expandedActivities
        model.registrationTimes = manager.registrationTimes
        model.notchSize = Self.notchSize(
            metrics: metrics,
            preference: settingsStore.generalPreferences.displayTarget
        )
        for secondary in secondaryPresentations.values {
            secondary.refreshContent()
        }
        hoverCoordinator.updateExpansionAvailability(
            manager.activeActivities.isEmpty == false
        )
    }

    private func reconcileSecondaryPresentations() {
        let preference = settingsStore.generalPreferences.displayTarget
        let displays = NSScreen.screens.map(DisplayDescription.init)
        let primaryDisplay = selectDisplay(from: displays, preference: preference)
        let secondaryDisplays =
            preference == .allDisplays
            ? selectDisplays(from: displays, preference: preference).filter {
                $0.identifier != primaryDisplay?.identifier
            }
            : []
        let targetIdentifiers = Set(secondaryDisplays.map(\.identifier))

        for identifier in Array(secondaryPresentations.keys)
        where !targetIdentifiers.contains(identifier) {
            guard let secondary = secondaryPresentations.removeValue(forKey: identifier) else {
                continue
            }
            secondary.stop()
            hoverCoordinator.removeSource(identifier)
        }

        for display in secondaryDisplays where secondaryPresentations[display.identifier] == nil {
            let identifier = display.identifier
            let secondary = SecondaryIslandPresentation(
                manager: manager,
                metrics: metrics,
                reduceMotion: reduceMotion,
                screen: { Self.screen(identifier: identifier) },
                onMusicTransport: { [weak self] command in
                    self?.musicProvider?.send(command)
                },
                onTimerCommand: { [weak self] command in
                    self?.timerProvider?.handle(command.timerCommand)
                },
                onPrimaryAction: { [weak self] identity in
                    self?.performPrimaryAction(for: identity)
                }
            )
            secondary.onHoverChange = { [weak self] isHovered in
                self?.hoverCoordinator.setHovered(
                    isHovered,
                    sourceID: identifier
                )
            }
            secondary.onExpandRequest = { [weak self] in
                self?.hoverCoordinator.expandNow()
            }
            secondary.onCollapseRequest = { [weak self] in
                self?.hoverCoordinator.collapseNow()
            }
            secondaryPresentations[identifier] = secondary
            secondary.start()
            if hoverCoordinator.isExpanded {
                secondary.expand()
            }
        }
    }

    private func expandAllPresentations() {
        controller.expand()
        for secondary in secondaryPresentations.values {
            secondary.expand()
        }
    }

    private func collapseAllPresentations() {
        controller.collapse()
        for secondary in secondaryPresentations.values {
            secondary.collapse()
        }
    }

    /// The screen the island belongs on, resolved through the same
    /// `selectDisplay` rule the Settings pane shows the user.
    private static func targetScreen(preference: DisplayPreference) -> ScreenDescription? {
        let screens = NSScreen.screens
        guard
            let selection = selectDisplay(
                from: screens.map(DisplayDescription.init),
                preference: preference
            ),
            let screen = screens.first(where: {
                DisplayDescription($0).identifier == selection.identifier
            })
                ?? screens.first
        else {
            return nil
        }
        return ScreenDescription(screen)
    }

    private static func screen(identifier: String) -> ScreenDescription? {
        NSScreen.screens.first {
            DisplayDescription($0).identifier == identifier
        }.map(ScreenDescription.init)
    }

    /// The hardware notch's size, or the fallback pill size on a screen that has
    /// none — the degraded mode from `docs/03-display-and-notch.md`, not an
    /// error state.
    private static func notchSize(
        metrics: PanelMetrics,
        preference: DisplayPreference
    ) -> CGSize {
        resolvedNotchSize(screen: targetScreen(preference: preference), metrics: metrics)
    }
}

func resolvedNotchSize(screen: ScreenDescription?, metrics: PanelMetrics) -> CGSize {
    guard
        let screen,
        let rect = notchRect(
            frame: screen.frame,
            safeAreaInsets: screen.safeAreaInsets,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    else {
        return metrics.compactFallbackSize
    }
    return rect.size
}
