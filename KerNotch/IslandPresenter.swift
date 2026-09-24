import AppKit
import KerNotchCore
import KerNotchProviders
import KerNotchUI
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
    /// Music icons taken off the pill: paused notes whose time on screen is up.
    ///
    /// Held here rather than inside the view because it decides how wide the
    /// pill is, and the pill's black surface and its hover target are sized from
    /// this model. While the view owned it privately, the icon vanished and the
    /// bar behind it stayed at full width.
    @Published var hiddenMusicSlotIDs: Set<String> = []
    /// The pet on the compact island, and the routine it is performing.
    ///
    /// Published rather than kept in the view for the reason the music icons
    /// are: the pet keeps the leading flank open, which decides how wide the
    /// pill and its hover target are — and the compact view is rebuilt on every
    /// expand and collapse, which would start the routine over each time.
    @Published var pet: IslandPetPresentation?
    /// The light around the compact island while an agent has news.
    ///
    /// Published rather than derived in the view because it is anchored to the
    /// moment the news was first seen, which no view outlives: the compact view
    /// is rebuilt every time the island expands and collapses.
    @Published var attentionGlow: IslandAttentionGlow?
    @Published var notchSize: CGSize
    /// The island size the user picked, as the metrics the expanded surface is
    /// drawn with. Published so a change in Settings redraws an open island.
    @Published var layout: IslandLayout
    @Published var hoverScale: CGFloat = 1
    /// How the change being drawn right now is animated.
    ///
    /// Published rather than decided in the view because the island's shape and
    /// its contents move on one clock, and only the presenter — which sees the
    /// island's size before and after a change — knows which way it is moving.
    @Published var contentMotion: IslandContentMotion = .still
    @Published var transitionMovesGeometry = true
    /// Set only by the CPU watchdog's degrade action, to stand the island's
    /// continuous motion still while the process is over budget.
    @Published var isMotionSuspended = false
    /// KerNotch's own Motion choice from the General pane, `nil` to follow the
    /// system. SwiftUI's reduce-motion value is the system's alone, so the
    /// choice reaches the views that honour it through the environment.
    @Published var reducedMotionOverride: Bool?

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

    init(compact: CompactActivityPresentation, notchSize: CGSize, layout: IslandLayout) {
        self.compact = compact
        self.notchSize = notchSize
        self.layout = layout
    }

    /// Everything that decides how big the island is drawn, as the view draws it
    /// now. `extentInput(compact:hiddenMusicSlotIDs:pet:expanded:)` answers the
    /// same question for a change that has not been applied yet.
    var extentInput: IslandExtentInput {
        extentInput(
            compact: compact,
            hiddenMusicSlotIDs: hiddenMusicSlotIDs,
            pet: pet?.pet,
            expanded: expanded
        )
    }

    func extentInput(
        compact: CompactActivityPresentation,
        hiddenMusicSlotIDs: Set<String>,
        pet: IslandPet?,
        expanded: [any Activity]
    ) -> IslandExtentInput {
        IslandExtentInput(
            state: state,
            compact: compact,
            hiddenMusicSlotIDs: hiddenMusicSlotIDs,
            pet: pet,
            expanded: expanded,
            disclosedInstances: disclosedInstances,
            registrationTimes: registrationTimes,
            notchSize: notchSize,
            layout: layout
        )
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

            attentionGlow

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
        .scaleEffect(peekScale, anchor: .top)
        .environment(\.islandHoverScale, peekScale)
        .environment(\.colorScheme, .dark)
        .environment(\.islandContentMotion, model.contentMotion)
        .environment(\.islandMotionSuspended, model.isMotionSuspended)
        .environment(\.islandReducedMotionOverride, model.reducedMotionOverride)
    }

    /// The hover peek's scale, which only the compact island has.
    private var peekScale: CGFloat {
        model.state == .compact ? model.hoverScale : 1
    }

    /// The compact pill's own geometry, whose flanks are only as wide as the
    /// slots they carry — apart from the pet's, which keeps its full width.
    private var compactPill: CompactPillGeometry {
        islandCompactPillGeometry(model.extentInput)
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

    private var geometry: ConnectedIslandGeometry {
        islandConnectedGeometry(model.extentInput)
    }

    private var surfaceSize: CGSize {
        islandSurfaceSize(model.extentInput)
    }

    /// Outside the mask, which would clip the halo to the island, and behind the
    /// surface, which hides the rim's inner half so the pill stays black.
    private var attentionGlow: some View {
        ZStack(alignment: .top) {
            if model.state == .compact, let glow = model.attentionGlow {
                IslandAttentionGlowView(
                    glow: glow,
                    surfaceSize: ConnectedIslandGeometry.compactSurfaceSize(forPillSize: compactPill.size)
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: IslandAttentionGlowTiming.fadeDuration), value: model.attentionGlow)
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
                hiddenMusicSlotIDs: model.hiddenMusicSlotIDs,
                pet: model.pet
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
                    metrics: model.layout.items,
                    panelMetrics: model.layout.panel,
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
    /// provider vocabulary — `KerNotchUI` does not depend on
    /// `KerNotchProviders`, and the composition root is the one place that
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
    private static let primaryHoverSourceID = "kernotch.primary-display"

    private let manager: ActivityManager
    private let settingsStore: SettingsStore
    /// The layout for the island size picked in Settings, before it is fitted
    /// to the screen the island is on.
    private var chosenLayout: IslandLayout
    private let model: IslandViewModel
    private let panel: NotchPanel
    private let controller: PresentationController
    private let reduceMotion: ConfigurableReduceMotion
    private let screenChanges: any ScreenChangeObserving
    private let musicProvider: (any MusicProvider)?
    private let timerProvider: TimerProvider?
    private let discordVoice: (any DiscordVoiceChannelLeaving)?
    private let primaryActions: any PrimaryActionDispatching
    private let screenConfigurationSettled: @MainActor ([DisplayDescription]) -> Void
    private let hoverCoordinator = SynchronizedHoverCoordinator()
    private var clocks = IslandPresentationClocks()
    /// The pet the Pet tab puts on the island, or `nil` while it is off. Only
    /// the primary island has one: a pet is a companion, and a second one on
    /// another display would be a copy, not company.
    private var pet: IslandPet?
    /// The routine the pet is performing, carried across every refresh so a
    /// stage change starts from wherever the pet actually is.
    private var petRoutines = PetRoutineTracker()
    private var presentationRefreshTask: Task<Void, Never>?
    private var isDegraded = false
    /// The user's own motion preference, held for the length of one watchdog
    /// episode because degrading overwrites the same override it is stored in.
    private var preDegradeReducedMotionOverride: Bool?
    private var secondaryPresentations: [String: SecondaryIslandPresentation] = [:]

    init(
        manager: ActivityManager,
        settingsStore: SettingsStore,
        screenChanges: any ScreenChangeObserving = SystemScreenChangeObserver(),
        musicProvider: (any MusicProvider)? = nil,
        timerProvider: TimerProvider? = nil,
        discordVoice: (any DiscordVoiceChannelLeaving)? = nil,
        primaryActions: any PrimaryActionDispatching = WorkspacePrimaryActionDispatcher(),
        screenConfigurationSettled: @escaping @MainActor ([DisplayDescription]) -> Void = { _ in }
    ) {
        self.manager = manager
        self.settingsStore = settingsStore
        let chosenLayout = IslandLayout(size: settingsStore.generalPreferences.islandSize)
        self.chosenLayout = chosenLayout
        pet = settingsStore.petPreferences.pet
        self.screenChanges = screenChanges
        self.musicProvider = musicProvider
        self.timerProvider = timerProvider
        self.discordVoice = discordVoice
        self.primaryActions = primaryActions
        self.screenConfigurationSettled = screenConfigurationSettled

        let reduceMotion = ConfigurableReduceMotion(
            override: settingsStore.generalPreferences.reducedMotionOverride
        )
        self.reduceMotion = reduceMotion

        let targetScreen = Self.targetScreen(preference: settingsStore.generalPreferences.displayTarget)
        let layout = chosenLayout.fitted(to: targetScreen)
        let model = IslandViewModel(
            compact: manager.compactPresentation,
            notchSize: resolvedNotchSize(screen: targetScreen, metrics: layout.panel),
            layout: layout
        )
        model.reducedMotionOverride = settingsStore.generalPreferences.reducedMotionOverride
        self.model = model

        panel = NotchPanel(
            metrics: layout.panel,
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
            layout: layout,
            mouse: SystemMouseLocationObserver(),
            reduceMotion: reduceMotion,
            screen: { Self.targetScreen(preference: displayTarget()) },
            disclosedInstances: { [model] in model.disclosedInstances },
            registrationTimes: { [model] in model.registrationTimes },
            hiddenMusicSlotIDs: { [model] in model.hiddenMusicSlotIDs },
            pet: { [model] in model.pet?.pet }
        )
        controller.automaticallyExpandsOnHover = false
        clocks.showsAttentionGlow = settingsStore.aiIntegrationPreferences.showsAttentionGlow
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
                model.hoverScale = isHovered && curve.movesGeometry ? IslandMotion.default.peekScale : 1
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

        // Filled in while the panel is still ordered out, so it is ordered in
        // at its resting size. Filled in after, the first refresh met an island
        // already compact and grew it on a spring — with the pet on, sliding
        // the whole island sideways onto its new offset at every launch.
        refreshContent()
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
    /// the expanded view's own pause/resume controls take. Leaving a Discord
    /// channel is routing for the same reason: it is a command to the RPC
    /// connection that reported the channel.
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
        case .leaveDiscordVoiceChannel:
            discordVoice?.leaveVoiceChannel()
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
            screenConfigurationSettled(change.displays)
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

    /// Resizes the island on every display to the size picked in Settings,
    /// without rebuilding a window — an open island redraws at the new size.
    func applyIslandSize(_ size: IslandSize) {
        let chosenLayout = IslandLayout(size: size)
        guard chosenLayout != self.chosenLayout else { return }
        self.chosenLayout = chosenLayout
        fitLayout(to: Self.targetScreen(preference: settingsStore.generalPreferences.displayTarget))
        for secondary in secondaryPresentations.values {
            secondary.applyLayout(chosenLayout)
        }
    }

    /// Keeps the drawn island, its hover silhouette and its window on the one
    /// budget the screen it is on can hold.
    private func fitLayout(to screen: ScreenDescription?) {
        let layout = chosenLayout.fitted(to: screen)
        guard model.layout != layout else { return }
        model.layout = layout
        controller.applyLayout(layout)
    }

    func applyReducedMotion(_ preferenceOverride: Bool?) {
        reduceMotion.updateOverride(preferenceOverride)
        model.reducedMotionOverride = preferenceOverride
        for secondary in secondaryPresentations.values {
            secondary.reducedMotionOverride = preferenceOverride
        }
    }

    /// Puts the pet on the island or takes it off, as the Pet tab says. The
    /// pill widens or narrows with it on every change, like an icon arriving.
    func applyPetPreferences(_ preferences: PetPreferences) {
        guard preferences.pet != pet else { return }
        pet = preferences.pet
        refreshContent()
    }

    /// Plays the glow once around the island, for the Settings test button.
    func previewAttentionGlow() {
        clocks.previewAttentionGlow(at: Date())
        refreshContent()
    }

    /// Takes the AI Integrations glow switch into effect at once, on every
    /// display — a glow running when it is switched off disappears.
    func applyAttentionGlowPreference(_ showsAttentionGlow: Bool) {
        guard clocks.showsAttentionGlow != showsAttentionGlow else { return }
        clocks.showsAttentionGlow = showsAttentionGlow
        refreshContent()
    }

    /// What degrading did, as one value the watchdog's tests can compare.
    ///
    /// `presentationState` is in here because the pointer is only observed while
    /// the panel is on screen: a degrade that left the island hidden would be a
    /// degrade that silently stopped answering the mouse.
    var motionState: MotionState {
        MotionState(
            isDegraded: isDegraded,
            isMotionSuspended: model.isMotionSuspended,
            reducedMotionOverride: reduceMotion.preferenceOverride,
            presentationState: controller.state
        )
    }

    struct MotionState: Equatable {
        let isDegraded: Bool
        let isMotionSuspended: Bool
        let reducedMotionOverride: Bool?
        let presentationState: PresentationState
    }

    /// Stands the island's motion down while the CPU watchdog says the process
    /// is over budget: no travelling dot, no animated transitions, nothing open.
    ///
    /// The pointer keeps being watched on purpose. An island that stops
    /// answering hover and clicks reads as a crashed app, which is the report
    /// the watchdog exists to prevent, and mouse tracking is not what burns the
    /// CPU. Idempotent: the user's own motion preference is captured on the
    /// first call only, so a second degrade cannot overwrite it with the
    /// override this method itself installed.
    @MainActor
    func enterDegradedMode() {
        guard isDegraded == false else { return }
        isDegraded = true
        preDegradeReducedMotionOverride = reduceMotion.preferenceOverride

        model.isMotionSuspended = true
        for secondary in secondaryPresentations.values {
            secondary.isMotionSuspended = true
        }
        applyReducedMotion(true)
        hoverCoordinator.collapseNow()
    }

    /// The exact reverse, including handing the motion preference back to the
    /// user unchanged — someone who had already forced Reduce Motion on must
    /// not find it off because a watchdog episode ended.
    @MainActor
    func exitDegradedMode() {
        guard isDegraded else { return }
        isDegraded = false

        model.isMotionSuspended = false
        for secondary in secondaryPresentations.values {
            secondary.isMotionSuspended = false
        }
        applyReducedMotion(preDegradeReducedMotionOverride)
        preDegradeReducedMotionOverride = nil
    }

    /// Says on the island that the last run ended in a watchdog restart or
    /// quit, through the same announcement path every other activity uses.
    ///
    /// Registered rather than drawn directly so it expires the way news does:
    /// auto-dismiss takes it off the pill and out of the model, without the
    /// presenter holding a timer of its own.
    @MainActor
    func announceWatchdogNotice(didRelaunch: Bool) {
        manager.register(WatchdogNoticeActivity(didRelaunch: didRelaunch))
    }

    func applyDisplayTarget() {
        controller.screenConfigurationDidChange()
        reconcileSecondaryPresentations()
        refreshContent()
    }

    /// Wakes the island when the next clock-driven change is due.
    ///
    /// `refreshContent` is driven by events — an activity registering, the
    /// pointer moving, the panel changing state. A blocked agent that failed
    /// once and went quiet, a track left paused, or a glow running its course
    /// produce none of those, so without a deadline to sleep on the pill would
    /// stay red, keep the note, or keep glowing until something unrelated
    /// happened.
    ///
    /// Self-limiting: once a deadline passes, the refresh it triggers finds it
    /// elapsed and schedules only what remains.
    private func schedulePresentationRefresh(after now: Date) {
        presentationRefreshTask?.cancel()
        presentationRefreshTask = nil

        guard let deadline = clocks.nextDeadline else { return }

        presentationRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(deadline.timeIntervalSince(now)))
            guard Task.isCancelled == false else { return }
            self?.refreshContent()
        }
    }

    private func refreshContent() {
        let now = Date()
        clocks.advance(
            activities: manager.expandedActivities,
            registrationTimes: manager.registrationTimes,
            now: now
        )
        let reading = clocks.reading
        let compact = compactPresentation(
            manager.compactPresentation,
            reconciledWith: manager.expandedActivities,
            announcementStarts: reading.announcementStarts,
            registrationTimes: manager.registrationTimes,
            now: now
        )
        applyContent(
            compact: compact,
            hiddenMusicSlotIDs: reading.hiddenMusicSlotIDs,
            pet: petPresentation(
                beside: compactSlotLayout(for: compact, hiding: reading.hiddenMusicSlotIDs, housing: pet)
            ),
            expanded: manager.expandedActivities,
            registrationTimes: manager.registrationTimes
        )
        model.attentionGlow = reading.attentionGlow
        let targetScreen = Self.targetScreen(preference: settingsStore.generalPreferences.displayTarget)
        model.notchSize = resolvedNotchSize(screen: targetScreen, metrics: chosenLayout.panel)
        fitLayout(to: targetScreen)
        schedulePresentationRefresh(after: now)
        for secondary in secondaryPresentations.values {
            secondary.follow(reading)
        }
        hoverCoordinator.updateExpansionAvailability(
            manager.activeActivities.isEmpty == false
        )
    }

    /// Puts what the island shows on screen, as one movement.
    ///
    /// The island's shape and its contents used to change on two clocks: the
    /// icons carried their own animation while the black surface behind them,
    /// the mask that clips it and its offset onto the notch were assigned
    /// outright. An icon arriving therefore read as the island snapping wider
    /// and the glyph catching up, and an icon leaving was clipped in half by a
    /// pill that had already closed over it.
    ///
    /// One transaction is the fix, and which way the island is about to move is
    /// what decides who waits for whom — so the size is measured before and
    /// after the change rather than guessed from what happened to arrive.
    private func applyContent(
        compact: CompactActivityPresentation,
        hiddenMusicSlotIDs: Set<String>,
        pet: IslandPetPresentation?,
        expanded: [any Activity],
        registrationTimes: [ActivityIdentity: Date]
    ) {
        let narrowsPill = model.hiddenMusicSlotIDs != hiddenMusicSlotIDs
        let resizesFlank = model.pet?.pet != pet?.pet
        let motion = islandContentMotion(
            in: model.state,
            change: islandExtentChange(
                from: islandSurfaceSize(model.extentInput),
                to: islandSurfaceSize(
                    model.extentInput(
                        compact: compact,
                        hiddenMusicSlotIDs: hiddenMusicSlotIDs,
                        pet: pet?.pet,
                        expanded: expanded
                    )
                )
            ),
            reduceMotion: reduceMotion.prefersReducedMotion,
            isMotionSuspended: model.isMotionSuspended
        )

        model.contentMotion = motion
        withAnimation(motion.container) {
            model.compact = compact
            model.hiddenMusicSlotIDs = hiddenMusicSlotIDs
            model.pet = pet
            model.expanded = expanded
            model.registrationTimes = registrationTimes
        }

        // Narrowing the pill has to narrow its hover target too, and nothing
        // else tells the controller when an icon leaves on a clock or the pet
        // is switched on or off.
        if narrowsPill || resizesFlank {
            controller.compactLayoutDidChange()
        }
    }

    /// Moves the pet onto the stage the icons leave it and hands back the
    /// routine it performs there, or `nil` while there is no pet.
    ///
    /// Only a change of stage starts a new routine, so this is free to run on
    /// every refresh: the routine plays itself out in Core Animation, and
    /// nothing here wakes the island to keep it going.
    ///
    /// Timed by uptime rather than by the wall clock `refreshContent` reads:
    /// uptime is the clock Core Animation plays the routine on.
    private func petPresentation(beside layout: CompactSlotLayout) -> IslandPetPresentation? {
        guard let pet, let stage = layout.petStage else {
            petRoutines.forget()
            return nil
        }
        petRoutines.follow(stage, at: ProcessInfo.processInfo.systemUptime, geometry: pet.stageGeometry())
        return petRoutines.performance.map { IslandPetPresentation(pet: pet, performance: $0) }
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
                layout: chosenLayout,
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
            secondary.isMotionSuspended = isDegraded
            secondary.reducedMotionOverride = reduceMotion.preferenceOverride
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

    static func screen(identifier: String) -> ScreenDescription? {
        NSScreen.screens.first {
            DisplayDescription($0).identifier == identifier
        }.map(ScreenDescription.init)
    }
}

/// The hardware notch's size, or the fallback pill size on a screen that has
/// none — the degraded mode from `docs/03-display-and-notch.md`, not an error
/// state.
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
