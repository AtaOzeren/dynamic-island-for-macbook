import AppKit
import NotchFlowCore
import NotchFlowProviders
import NotchFlowUI
import SwiftUI

@MainActor
final class SecondaryIslandPresentation {
    private let manager: ActivityManager
    private let metrics: PanelMetrics
    private let screen: PresentationController.ScreenProvider
    private let model: IslandViewModel
    private let panel: NotchPanel
    private let controller: PresentationController

    var onHoverChange: ((Bool) -> Void)?
    var onExpandRequest: (() -> Void)?
    var onCollapseRequest: (() -> Void)?

    init(
        manager: ActivityManager,
        metrics: PanelMetrics,
        reduceMotion: any ReduceMotionQuerying,
        screen: @escaping PresentationController.ScreenProvider,
        onMusicTransport: @escaping (MusicTransportCommand) -> Void,
        onTimerCommand: @escaping (TimerControlCommand) -> Void,
        onPrimaryAction: @escaping (ActivityIdentity) -> Void
    ) {
        self.manager = manager
        self.metrics = metrics
        self.screen = screen

        let model = IslandViewModel(
            compact: manager.compactPresentation,
            notchSize: resolvedNotchSize(screen: screen(), metrics: metrics)
        )
        self.model = model

        let panel = NotchPanel(
            metrics: metrics,
            appearance: .dark,
            content: IslandRootView(model: model)
        )
        self.panel = panel

        let controller = PresentationController(
            panel: panel,
            manager: manager,
            metrics: metrics,
            mouse: SystemMouseLocationObserver(),
            reduceMotion: reduceMotion,
            screen: screen,
            disclosedAgentIDs: { [model] in model.disclosedAgentIDs }
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
                model.hoverScale = isHovered && curve.movesGeometry ? 1.03 : 1
                model.hoverOpacity = isHovered ? 0.94 : 1
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

    func expand() {
        controller.expand()
    }

    func collapse() {
        controller.collapse()
    }

    func refreshContent() {
        model.compact = manager.compactPresentation
        model.expanded = manager.expandedActivities
        model.notchSize = resolvedNotchSize(screen: screen(), metrics: metrics)
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
