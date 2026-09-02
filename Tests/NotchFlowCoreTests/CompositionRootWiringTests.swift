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

    /// The expanded panel must be handed the registration times that number an
    /// agent's concurrent sessions.
    ///
    /// The numbering function defaults to an empty table, so a presenter that
    /// never publishes the times still compiles and still draws — it just draws
    /// two cards both called "OpenCode", which is the thing the numbers exist to
    /// prevent. Only the wiring can catch that.
    @Test("the expanded panel is handed the session registration times")
    func expandedPanelReceivesRegistrationTimes() throws {
        for presenter in ["NotchFlow/IslandPresenter.swift", "NotchFlow/SecondaryIslandPresentation.swift"] {
            let source = try Self.appSource(presenter)
            #expect(
                source.contains("model.registrationTimes = manager.registrationTimes"),
                "\(presenter) never refreshes the registration times"
            )
        }

        let primary = try Self.appSource("NotchFlow/IslandPresenter.swift")
        #expect(primary.contains("@Published var registrationTimes"))
        #expect(primary.contains("registrationTimes: model.registrationTimes"))
    }

    /// The pill's icons, the black bar behind them, and the hover target must
    /// all be sized from the same set of visible slots.
    ///
    /// A music icon leaves after a few seconds. While that timer lived as
    /// private state inside `CompactActivityView`, only the icons shrank: the
    /// bar kept the width of a slot that was no longer drawn, and the hover
    /// target kept reporting the pointer as over an island that had moved out
    /// from under it. The filtering functions were always correct — nothing was
    /// passing them the set — so only the wiring can catch this.
    @Test("the pill, its surface and its hover target share one visible slot set")
    func compactPillFollowsHiddenMusicIcons() throws {
        let presenter = try Self.appSource("NotchFlow/IslandPresenter.swift")

        // One owner, read by the surface and bound into the view.
        #expect(presenter.contains("@Published var hiddenMusicSlotIDs"))
        #expect(presenter.contains("hiddenMusicSlotIDs: $model.hiddenMusicSlotIDs"))
        #expect(
            presenter.contains(
                "compactSlotLayout(for: model.compact, hiding: model.hiddenMusicSlotIDs)"
            )
        )
        // And handed to the controller, which owns the hover target.
        #expect(presenter.contains("hiddenMusicSlotIDs: { [model] in model.hiddenMusicSlotIDs }"))

        // Nothing may size the compact pill from the unfiltered presentation.
        #expect(!presenter.contains("compactPillGeometry(for: model.compact,"))
        #expect(!presenter.contains("balancedCompactPillSize(\n            for: model.compact,"))
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

    @Test("AI preference switches persist through one synchronous write path")
    func aiPreferencesHaveOneWritePath() throws {
        let source = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(source.contains("onAIPreferencesChange: applyAIPreferences"))
        #expect(source.contains("private func applyAIPreferences("))
        #expect(source.contains("settingsStore.aiIntegrationPreferences = preferences"))
        #expect(source.contains("urlSchemeReceiver.preferences = preferences"))
        #expect(!source.contains(".onChange(of: aiPreferences"))
    }

    @Test("the loopback listener is started and stopped from the app")
    func loopbackListenerHasALifecycle() throws {
        let source = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(source.contains("loopbackListener.updatePreferences(seededPreferences)"))
        #expect(source.contains("URLSchemeAppDelegate.onTerminate"))
        #expect(source.contains("stopSynchronously(loopbackListener)"))
    }

    @Test("the app owns one user-controlled AppKit status item")
    func appOwnsUserControlledStatusItem() throws {
        let source = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(source.contains("StatusItemPresenter("))
        #expect(source.contains("NSStatusBar.system.statusItem"))
        #expect(source.contains("statusItem.isVisible = true"))
        #expect(source.contains("NSImage(named: \"MenuBarIcon\")"))

        // The item is added once AppKit has finished launching, and re-added
        // when the display arrangement changes. Neither an autosaved visibility
        // flag the app never reads back, nor a toggle of `isVisible` to force a
        // redraw, may come back: both produced an item that reported itself
        // visible while the menu bar drew nothing.
        #expect(source.contains("URLSchemeAppDelegate.onDidFinishLaunching"))
        #expect(source.contains("didChangeScreenParametersNotification"))
        #expect(!source.contains("statusItem.autosaveName ="))
        #expect(!source.contains("statusItem.isVisible = false"))
        #expect(!source.contains("visibilityRestorationTask"))
        #expect(source.contains("systemSymbolName: \"capsule.fill\""))
        #expect(source.contains("setAccessibilityLabel(\"NotchFlow\")"))
        #expect(source.contains("statusItemPresenter.setVisible(preferences.showMenuBarIcon)"))
        #expect(source.contains("$isSettingsActionBridgeInserted"))
        #expect(source.contains("isSettingsActionBridgeInserted = false"))
        #expect(!source.contains("isInserted: .constant(true)"))
        #expect(source.contains("SettingsActionBridge("))
    }

    @Test("a language change can relaunch the app from Settings")
    func languageChangeCanRelaunchTheApp() throws {
        let source = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(source.contains("appliedLanguageOverride"))
        #expect(source.contains("languageOverride != appliedLanguageOverride"))
        #expect(source.contains("onRestart: restartApplication"))
        #expect(source.contains("NSWorkspace.OpenConfiguration()"))
        #expect(source.contains("createsNewApplicationInstance = true"))
        #expect(source.contains("NSApp.terminate(nil)"))
    }

    @Test("reopening the running accessory app opens Settings")
    func appReopenOpensSettings() throws {
        let delegateSource = try Self.appSource("NotchFlow/URLSchemeReceiver.swift")
        let appSource = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(delegateSource.contains("applicationShouldHandleReopen"))
        #expect(delegateSource.contains("Self.onReopen?()"))
        #expect(appSource.contains("URLSchemeAppDelegate.onReopen ="))
        #expect(appSource.contains("settingsWindowRouter.open()"))
        #expect(appSource.contains("@Environment(\\.openSettings)"))
        #expect(appSource.contains("NSApp.activate(ignoringOtherApps: true)"))
        #expect(appSource.contains("$0.level == .normal && $0.canBecomeKey"))
        #expect(appSource.contains("settingsWindow.makeKeyAndOrderFront(nil)"))
        #expect(appSource.contains("settingsWindow.orderFrontRegardless()"))
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

    @Test("all-displays mode owns one independently interactive panel per extra screen")
    func presenterCreatesSecondaryDisplayPanels() throws {
        let source = try Self.appSource("NotchFlow/IslandPresenter.swift")

        #expect(source.contains("secondaryPresentations"))
        #expect(source.contains("selectDisplays("))
        #expect(source.contains("SecondaryIslandPresentation("))
        #expect(source.contains("secondary.stop()"))
    }

    @Test("music transport reaches the provider from the presenter")
    func musicTransportIsWired() throws {
        let presenter = try Self.appSource("NotchFlow/IslandPresenter.swift")
        let app = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(presenter.contains("musicProvider?.send(command)"))
        #expect(presenter.contains("model.onMusicTransport ="))
        #expect(app.contains("musicProvider: musicProvider"))
    }

    @Test("modern macOS avoids the MediaRemote entitlement wall")
    func modernMacOSUsesScriptableMusicFallback() throws {
        let source = try Self.appSource("NotchFlow/MusicBackend.swift")
        let directEntitlements = try Self.appSource("NotchFlow-Direct.entitlements")

        #expect(source.contains("#available(macOS 15.4, *)"))
        #expect(source.contains("AppleScriptMusicProvider("))
        #expect(source.contains("URLSessionArtworkDataLoader()"))
        #expect(source.contains("gate.access()"))
        #expect(directEntitlements.contains("com.apple.security.automation.apple-events"))
    }

    @Test("music automation changes refresh the live provider immediately")
    func automationChangesRefreshMusicProvider() throws {
        let source = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(source.contains("refreshCurrentState()"))
        #expect(source.contains("NSApplication.didBecomeActiveNotification"))
        #expect(source.contains("refreshMusicAutomationState()"))
    }

    @Test("launch never waits for an Apple Events permission query")
    func launchDoesNotQueryMusicAutomationSynchronously() throws {
        let source = try Self.appSource("NotchFlow/NotchFlowApp.swift")
        let initializer = try #require(
            source.split(separator: "var body: some Scene", maxSplits: 1).first
        )

        #expect(
            initializer.contains(
                "_musicAutomation = State(initialValue: makePendingMusicAutomationAccess())"
            )
        )
        #expect(!initializer.contains("makeMusicAutomationAccess(gate:"))
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

    /// Ending an instance has to reap its sub-agents at the delivery site.
    ///
    /// `AIAgentActivity.dependents(endingWith:in:)` is unit-tested, but it is a
    /// pure function: nothing fails if the sink never calls it, and the symptom
    /// is a card the user cannot dismiss rather than a broken build.
    @Test("ending an agent session reaps the sub-agents under it")
    func endingASessionReapsItsSubagents() throws {
        let source = try Self.appSource("NotchFlow/NotchFlowApp.swift")

        #expect(source.contains("AIAgentActivity.dependents("))
        #expect(
            source.contains("endingWith: activity"),
            "the sink never asks which sessions end with this one"
        )
        #expect(
            source.contains("sessionLedger.forget(dependent.sessionID)"),
            "a reaped sub-agent left in the ledger is judged against a dead timeline"
        )
    }

    /// Nothing may be drawn outside the island's own silhouette.
    ///
    /// A view leaving through a transition keeps its full layout size while it
    /// fades, so collapsing drew the expanded cards at their old size for a few
    /// frames after the black surface had shrunk past them. The mask is what
    /// stops that, and it only works while the surface and the content sit in
    /// the same masked stack — nothing about the types enforces it.
    @Test("the island clips its content to the surface it draws")
    func islandContentIsClippedToItsSurface() throws {
        let source = try Self.appSource("NotchFlow/IslandPresenter.swift")

        #expect(source.contains(".mask(alignment: .top) { surfaceMask }"))
        #expect(
            source.contains("private var surfaceSize: CGSize"),
            "the surface and its mask must be sized from one place or they can drift apart"
        )

        // The click-anywhere-outside collapse target has to stay outside the
        // mask, or a click past the island's edge stops closing it.
        let maskCall = try #require(source.range(of: ".mask(alignment: .top)"))
        let collapseTarget = try #require(source.range(of: "onTapGesture(perform: model.onCollapse)"))
        #expect(
            collapseTarget.upperBound < maskCall.lowerBound,
            "the collapse target was moved inside the mask and no longer covers the window"
        )
    }
}
