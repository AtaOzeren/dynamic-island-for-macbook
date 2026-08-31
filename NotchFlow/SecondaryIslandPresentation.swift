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
            screen: screen
        )
        self.controller = controller

        controller.onStateChange = { [weak self, weak controller, weak model] state in
            guard let self, let controller, let model else { return }
            let curve = controller.transition
            model.transitionMovesGeometry = curve.movesGeometry
            withAnimation(curve.animation) {
                model.state = state
            }
            refreshContent()
        }
        controller.onHoverChange = { [weak controller, weak model] isHovered in
            guard let controller, let model else { return }
            let curve = controller.peek
            withAnimation(curve.animation) {
                model.hoverScale = isHovered && curve.movesGeometry ? 1.03 : 1
                model.hoverOpacity = isHovered ? 0.94 : 1
            }
        }
        controller.onSynchronize = { [weak self] in
            self?.refreshContent()
        }
        model.onCollapse = { [weak controller] in controller?.collapse() }
        model.onExpand = { [weak controller] in
            controller?.expand()
            controller?.beginInteractiveMode()
        }
        model.onBeginInteraction = { [weak controller] in
            controller?.beginInteractiveMode()
        }
        model.onMusicTransport = onMusicTransport
        model.onTimerCommand = onTimerCommand
        model.onPrimaryAction = onPrimaryAction
        panel.onCancel = { [weak controller] in controller?.collapse() }
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

    func refreshContent() {
        model.compact = manager.compactPresentation
        model.expanded = manager.expandedActivities
        model.notchSize = resolvedNotchSize(screen: screen(), metrics: metrics)
    }
}
