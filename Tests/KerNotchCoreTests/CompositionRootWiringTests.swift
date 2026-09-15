import Foundation
import Testing

/// Asserts the app target actually assembles what the libraries provide.
///
/// The defect class this file exists to catch is not a broken unit — every unit
/// here has passing tests — it is a unit that is never constructed. No test
/// target can reach the composition root's `App.init` — `KerNotchTests` can
/// import the executable, but nothing can construct the scene it assembles — so
/// the wiring is inspected as source, the same way `HookSnippetDocDriftTests`
/// inspects `docs/07-ai-integration.md`. Coarse by nature: it proves a wire
/// exists, not that it carries the right current. `scripts/check-composition-root.sh` is
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

    @Test("launch initialization never replaces the stored preference with service state")
    func launchAtLoginPreferenceRemainsAuthoritative() throws {
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(!source.contains("launchAtLogin = Self.launchAtLoginIsRequested"))
        #expect(source.contains("resolveLaunchAtLogin("))
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
        for presenter in ["KerNotch/IslandPresenter.swift", "KerNotch/SecondaryIslandPresentation.swift"] {
            let source = try Self.appSource(presenter)
            #expect(
                source.contains("model.registrationTimes = manager.registrationTimes"),
                "\(presenter) never refreshes the registration times"
            )
        }

        let primary = try Self.appSource("KerNotch/IslandPresenter.swift")
        #expect(primary.contains("@Published var registrationTimes"))
        #expect(primary.contains("registrationTimes: model.registrationTimes"))
    }

    /// The pill's icons, the black bar behind them, and the hover target must
    /// all be sized from the same set of visible slots.
    ///
    /// A paused note leaves after twenty seconds. While that timer lived as
    /// private state inside `CompactActivityView`, only the icons shrank: the
    /// bar kept the width of a slot that was no longer drawn, and the hover
    /// target kept reporting the pointer as over an island that had moved out
    /// from under it. The filtering functions were always correct — nothing was
    /// passing them the set — so only the wiring can catch this.
    @Test("the pill, its surface and its hover target share one visible slot set")
    func compactPillFollowsHiddenMusicIcons() throws {
        let presenter = try Self.appSource("KerNotch/IslandPresenter.swift")
        let secondary = try Self.appSource("KerNotch/SecondaryIslandPresentation.swift")
        let compactView = try Self.appSource("Sources/KerNotchUI/CompactActivityView.swift")

        // One owner, read by the surface and handed to the view as a value.
        #expect(presenter.contains("@Published var hiddenMusicSlotIDs"))
        #expect(presenter.contains("hiddenMusicSlotIDs: model.hiddenMusicSlotIDs"))
        #expect(!presenter.contains("$model.hiddenMusicSlotIDs"))
        #expect(
            presenter.contains(
                "compactSlotLayout(for: model.compact, hiding: model.hiddenMusicSlotIDs)"
            )
        )
        // And handed to the controller, which owns the hover target — on every
        // display, and re-read whenever an icon leaves on a clock.
        #expect(presenter.contains("hiddenMusicSlotIDs: { [model] in model.hiddenMusicSlotIDs }"))
        #expect(secondary.contains("hiddenMusicSlotIDs: { [model] in model.hiddenMusicSlotIDs }"))
        #expect(presenter.contains("controller.compactLayoutDidChange()"))
        #expect(secondary.contains("controller.compactLayoutDidChange()"))

        // The view keeps no countdown of its own: it is rebuilt on every
        // expand and collapse, which restarted the timer on every hover.
        #expect(!compactView.contains(".task(id:"))
        #expect(!compactView.contains("Task.sleep("))

        // Nothing may size the compact pill from the unfiltered presentation.
        #expect(!presenter.contains("compactPillGeometry(for: model.compact,"))
        #expect(!presenter.contains("balancedCompactPillSize(\n            for: model.compact,"))
    }

    /// The island has to stay the notch's own black on every display, hovered
    /// or not. The peek used to dim the whole island to 94%, which let the
    /// desktop through and turned the pill grey beside the hardware cutout —
    /// nothing about the surface types can catch a modifier applied above them.
    @Test("hovering never makes the island translucent")
    func hoverKeepsTheIslandOpaque() throws {
        for presenter in ["KerNotch/IslandPresenter.swift", "KerNotch/SecondaryIslandPresentation.swift"] {
            let source = try Self.appSource(presenter)
            #expect(!source.contains("hoverOpacity"), "\(presenter) still dims the island on hover")
            #expect(source.contains("model.hoverScale ="), "\(presenter) lost its hover peek")
        }

        let primary = try Self.appSource("KerNotch/IslandPresenter.swift")
        #expect(!primary.contains(".opacity(model.state"))
        #expect(primary.contains(".fill(.black)"))
    }

    @Test("both IPC transports are handed the same message sink")
    func transportsShareOneSink() throws {
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

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
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(source.contains("onAIPreferencesChange: applyAIPreferences"))
        #expect(source.contains("private func applyAIPreferences("))
        #expect(source.contains("settingsStore.aiIntegrationPreferences = preferences"))
        #expect(source.contains("urlSchemeReceiver.preferences = preferences"))
        // The glow switch is presentation only, so the island has to be told
        // directly — no receiver would ever carry it there.
        #expect(source.contains("islandPresenter.applyAttentionGlowPreference(preferences.showsAttentionGlow)"))

        // The Settings test button reaches the island through the window view.
        let settingsWindow = try Self.appSource("Sources/KerNotchUI/SettingsWindowView.swift")
        #expect(source.contains("onPreviewAttentionGlow: islandPresenter.previewAttentionGlow"))
        #expect(settingsWindow.contains("onPreviewAttentionGlow: onPreviewAttentionGlow"))
        #expect(!source.contains(".onChange(of: aiPreferences"))
    }

    @Test("the loopback listener is started and stopped from the app")
    func loopbackListenerHasALifecycle() throws {
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(source.contains("loopbackListener.updatePreferences(seededPreferences)"))
        #expect(source.contains("URLSchemeAppDelegate.onTerminate"))
        #expect(source.contains("stopSynchronously(loopbackListener)"))
    }

    @Test("the app owns one user-controlled AppKit status item")
    func appOwnsUserControlledStatusItem() throws {
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(source.contains("StatusItemPresenter("))
        #expect(source.contains("NSStatusBar.system.statusItem"))
        #expect(source.contains("statusItem.isVisible = true"))
        #expect(source.contains("NSImage(named: \"MenuBarIcon\")"))

        // The item is added once AppKit has finished launching. It carries an
        // explicit autosave name: on macOS 26 Control Center hosts the item
        // under bundle id plus that name, and a derived `Item-N` shifts as
        // scenes come and go. A toggle of `isVisible` to force a redraw may not
        // come back — it produced an item that reported itself visible while
        // the menu bar drew nothing — and neither may removing the item on
        // quit or on a screen change, which Control Center records as the item
        // being unwanted and then hides on every later launch.
        #expect(source.contains("URLSchemeAppDelegate.onDidFinishLaunching"))
        #expect(source.contains("statusItemPresenter.screenConfigurationDidChange()"))
        #expect(source.contains("statusItem.autosaveName = Self.statusItemAutosaveName"))
        #expect(source.contains("if #available(macOS 26, *) { return }"))
        #expect(!source.contains("statusItemPresenter.stop()\n            Self.stopSynchronously"))
        #expect(!source.contains("statusItem.isVisible = false"))
        #expect(!source.contains("visibilityRestorationTask"))
        #expect(source.contains("systemSymbolName: \"capsule.fill\""))
        #expect(source.contains("setAccessibilityLabel(\"KerNotch\")"))
        #expect(source.contains("statusItemPresenter.setVisible(preferences.showMenuBarIcon)"))
        // No SwiftUI `MenuBarExtra` may exist beside the AppKit item: on macOS 26
        // Control Center hosts every status item itself and kept a blank slot
        // for the zero-size bridge next to the real icon. Settings opens
        // through the responder chain instead.
        #expect(!source.contains("MenuBarExtra("))
        #expect(!source.contains("SettingsActionBridge"))
        #expect(!source.contains("Selector((\"showSettingsWindow:\"))"))
        #expect(source.contains("settingsMenuItem(in: NSApp.mainMenu)"))
    }

    @Test("hiding the status item leaves no screen notification token")
    func hiddenStatusItemHasNoScreenNotificationToken() throws {
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(source.contains("func screenConfigurationDidChange()"))
        #expect(source.contains("func setVisible(_ isVisible: Bool)"))
        #expect(source.contains("stop()"))
        #expect(!source.contains("screenChangeObserver"))
        #expect(!source.contains("didChangeScreenParametersNotification"))
    }

    @Test("a language change can relaunch the app from Settings")
    func languageChangeCanRelaunchTheApp() throws {
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(source.contains("appliedLanguageOverride"))
        #expect(source.contains("languageOverride != appliedLanguageOverride"))
        #expect(source.contains("onRestart: restartApplication"))
        #expect(source.contains("NSWorkspace.OpenConfiguration()"))
        #expect(source.contains("createsNewApplicationInstance = true"))
        #expect(source.contains("NSApp.terminate(nil)"))
    }

    @Test("reopening the running accessory app opens Settings")
    func appReopenOpensSettings() throws {
        let delegateSource = try Self.appSource("KerNotch/URLSchemeReceiver.swift")
        let appSource = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(delegateSource.contains("applicationShouldHandleReopen"))
        #expect(delegateSource.contains("Self.onReopen?()"))
        #expect(appSource.contains("URLSchemeAppDelegate.onReopen ="))
        #expect(appSource.contains("settingsWindowRouter.open()"))
        // The item is matched by action, not by key equivalent alone: on a
        // Turkish keyboard the item SwiftUI installs reads its key back as
        // "ö", and the comma-only match made Settings silently never open.
        #expect(appSource.contains("item.action == Selector((\"menuAction:\"))"))
        #expect(appSource.contains("NSApp.activate(ignoringOtherApps: true)"))
        // The send is verified and retried: the item's target is a SwiftUI
        // callback, so the send reaches it directly and an open that races
        // launch is retried rather than dropped silently. The window is found
        // by identifier, not by being the first ordinary keyable window.
        #expect(appSource.contains("NSApp.sendAction(action, to: item.target, from: item)"))
        #expect(appSource.contains("retryOrGiveUp(attempt:"))
        #expect(appSource.contains("settingsWindow(in: NSApp.windows)"))
        #expect(appSource.contains("settingsWindow.makeKeyAndOrderFront(nil)"))
        #expect(appSource.contains("settingsWindow.orderFrontRegardless()"))
    }

    @Test("the delegate forwards termination to the composition root")
    func delegateForwardsTermination() throws {
        let source = try Self.appSource("KerNotch/URLSchemeReceiver.swift")

        #expect(source.contains("func applicationWillTerminate"))
        #expect(source.contains("Self.onTerminate?()"))
    }

    @Test("the presenter observes screen changes and repositions on them")
    func presenterObservesScreenChanges() throws {
        let source = try Self.appSource("KerNotch/IslandPresenter.swift")

        #expect(source.contains("SystemScreenChangeObserver()"))
        #expect(source.contains("screenChanges.startObserving"))
        #expect(source.contains("controller.screenConfigurationDidChange()"))
    }

    @Test("all-displays mode owns one independently interactive panel per extra screen")
    func presenterCreatesSecondaryDisplayPanels() throws {
        let source = try Self.appSource("KerNotch/IslandPresenter.swift")

        #expect(source.contains("secondaryPresentations"))
        #expect(source.contains("selectDisplays("))
        #expect(source.contains("SecondaryIslandPresentation("))
        #expect(source.contains("secondary.stop()"))
    }

    @Test("music transport reaches the provider from the presenter")
    func musicTransportIsWired() throws {
        let presenter = try Self.appSource("KerNotch/IslandPresenter.swift")
        let app = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(presenter.contains("musicProvider?.send(command)"))
        #expect(presenter.contains("model.onMusicTransport ="))
        #expect(app.contains("musicProvider: musicProvider"))
    }

    @Test("modern macOS avoids the MediaRemote entitlement wall")
    func modernMacOSUsesScriptableMusicFallback() throws {
        let source = try Self.appSource("KerNotch/MusicBackend.swift")
        let directEntitlements = try Self.appSource("KerNotch-Direct.entitlements")

        #expect(source.contains("#available(macOS 15.4, *)"))
        #expect(source.contains("AppleScriptMusicProvider("))
        #expect(source.contains("URLSessionArtworkDataLoader()"))
        #expect(source.contains("gate.access()"))
        #expect(directEntitlements.contains("com.apple.security.automation.apple-events"))
    }

    @Test("music automation changes refresh the live provider immediately")
    func automationChangesRefreshMusicProvider() throws {
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(source.contains("refreshCurrentState()"))
        #expect(source.contains("NSApplication.didBecomeActiveNotification"))
        #expect(source.contains("refreshMusicAutomationState()"))
    }

    @Test("launch never waits for an Apple Events permission query")
    func launchDoesNotQueryMusicAutomationSynchronously() throws {
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")
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
        let presenter = try Self.appSource("KerNotch/IslandPresenter.swift")
        let app = try Self.appSource("KerNotch/KerNotchApp.swift")

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
        let presenter = try Self.appSource("KerNotch/IslandPresenter.swift")

        #expect(presenter.contains("setPanelVisible(state != .hidden)"))
    }

    @Test("primary actions are dispatched by intent")
    func primaryActionsAreDispatched() throws {
        let presenter = try Self.appSource("KerNotch/IslandPresenter.swift")

        #expect(presenter.contains("model.onPrimaryAction ="))
        #expect(presenter.contains("primaryActions.perform(intent)"))
        #expect(presenter.contains("WorkspacePrimaryActionDispatcher()"))
    }

    @Test("the presenter answers screen changes without polling")
    func presenterDoesNotPoll() throws {
        let source = try Self.appSource("KerNotch/IslandPresenter.swift")

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
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

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
        let source = try Self.appSource("KerNotch/IslandPresenter.swift")

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

    /// A blocked agent's announcement has to end on a clock, not on the next
    /// thing that happens to change.
    ///
    /// `refreshContent` is driven by events — an activity registering, the
    /// pointer moving, the panel changing state. An agent that failed once and
    /// went quiet produces none of those, so nothing would ever re-read the
    /// compact presentation and the pill would stay red for the activity's
    /// whole lifetime. The deadline function is pure and unit-tested; only the
    /// wiring can catch a presenter that never asks it for one.
    @Test("the island wakes itself when a clock-driven change is due")
    func islandWakesForPresentationDeadlines() throws {
        let source = try Self.appSource("KerNotch/IslandPresenter.swift")
        let clocks = try Self.appSource("Sources/KerNotchUI/IslandPresentationClocks.swift")

        #expect(clocks.contains("nextAnnouncementDeadline("))
        #expect(source.contains("clocks.nextDeadline"))
        #expect(source.contains("private var presentationRefreshTask"))
        #expect(
            source.contains("schedulePresentationRefresh(after: now)"),
            "the refresh never arms the next wake-up"
        )
        // Cancelled before each rearm, or a quiet agent accumulates one timer
        // per refresh for as long as it stays blocked.
        #expect(source.contains("presentationRefreshTask?.cancel()"))
    }

    /// The glow has to reach past the island's edge, so it cannot sit inside
    /// the mask that clips everything else — and it has to sit behind the
    /// surface, so the pill itself stays black.
    @Test("the attention glow is drawn behind the surface and outside its clip")
    func attentionGlowSitsOutsideTheClip() throws {
        let source = try Self.appSource("KerNotch/IslandPresenter.swift")

        #expect(source.contains("@Published var attentionGlow"))
        #expect(source.contains("model.attentionGlow = reading.attentionGlow"))

        let body = try #require(source.range(of: "var body: some View {"))
        let glow = try #require(
            source.range(of: "            attentionGlow\n", range: body.upperBound..<source.endIndex)
        )
        let maskedStack = try #require(
            source.range(of: "ZStack(alignment: .top) {", range: glow.upperBound..<source.endIndex)
        )
        let mask = try #require(source.range(of: ".mask(alignment: .top) { surfaceMask }"))
        #expect(glow.upperBound <= maskedStack.lowerBound, "the glow must come before the surface it sits behind")
        #expect(!source[maskedStack.lowerBound..<mask.lowerBound].contains("attentionGlow"))
        #expect(source.contains("if model.state == .compact, let glow = model.attentionGlow"))
    }

    /// Every display ends a glow, an announcement and a paused note at the same
    /// moment, because only the primary presenter keeps the clocks.
    @Test("secondary displays follow the primary presenter's clocks")
    func secondaryDisplaysFollowThePrimaryClocks() throws {
        let presenter = try Self.appSource("KerNotch/IslandPresenter.swift")
        let secondary = try Self.appSource("KerNotch/SecondaryIslandPresentation.swift")

        #expect(presenter.contains("secondary.follow(reading)"))
        #expect(secondary.contains("func follow(_ reading: IslandPresentationClocks.Reading)"))
        #expect(secondary.contains("announcementStarts: reading.announcementStarts"))
        #expect(!secondary.contains("advancedAnnouncementStarts("))
    }

    /// The watchdog's degrade stands every island's motion still, not only the
    /// primary display's.
    @Test("degrading stills the islands on every display")
    func degradingStillsEveryDisplay() throws {
        let presenter = try Self.appSource("KerNotch/IslandPresenter.swift")
        let secondary = try Self.appSource("KerNotch/SecondaryIslandPresentation.swift")

        #expect(presenter.contains("secondary.isMotionSuspended = true"))
        #expect(presenter.contains("secondary.isMotionSuspended = false"))
        #expect(presenter.contains("secondary.isMotionSuspended = isDegraded"))
        #expect(secondary.contains("set { model.isMotionSuspended = newValue }"))
    }

    /// The Discord integration only works end to end when the same microphone
    /// observer is both drawn by the registry and told to step aside, and when
    /// the island's leave press reaches the session.
    ///
    /// Each half compiles alone — a second `SystemAudioRecordingObserver`, or a
    /// presenter left at its `nil` default, still builds and still draws — so a
    /// Discord call would show twice, or its button would do nothing.
    @Test("the Discord integration shares the microphone observer and receives leave presses")
    func discordIntegrationIsWired() throws {
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(source.contains("microphoneRecording: microphoneRecording,\n            enabledIdentifiers:"))
        let integrationArguments =
            "microphoneMonitor: microphoneMonitor,\n" + "                microphoneRecording: microphoneRecording"
        let builtInClientID = "clientID: DiscordApplication.builtInClientID(infoDictionary: Bundle.main.infoDictionary)"
        #expect(source.contains(integrationArguments))
        #expect(source.contains(builtInClientID))
        #expect(source.contains("let settingsStorage = FileSettingsStorage()"))
        #expect(source.contains("settingsStorage.importPreferences(from: .standard, domain: bundleIdentifier)"))
        #expect(source.contains("SettingsStore(storage: settingsStorage, migrations: [.removingRetiredKeys])"))
        #expect(source.contains("discordVoice: discordIntegration?.voiceChannelLeaving"))
        #expect(source.contains("discordIntegration?.apply(settingsStore.discordIntegrationPreferences)"))
        #expect(source.contains("discordIntegration?.apply(preferences)"))
        #expect(source.contains("#if APPSTORE_BUILD\n            let discordIntegration: DiscordIntegration? = nil"))
    }

    /// With a settings file that exists but cannot be read, the session runs on
    /// defaults. Applying those defaults would switch off Launch at Login, drop
    /// the chosen language and — because every agent defaults to off — remove
    /// the user's installed hooks from Claude Code, Codex and OpenCode.
    @Test("an unreadable settings file leaves the system and the agents' files untouched")
    func unreadableSettingsTouchNothing() throws {
        let source = try Self.appSource("KerNotch/KerNotchApp.swift")

        #expect(source.contains("let isSettingsFileUsable = settingsStorage.isSavingEnabled"))
        let launchAtLoginGuard =
            "if isSettingsFileUsable {\n" + "            do {\n" + "                try Self.applyLaunchAtLogin"
        #expect(source.contains(launchAtLoginGuard))
        #expect(source.contains("if isSettingsFileUsable {\n            Self.applyLanguageOverride"))
        #expect(source.contains("if isSettingsFileUsable {\n                Self.repairEnabledHooks("))
        #expect(source.contains("} else {\n                Self.presentUnreadableSettingsNotice()"))
        let flippedByUser = "if isSettingsFileUsable || previous.launchAtLogin != preferences.launchAtLogin"
        #expect(source.contains(flippedByUser))
    }

    /// The Client ID travels xcconfig → build setting → Info.plist → app. A
    /// break anywhere along it still builds, and silently ships an app whose
    /// Integrations pane has no connection to offer.
    @Test("the build's Discord Client ID reaches the app's Info.plist")
    func discordClientIDIsConfigured() throws {
        let config = try Self.appSource("Config/Discord.xcconfig")
        let infoPlist = try Self.appSource("KerNotch/Info.plist")
        let project = try Self.appSource("KerNotch.xcodeproj/project.pbxproj")

        #expect(config.contains("KERNOTCH_DISCORD_CLIENT_ID = "))
        let infoPlistEntry = "<key>KerNotchDiscordClientID</key>\n\t<string>$(KERNOTCH_DISCORD_CLIENT_ID)</string>"
        #expect(infoPlist.contains(infoPlistEntry))
        #expect(project.components(separatedBy: "baseConfigurationReference = D15C0001A0000000000000A1").count - 1 == 4)
    }
}
