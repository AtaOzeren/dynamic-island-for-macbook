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
                ExpandedActivityView(activities: model.expanded)
            }
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

    init(
        manager: ActivityManager,
        settingsStore: SettingsStore,
        metrics: PanelMetrics = .default
    ) {
        self.manager = manager
        self.settingsStore = settingsStore
        self.metrics = metrics

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
            self?.refreshContent()
        }
        controller.onSynchronize = { [weak self] in
            self?.refreshContent()
        }
        model.onExpand = { [weak self] in self?.controller.expand() }
        model.onCollapse = { [weak self] in self?.controller.collapse() }

        controller.start()
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
