import AppKit
import KerNotchCore
import KerNotchProviders
import KerNotchUI
import SwiftUI

@MainActor
final class SecondaryIslandPresentation {
    private let manager: ActivityManager
    private let screen: PresentationController.ScreenProvider
    /// The layout for the island size picked in Settings, before it is fitted
    /// to this display.
    private var chosenLayout: IslandLayout
    private let model: IslandViewModel
    private let panel: NotchPanel
    private let controller: PresentationController

    /// The primary presenter's clocks as last pushed here. The primary owns the
    /// one wake-up, so every display ends an announcement, a paused note and a
    /// glow at the same moment instead of each keeping a clock of its own.
    private var reading = IslandPresentationClocks().reading

    var onHoverChange: ((Bool) -> Void)?
    var onExpandRequest: (() -> Void)?
    var onCollapseRequest: (() -> Void)?

    init(
        manager: ActivityManager,
        layout: IslandLayout,
        reduceMotion: any ReduceMotionQuerying,
        screen: @escaping PresentationController.ScreenProvider,
        onMusicTransport: @escaping (MusicTransportCommand) -> Void,
        onTimerCommand: @escaping (TimerControlCommand) -> Void,
        onPrimaryAction: @escaping (ActivityIdentity) -> Void
    ) {
        self.manager = manager
        self.screen = screen
        chosenLayout = layout

        let currentScreen = screen()
        let fittedLayout = layout.fitted(to: currentScreen)
        let model = IslandViewModel(
            compact: manager.compactPresentation,
            notchSize: resolvedNotchSize(screen: currentScreen, metrics: layout.panel),
            layout: fittedLayout
        )
        self.model = model

        let panel = NotchPanel(
            metrics: fittedLayout.panel,
            appearance: .dark,
            content: IslandRootView(model: model)
        )
        self.panel = panel

        let controller = PresentationController(
            panel: panel,
            manager: manager,
            layout: fittedLayout,
            mouse: SystemMouseLocationObserver(),
            reduceMotion: reduceMotion,
            screen: screen,
            disclosedInstances: { [model] in model.disclosedInstances },
            registrationTimes: { [model] in model.registrationTimes },
            hiddenMusicSlotIDs: { [model] in model.hiddenMusicSlotIDs }
        )
        self.controller = controller
        controller.automaticallyExpandsOnHover = false

        controller.onStateChange = { [weak self, weak controller, weak model] state in
            guard let self, let controller, let model else { return }
            let curve = controller.transition
            model.transitionMovesGeometry = curve.movesGeometry
            withAnimation(curve.animation) {
                model.state = state
            }
            refreshContent()
        }
        controller.onHoverChange = { [weak self, weak controller, weak model] isHovered in
            guard let self, let controller, let model else { return }
            let curve = controller.peek
            withAnimation(curve.animation) {
                model.hoverScale = isHovered && curve.movesGeometry ? IslandMotion.default.peekScale : 1
            }
            onHoverChange?(isHovered)
        }
        controller.onSynchronize = { [weak self] in
            self?.refreshContent()
        }
        model.onCollapse = { [weak self] in
            self?.requestCollapse()
        }
        model.onExpand = { [weak self] in
            self?.requestExpansion()
        }
        model.onBeginInteraction = { [weak controller] in
            controller?.beginInteractiveMode()
        }
        model.onMusicTransport = onMusicTransport
        model.onTimerCommand = onTimerCommand
        model.onPrimaryAction = onPrimaryAction
        panel.onCancel = { [weak self] in self?.requestCollapse() }
    }

    func start() {
        controller.start()
        refreshContent()
    }

    func stop() {
        controller.stop()
    }

    func suspend() {
        controller.suspend()
    }

    func screenConfigurationDidChange() {
        controller.screenConfigurationDidChange()
        refreshContent()
    }

    func applyAppearance() {
        panel.applyAppearance(.dark)
    }

    func applyLayout(_ layout: IslandLayout) {
        chosenLayout = layout
        fitLayout(to: screen())
    }

    /// Mirrors the CPU watchdog's degrade on this display. Left to the primary
    /// model alone, the other displays' working dots, equaliser and glow kept
    /// moving while the process was over budget.
    var isMotionSuspended: Bool {
        get { model.isMotionSuspended }
        set { model.isMotionSuspended = newValue }
    }

    /// Adopts the primary presenter's latest clock reading and redraws from it.
    func follow(_ reading: IslandPresentationClocks.Reading) {
        self.reading = reading
        refreshContent()
    }

    func expand() {
        controller.expand()
    }

    func collapse() {
        controller.collapse()
    }

    func refreshContent() {
        model.compact = compactPresentation(
            manager.compactPresentation,
            reconciledWith: manager.expandedActivities,
            announcementStarts: reading.announcementStarts,
            registrationTimes: manager.registrationTimes,
            now: Date()
        )
        if model.hiddenMusicSlotIDs != reading.hiddenMusicSlotIDs {
            model.hiddenMusicSlotIDs = reading.hiddenMusicSlotIDs
            controller.compactLayoutDidChange()
        }
        model.attentionGlow = reading.attentionGlow
        model.expanded = manager.expandedActivities
        model.registrationTimes = manager.registrationTimes
        let currentScreen = screen()
        model.notchSize = resolvedNotchSize(screen: currentScreen, metrics: chosenLayout.panel)
        fitLayout(to: currentScreen)
    }

    /// Keeps the drawn island, its hover silhouette and its window on the one
    /// budget this display can hold.
    private func fitLayout(to screen: ScreenDescription?) {
        let layout = chosenLayout.fitted(to: screen)
        guard model.layout != layout else { return }
        model.layout = layout
        controller.applyLayout(layout)
    }

    private func requestExpansion() {
        if let onExpandRequest {
            onExpandRequest()
        } else {
            controller.expand()
        }
        controller.beginInteractiveMode()
    }

    private func requestCollapse() {
        if let onCollapseRequest {
            onCollapseRequest()
        } else {
            controller.collapse()
        }
    }
}
