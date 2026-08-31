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
    @Published var notchSize: CGSize

    /// Assigned by the presenter after the controller exists. The content view
    /// is built *before* the controller — the panel's initialiser demands it —
    /// so the pill's tap target cannot capture the controller directly.
    var onExpand: () -> Void = {}
    var onCollapse: () -> Void = {}

    /// Where a press inside the expanded island goes. Assigned by the
    /// composition root for the same reason `onExpand` is: the view is built
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
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .hidden:
            Color.clear
        case .compact:
            CompactActivityView(presentation: model.compact, notchSize: model.notchSize)
                .contentShape(Rectangle())
                .onTapGesture(perform: model.onExpand)
        case .expanded:
            // The collapse target is the empty space around the detail, per
            // `docs/04-overlay-window.md`: while expanded the panel accepts the
            // mouse across its whole frame, and a click that misses the content
            // is the gesture that closes it.
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: model.onCollapse)
                ExpandedActivityView(
                    activities: model.expanded,
                    onPrimaryAction: model.onPrimaryAction,
                    onMusicTransport: model.onMusicTransport,
                    onTimerCommand: model.onTimerCommand
                )
            }
        }
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
    private let manager: ActivityManager
    private let settingsStore: SettingsStore
    private let metrics: PanelMetrics
    private let model: IslandViewModel
    private let panel: NotchPanel
    private let controller: PresentationController
    private let screenChanges: any ScreenChangeObserving
    private let musicProvider: (any MusicProvider)?
    private let timerProvider: TimerProvider?
    private let primaryActions: any PrimaryActionDispatching

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
            appearance: settingsStore.generalPreferences.appearance,
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
            screen: { Self.targetScreen(preference: displayTarget()) }
        )
    }

    func start() {
        controller.onStateChange = { [weak self] state in
            self?.model.state = state
            // The provider arms its tick only while something is on screen to
            // redraw. Nothing called this before, so a running timer never
            // refreshed its face — the same never-wired defect class this
            // audit exists to close.
            self?.timerProvider?.setPanelVisible(state != .hidden)
            self?.refreshContent()
        }
        controller.onSynchronize = { [weak self] in
            self?.refreshContent()
        }
        model.onExpand = { [weak self] in self?.controller.expand() }
        model.onCollapse = { [weak self] in self?.controller.collapse() }
        model.onMusicTransport = { [weak self] command in
            self?.musicProvider?.send(command)
        }
        model.onTimerCommand = { [weak self] command in
            self?.timerProvider?.handle(command.timerCommand)
        }
        model.onPrimaryAction = { [weak self] identity in
            self?.performPrimaryAction(for: identity)
        }

        screenChanges.startObserving { [weak self] change in
            self?.screenSetChanged(change)
        }

        controller.start()
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
    /// `.systemWillSleep` is deliberately ignored. Repositioning against a
    /// display list that is about to be torn down resolves nothing, and
    /// ordering the panel out here would desynchronise `PresentationController`
    /// from the manager's active set — it only orders back in when the active
    /// set changes, so an activity that is still running across the sleep would
    /// never come back.
    ///
    /// `.systemDidWake` needs no delay. `docs/03-display-and-notch.md:66` states
    /// the contract: while the display list is still settling nothing resolves,
    /// and the `didChangeScreenParametersNotification` that follows is what
    /// reflects the final geometry. Both events land here, so the wake attempt
    /// is either correct or a no-op, and the parameters change that follows is
    /// authoritative either way.
    private func screenSetChanged(_ change: ScreenChange) {
        guard change.event != .systemWillSleep else { return }
        controller.repositionOnCurrentScreen()
        refreshContent()
    }

    /// Restyles the live panel. The window is never rebuilt for a scheme change,
    /// so an appearance switch while the island is expanded does not blink it
    /// out and back.
    func applyAppearance(_ appearance: SettingsAppearance) {
        panel.applyAppearance(appearance)
    }

    private func refreshContent() {
        model.compact = manager.compactPresentation
        model.expanded = manager.expandedActivities
        model.notchSize = Self.notchSize(
            metrics: metrics,
            preference: settingsStore.generalPreferences.displayTarget
        )
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
            let screen = screens.first(where: { $0.localizedName == selection.name })
                ?? screens.first
        else {
            return nil
        }
        return ScreenDescription(screen)
    }

    /// The hardware notch's size, or the fallback pill size on a screen that has
    /// none — the degraded mode from `docs/03-display-and-notch.md`, not an
    /// error state.
    private static func notchSize(
        metrics: PanelMetrics,
        preference: DisplayPreference
    ) -> CGSize {
        guard
            let screen = targetScreen(preference: preference),
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
}
