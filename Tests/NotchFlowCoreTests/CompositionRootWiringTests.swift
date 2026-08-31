import Foundation
import Testing

/// Asserts the app target actually assembles what the libraries provide.
///
/// The defect class this file exists to catch is not a broken unit — every unit
/// here has passing tests — it is a unit that is never constructed. No test
/// target can import the `NotchFlow` executable, so the composition root is
/// inspected as source, the same way `HookSnippetDocDriftTests` inspects
/// `docs/07-ai-integration.md`. Coarse by nature: it proves a wire exists, not
/// that it carries the right current. `scripts/check-composition-root.sh` is
/// the broad sweep; these are the named wires the audit found cut.
@Suite("Composition root wiring")
struct CompositionRootWiringTests {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func appSource(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("both IPC transports are handed the same message sink")
    func transportsShareOneSink() throws {
        let source = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(source.contains("let messageSink:"))
        #expect(source.contains("urlSchemeReceiver.onMessage = messageSink"))
        #expect(source.contains("LoopbackHTTPListener(sink: messageSink)"))

        // The register/end decision must appear once. A second occurrence means
        // a transport grew its own copy, which is how one starts registering
        // what the other ends.
        #expect(source.components(separatedBy: "activity.endsPresentation").count - 1 == 1)
    }

    @Test("the loopback listener is started and stopped from the app")
    func loopbackListenerHasALifecycle() throws {
        let source = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(source.contains("loopbackListener.updatePreferences(seededPreferences)"))
        #expect(source.contains("URLSchemeAppDelegate.onTerminate"))
        #expect(source.contains("stopSynchronously(loopbackListener)"))
    }

    @Test("the delegate forwards termination to the composition root")
    func delegateForwardsTermination() throws {
        let source = try Self.appSource("NotchFlow/URLSchemeReceiver.swift")

        #expect(source.contains("func applicationWillTerminate"))
        #expect(source.contains("Self.onTerminate?()"))
    }

    @Test("the presenter observes screen changes and repositions on them")
    func presenterObservesScreenChanges() throws {
        let source = try Self.appSource("NotchFlow/IslandPresenter.swift")

        #expect(source.contains("SystemScreenChangeObserver()"))
        #expect(source.contains("screenChanges.startObserving"))
        #expect(source.contains("controller.screenConfigurationDidChange()"))
    }

    @Test("music transport reaches the provider from the presenter")
    func musicTransportIsWired() throws {
        let presenter = try Self.appSource("NotchFlow/IslandPresenter.swift")
        let app = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(presenter.contains("musicProvider?.send(command)"))
        #expect(presenter.contains("model.onMusicTransport ="))
        #expect(app.contains("musicProvider: musicProvider"))
    }

    @Test("timer commands reach the provider, and the menu can start one")
    func timerDispatchIsWired() throws {
        let presenter = try Self.appSource("NotchFlow/IslandPresenter.swift")
        let app = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(presenter.contains("timerProvider?.handle(command.timerCommand)"))
        #expect(app.contains("timerProvider.handle("))
        #expect(app.contains("timerPresets"))

        // One instance, shared: the registry that draws the timer and the menu
        // that starts it must not hold different providers.
        #expect(app.contains("let timerProvider = TimerProvider()"))
        #expect(app.contains("timerProvider: timerProvider"))
        #expect(app.components(separatedBy: "TimerProvider()").count - 1 == 1)
    }

    @Test("the panel's visibility is reported to the timer provider")
    func panelVisibilityIsReported() throws {
        let presenter = try Self.appSource("NotchFlow/IslandPresenter.swift")

        #expect(presenter.contains("setPanelVisible(state != .hidden)"))
    }

    @Test("primary actions are dispatched by intent")
    func primaryActionsAreDispatched() throws {
        let presenter = try Self.appSource("NotchFlow/IslandPresenter.swift")

        #expect(presenter.contains("model.onPrimaryAction ="))
        #expect(presenter.contains("primaryActions.perform(intent)"))
        #expect(presenter.contains("WorkspacePrimaryActionDispatcher()"))
    }

    @Test("the presenter answers screen changes without polling")
    func presenterDoesNotPoll() throws {
        let source = try Self.appSource("NotchFlow/IslandPresenter.swift")

        // The performance contract in docs/02-performance-contract.md is the
        // reason the observer is notification-backed. A timer added here would
        // pass every behavioural test and still break the idle budget.
        #expect(!source.contains("asyncAfter"))
        #expect(!source.contains("repeats: true"))
        #expect(!source.contains("Timer.scheduledTimer"))
    }
}
