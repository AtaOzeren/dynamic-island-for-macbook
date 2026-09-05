import AppKit
import Foundation
import NotchFlowCore
import NotchFlowProviders
import NotchFlowUI
import os
import ServiceManagement
import SwiftUI

@MainActor
private final class DisplayInventory: ObservableObject {
    @Published var displays: [DisplayDescription]

    init(displays: [DisplayDescription]) {
        self.displays = displays
    }
}

@main
struct NotchFlowApp: App {
    private static let isUITesting = CommandLine.arguments.contains("--ui-testing")
    private static let reopenSettingsArgument = "--show-settings-after-restart"

    /// Delivers `notchflow://` URLs while no window is open. See
    /// `URLSchemeAppDelegate` for why a view modifier cannot.
    @NSApplicationDelegateAdaptor(URLSchemeAppDelegate.self)
    private var appDelegate

    /// The composition root's single music backend, selected at compile time by
    /// `makeMusicProvider()`.
    private let musicProvider: any MusicProvider
    private let manager = ActivityManager()
    private let registry: ActivityProviderRegistry
    private let settingsStore: SettingsStore
    private let urlSchemeReceiver = URLSchemeReceiver()
    private let onboardingPresenter = OnboardingPresenter()
    private let manualSetupPresenter = ManualSetupPresenter()
    private let settingsWindowRouter: SettingsWindowRouter

    /// The loopback transport, held for the app's lifetime so termination can
    /// close its socket.
    private let loopbackListener: LoopbackHTTPListener

    /// The timer the menu bar starts and the island controls — one instance,
    /// shared with the registry that draws it.
    private let timerProvider: TimerProvider
    private let appleClockMirror: AppleClockMirror?
    private let statusItemPresenter: StatusItemPresenter

    /// Draws the manager's activities in the overlay window. Held for the app's
    /// lifetime: the panel is created once and ordered in and out, never rebuilt.
    private let islandPresenter: IslandPresenter

    /// The one gate both the music backend and the Activities pane consult, so
    /// the button the user presses and the permission the provider is blocked on
    /// are the same fact.
    private let automationGate: MusicAutomationGate
    private let appliedLanguageOverride: String?

    @State private var aiPreferences: AIIntegrationPreferences
    @State private var generalPreferences: GeneralPreferences
    @State private var enabledIdentifiers: Set<ActivityProviderIdentifier>
    @State private var languageOverride: String?
    @State private var musicAutomation: [MusicAutomationAccess]
    @State private var musicAutomationRequestsInProgress: Set<MusicPlayerTarget>
    @State private var hookStates: [IPCAgentID: HookInstallationState]
    @State private var launchAtLoginNeedsApproval: Bool
    @StateObject private var displayInventory: DisplayInventory

    init() {
        let automationGate = MusicAutomationGate()
        let musicProvider = makeMusicProvider(gate: automationGate)
        let settingsWindowRouter = SettingsWindowRouter()

        // The build's backend, reportable without a window, so CI can assert the
        // two configurations differ and a support conversation can ask for one
        // line of output rather than a screenshot. This must happen before
        // provider observation starts, so the diagnostic path starts no Apple
        // Events work.
        if CommandLine.arguments.contains("--print-music-backend") {
            print(musicProvider.backendName)
            exit(EXIT_SUCCESS)
        }

        self.automationGate = automationGate
        self.settingsWindowRouter = settingsWindowRouter
        _musicAutomation = State(initialValue: makePendingMusicAutomationAccess())
        _musicAutomationRequestsInProgress = State(initialValue: [])
        _hookStates = State(initialValue: [:])
        let currentDisplays = NSScreen.screens.map(DisplayDescription.init)
        let displayInventory = DisplayInventory(displays: currentDisplays)
        _displayInventory = StateObject(wrappedValue: displayInventory)
        let settingsStore = SettingsStore()
        self.musicProvider = musicProvider
        self.settingsStore = settingsStore
        _aiPreferences = State(initialValue: settingsStore.aiIntegrationPreferences)
        var initialGeneralPreferences = settingsStore.generalPreferences
        initialGeneralPreferences.displayTarget = normalizeDisplayPreference(
            initialGeneralPreferences.displayTarget,
            availableDisplayCount: currentDisplays.count
        )
        initialGeneralPreferences.appearance = .dark
        _generalPreferences = State(initialValue: initialGeneralPreferences)
        _launchAtLoginNeedsApproval = State(
            initialValue: SMAppService.mainApp.status == .requiresApproval
        )
        do {
            try Self.applyLaunchAtLogin(initialGeneralPreferences.launchAtLogin)
        } catch {
            Self.present(error)
        }
        _enabledIdentifiers = State(initialValue: settingsStore.enabledProviderIdentifiers)
        let appliedLanguageOverride = settingsStore[.languageOverride]
        self.appliedLanguageOverride = appliedLanguageOverride
        _languageOverride = State(initialValue: appliedLanguageOverride)
        Self.applyLanguageOverride(appliedLanguageOverride)

        // Held rather than constructed inline: the menu bar's timer control and
        // the expanded island's pause/resume have to reach the same provider
        // instance the registry observes, or a press would drive a timer
        // nothing is drawing.
        let timerProvider = TimerProvider()
        self.timerProvider = timerProvider
        appleClockMirror = makeAppleClockMirror(timerProvider: timerProvider)
        let statusItemPresenter = StatusItemPresenter(
            timerProvider: timerProvider,
            openSettings: settingsWindowRouter.open
        )
        self.statusItemPresenter = statusItemPresenter

        let registry = ProviderComposition.makeRegistry(
            musicProvider: musicProvider,
            timerProvider: timerProvider,
            enabledIdentifiers: settingsStore.enabledProviderIdentifiers
        )
        self.registry = registry
        settingsStore.observeProviderEnablement { identifier, isEnabled in
            registry.setEnabled(isEnabled, for: identifier)
        }

        registry.startObserving(into: manager)
        appleClockMirror?.start()

        // The providers are handed in so a press inside the expanded island
        // reaches the backend that owns the state it is about. The presenter
        // holds no provider logic of its own — it routes.
        let islandPresenter = IslandPresenter(
            manager: manager,
            settingsStore: settingsStore,
            musicProvider: musicProvider,
            timerProvider: timerProvider,
            screenConfigurationSettled: { displays in
                statusItemPresenter.screenConfigurationDidChange()
                displayInventory.displays = displays
            }
        )
        self.islandPresenter = islandPresenter

        // The URL scheme is the transport every installed hook actually uses, so
        // its two ends are wired here rather than on a scene: NotchFlow is an
        // accessory app, and a message that arrives while no window is open is
        // the normal case, not the exception.
        let receiver = urlSchemeReceiver
        URLSchemeAppDelegate.onOpenURL = { url in
            receiver.handle(url)
        }
        URLSchemeAppDelegate.onReopen = {
            settingsWindowRouter.open()
        }

        // Seeded from the store, not left at `.default`, because the default has
        // every agent switched off: a receiver holding it drops every message
        // the user opted into during onboarding. The settings window keeps this
        // in step afterwards, but it cannot be the first writer — it may never
        // be opened at all.
        urlSchemeReceiver.preferences = settingsStore.aiIntegrationPreferences

        // `register` rather than `update` because a session's first message is
        // as likely to be `working` as anything else — there is no separate
        // "agent started" event to register on — and it preserves the original
        // registration time when the session is already on screen.
        //
        // Named once and handed to both transports rather than written twice:
        // the URL scheme and the loopback listener carry the same envelope, so
        // two copies of this would be two chances for one transport to start
        // registering what the other ends.
        //
        // Both transports share one ledger, for the same reason they share this
        // closure: a session's messages can arrive over either, and two ledgers
        // would each judge half a timeline as if it were the whole one.
        let activityManager = manager
        let sessionLedger = AIAgentSessionLedgerBox()
        let messageSink: @MainActor @Sendable (IPCMessage) -> Void = { message in
            guard sessionLedger.admit(message) else { return }
            let activity = AIAgentActivity(message: message)
            guard activity.endsPresentation else {
                activityManager.register(activity)
                return
            }

            // An instance ending takes its sub-agents with it. They are sessions
            // the agent spawned, so the process that would have reported their
            // end is the one that just went away.
            for dependent in AIAgentActivity.dependents(
                endingWith: activity,
                in: activityManager.activeActivities
            ) {
                sessionLedger.forget(dependent.sessionID)
                activityManager.end(dependent.identity)
            }
            sessionLedger.forget(message.sessionId)
            activityManager.end(activity.identity)
        }
        urlSchemeReceiver.onMessage = messageSink

        // The second transport from `docs/07-ai-integration.md`, for hooks that
        // can reach a socket but not `open`. Its own preference gate is seeded
        // from the store for the reason the URL receiver's is: `.default` has
        // every agent off, and with no agent enabled the listener does not open
        // a port at all — so a receiver left at the default would never listen
        // for the agents the user opted into during onboarding.
        let loopbackListener = LoopbackHTTPListener(sink: messageSink)
        self.loopbackListener = loopbackListener
        let seededPreferences = settingsStore.aiIntegrationPreferences
        Task { try? await loopbackListener.updatePreferences(seededPreferences) }

        // A listening socket outliving the process that owned it is a defect,
        // and an accessory app is quit from a menu item rather than by closing
        // a window — so termination is the only hook that always runs.
        // The status item is deliberately *not* removed here. `removeStatusItem`
        // is how a user-initiated hide is expressed, and AppKit records that by
        // writing the item's persisted visibility flag to false — so removing it
        // on the way out taught every subsequent launch that the icon was not
        // wanted, and the item was created but never given a menu bar slot. The
        // process is exiting; the item goes with it.
        URLSchemeAppDelegate.onTerminate = {
            Self.stopSynchronously(loopbackListener)
        }

        // Deferred to `applicationDidFinishLaunching` rather than run inline:
        // ordering a window front and activating the app before AppKit has
        // finished launching is unreliable, and this is the one screen that has
        // to come forward on its own in an app with no Dock icon.
        //
        // Detection is an autoclosure so a returning user — the overwhelmingly
        // common case — never probes the file system for agent configuration.
        let presenter = onboardingPresenter
        let manualSetupPresenter = manualSetupPresenter
        URLSchemeAppDelegate.onDidFinishLaunching = {
            // Ordering a window front, or adding a menu bar item, before AppKit
            // has finished launching is unreliable — the screen arrangement is
            // not settled, and a status item placed against it lands on no
            // menu bar at all.
            statusItemPresenter.setVisible(settingsStore.generalPreferences.showMenuBarIcon)
            islandPresenter.start()
            Self.repairEnabledHooks(
                preferences: settingsStore.aiIntegrationPreferences,
                manualSetupPresenter: manualSetupPresenter
            )

            presenter.presentIfNeeded(
                hasCompletedOnboarding: settingsStore[.hasCompletedOnboarding] || Self.isUITesting,
                detectedAgents: Self.detectedAgents()
            ) { outcome in
                settingsStore[.hasCompletedOnboarding] = true
                Self.applyHookOffers(
                    outcome.acceptedHookOffers,
                    to: settingsStore,
                    receiver: receiver,
                    listener: loopbackListener,
                    manualSetupPresenter: manualSetupPresenter
                )
            }

            if CommandLine.arguments.contains(Self.reopenSettingsArgument) {
                settingsWindowRouter.open()
            }

        }
    }

    /// Closes the listener's socket before the process exits.
    ///
    /// `applicationWillTerminate` returns into `exit()`, so an `async` stop
    /// detached into a `Task` would be killed mid-cancel and leave the port
    /// bound. The semaphore waits on the actor's own `stop()` instead — bounded,
    /// because it is a cancel and a file removal with nothing to block on.
    private static func stopSynchronously(_ listener: LoopbackHTTPListener) {
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            await listener.stop()
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + 2)
    }

    /// Pins the bundle-lookup language list to the user's override.
    ///
    /// `AppleLanguages` is the only lever that reaches every catalog at once —
    /// Core's, UI's, and the app's — because it is what `Bundle` consults when
    /// choosing an `.lproj`. Setting it per bundle instead would leave the three
    /// free to disagree, which reads as a half-translated window.
    ///
    /// It must be written before the first lookup, hence the call from `init`:
    /// `Bundle` caches its resolved language on first use, which is why the
    /// About pane says the choice takes effect at the next launch. Clearing the
    /// override removes the key rather than writing an empty list, so the system
    /// preference — not an empty override — is what the next launch reads.
    private static func applyLanguageOverride(_ code: String?) {
        guard let code else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            return
        }
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
    }

    /// The agents whose configuration files exist, in the fixed order the
    /// onboarding screen lists them.
    private static func detectedAgents() -> [IPCAgentID] {
        let statuses = AgentDetector().detect()
        return IPCAgentID.allCases.filter { statuses[$0] == .installed }
    }

    /// Installs only hooks explicitly accepted in onboarding, then updates both
    /// IPC transports from the resulting preference.
    private static func applyHookOffers(
        _ agentIDs: [IPCAgentID],
        to store: SettingsStore,
        receiver: URLSchemeReceiver,
        listener: LoopbackHTTPListener,
        manualSetupPresenter: ManualSetupPresenter
    ) {
        guard !agentIDs.isEmpty else { return }
        var preferences = store.aiIntegrationPreferences
        for agentID in agentIDs {
            do {
                try installHook(for: agentID)
                preferences.setAgent(agentID, enabled: true)
            } catch {
                presentManualSetup(
                    for: agentID,
                    with: manualSetupPresenter,
                    fallbackError: error
                )
            }
        }
        store.aiIntegrationPreferences = preferences
        receiver.preferences = preferences
        Task {
            do {
                _ = try await listener.updatePreferences(preferences)
            } catch {
                present(error)
            }
        }
    }

    private static func repairEnabledHooks(
        preferences: AIIntegrationPreferences,
        manualSetupPresenter: ManualSetupPresenter
    ) {
        LaunchHookRepairer(hooks: managedAgentHooks()).repair(
            preferences: preferences
        ) { agentID, error in
            presentManualSetup(
                for: agentID,
                with: manualSetupPresenter,
                fallbackError: error
            )
        }
    }

    private static func managedAgentHooks() -> [ManagedAgentHook] {
        IPCAgentID.allCases.map { agentID in
            ManagedAgentHook(
                agentID: agentID,
                installationState: { hookState(for: agentID) },
                install: { try installHook(for: agentID) },
                uninstallManagedHook: { try uninstallHook(for: agentID) }
            )
        }
    }

    var body: some Scene {
        // The only scene. An earlier version also declared a zero-size
        // `MenuBarExtra` to capture `openSettings` from the environment and
        // removed it on first appearance. On macOS 26 Control Center hosts
        // every status item itself and kept a blank 16-point slot for that
        // bridge beside the real icon; the Settings window is reached through
        // the responder chain instead (see `SettingsWindowRouter`).
        Settings {
            settingsWindowContent
        }
    }

    private var settingsWindowContent: some View {
        SettingsWindowView(
            general: $generalPreferences,
            enabledIdentifiers: $enabledIdentifiers,
            aiPreferences: $aiPreferences,
            languageOverride: $languageOverride,
            availableDisplays: displayInventory.displays,
            information: aboutInformation,
            languages: LanguageOption.shipped,
            musicAutomation: $musicAutomation,
            hookStates: hookStates,
            automationRequestsInProgress: musicAutomationRequestsInProgress,
            onRequestAutomation: requestAutomation,
            onAIPreferencesChange: applyAIPreferences,
            onHookAction: handleHookAction,
            launchAtLoginNeedsApproval: launchAtLoginNeedsApproval,
            restartRequired: languageOverride != appliedLanguageOverride,
            onRestart: restartApplication
        )
        .onAppear {
            aiPreferences = settingsStore.aiIntegrationPreferences
            hookStates = Self.currentHookStates()
            refreshLaunchAtLoginApprovalState()
            refreshAvailableDisplays()
            reloadMusicAutomationState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            reloadMusicAutomationState()
        }
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: .musicAutomationPermissionDidChange
            )
        ) { _ in
            refreshMusicAutomationState()
        }
        .onChange(of: generalPreferences, initial: true) { _, preferences in
            do {
                try Self.applyLaunchAtLogin(preferences.launchAtLogin)
            } catch {
                Self.present(error)
            }
            refreshLaunchAtLoginApprovalState()
            settingsStore.generalPreferences = preferences
            statusItemPresenter.setVisible(preferences.showMenuBarIcon)
            islandPresenter.applyAppearance(preferences.appearance)
            islandPresenter.applyReducedMotion(preferences.reducedMotionOverride)
            islandPresenter.applyDisplayTarget()
        }
        .onChange(of: displayInventory.displays) { _, displays in
            generalPreferences.displayTarget = normalizeDisplayPreference(
                generalPreferences.displayTarget,
                availableDisplayCount: displays.count
            )
        }
        .onChange(of: enabledIdentifiers) { _, identifiers in
            settingsStore.enabledProviderIdentifiers = identifiers
        }
        .onChange(of: languageOverride) { _, override in
            settingsStore[.languageOverride] = override
        }
    }

    private func restartApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [Self.reopenSettingsArgument]
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            Task { @MainActor in
                if let error {
                    Self.present(error)
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// The only place in NotchFlow that can raise a system permission prompt,
    /// and it runs solely from the button in the Activities pane.
    ///
    /// Every row is re-read afterwards, not just the one asked for, because the
    /// System Settings pane the denied row points at can change any target's
    /// answer while NotchFlow is running — refreshing one would leave the other
    /// row asserting something the system no longer agrees with.
    private func requestAutomation(_ target: MusicPlayerTarget) {
        guard musicAutomation.first(where: { $0.target == target })?.isRequestable == true else {
            return
        }
        guard musicAutomationRequestsInProgress.isEmpty else { return }
        guard musicAutomationRequestsInProgress.insert(target).inserted else { return }

        Task { @MainActor in
            defer { musicAutomationRequestsInProgress.remove(target) }
            _ = await automationGate.requestAccess(for: target)
            refreshMusicAutomationState()
        }
    }

    private func refreshMusicAutomationState() {
        musicAutomation = makeMusicAutomationAccess(gate: automationGate)
        (musicProvider as? AppleScriptMusicProvider)?.refreshCurrentState()
    }

    private func reloadMusicAutomationState() {
        musicAutomation = automationGate.reloadAccess()
    }

    private func applyAIPreferences(_ preferences: AIIntegrationPreferences) {
        settingsStore.aiIntegrationPreferences = preferences
        urlSchemeReceiver.preferences = preferences
        Task {
            do {
                _ = try await loopbackListener.updatePreferences(preferences)
            } catch {
                Self.present(error)
            }
        }
    }

    private func handleHookAction(_ agentID: IPCAgentID, _ action: AIHookAction) {
        do {
            let updatedPreferences: AIIntegrationPreferences?
            switch action {
            case .install:
                try Self.installHook(for: agentID)
                var preferences = aiPreferences
                preferences.setAgent(agentID, enabled: true)
                updatedPreferences = preferences
            case .uninstall:
                try Self.uninstallHook(for: agentID)
                var preferences = aiPreferences
                preferences.setAgent(agentID, enabled: false)
                updatedPreferences = preferences
            case .manualSetup:
                Self.presentManualSetup(for: agentID, with: manualSetupPresenter)
                updatedPreferences = nil
            }
            if let updatedPreferences {
                aiPreferences = updatedPreferences
                applyAIPreferences(updatedPreferences)
            }
        } catch {
            Self.presentManualSetup(
                for: agentID,
                with: manualSetupPresenter,
                fallbackError: error
            )
        }
        hookStates = Self.currentHookStates()
    }

    private func refreshLaunchAtLoginApprovalState() {
        launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    private static func applyLaunchAtLogin(_ shouldLaunch: Bool) throws {
        let service = SMAppService.mainApp
        switch resolveLaunchAtLogin(preference: shouldLaunch, serviceStatus: service.status) {
        case .register:
            try service.register()
        case .unregister:
            try service.unregister()
        case .needsApproval, .none:
            break
        }
    }

    private static func currentHookStates() -> [IPCAgentID: HookInstallationState] {
        Dictionary(
            uniqueKeysWithValues: IPCAgentID.allCases.map { agentID in
                (agentID, hookState(for: agentID))
            })
    }

    private static func hookState(for agentID: IPCAgentID) -> HookInstallationState {
        switch agentID {
        case .claudeCode: ClaudeCodeHookInstaller().installationState()
        case .codex: CodexHookInstaller().installationState()
        case .opencode: OpenCodePluginInstaller().installationState()
        }
    }

    private static func installHook(for agentID: IPCAgentID) throws {
        switch agentID {
        case .claudeCode: try ClaudeCodeHookInstaller().install()
        case .codex: try CodexHookInstaller().install()
        case .opencode: try OpenCodePluginInstaller().install()
        }
    }

    private static func uninstallHook(for agentID: IPCAgentID) throws {
        switch agentID {
        case .claudeCode: try ClaudeCodeHookInstaller().uninstall()
        case .codex: try CodexHookInstaller().uninstall()
        case .opencode: try OpenCodePluginInstaller().uninstall()
        }
    }

    private static func manualSetupInstructions(
        for agentID: IPCAgentID
    ) throws -> ManualSetupInstructions {
        switch agentID {
        case .claudeCode: try ClaudeCodeHookInstaller().manualSetupInstructions()
        case .codex: try CodexHookInstaller().manualSetupInstructions()
        case .opencode: try OpenCodePluginInstaller().manualSetupInstructions()
        }
    }

    private static func presentManualSetup(
        for agentID: IPCAgentID,
        with presenter: ManualSetupPresenter,
        fallbackError: Error? = nil
    ) {
        do {
            presenter.present(try manualSetupInstructions(for: agentID))
        } catch {
            present(fallbackError ?? error)
        }
    }

    private static func present(_ error: Error) {
        NSAlert(error: error).runModal()
    }

}

extension NotchFlowApp {
    fileprivate func refreshAvailableDisplays() {
        displayInventory.displays = NSScreen.screens.map(DisplayDescription.init)
    }

    fileprivate var aboutInformation: AboutInformation {
        let info = Bundle.main.infoDictionary
        return AboutInformation(
            version: info?["CFBundleShortVersionString"] as? String ?? "—",
            build: info?["CFBundleVersion"] as? String ?? "—",
            musicBackendName: musicProvider.backendName
        )
    }
}

/// Holds the ordering ledger for the app's lifetime.
///
/// The sink is a closure shared by both transports and captured before any
/// object that could own the ledger exists, so the mutable state needs a
/// reference to live in — a captured `var` would be copied into the closure and
/// every message would be judged against an empty table.
@MainActor
private final class AIAgentSessionLedgerBox {
    private var ledger = AIAgentSessionLedger()

    func admit(_ message: IPCMessage) -> Bool {
        ledger.admit(message) == .admit
    }

    func forget(_ sessionID: UUID) {
        ledger.forget(sessionID)
    }
}

@MainActor
private final class StatusItemPresenter: NSObject {
    /// The image size the menu bar draws at. Constraining the `NSImage` rather
    /// than trusting the asset keeps a future art change from producing an item
    /// that is silently clipped to nothing.
    private static let iconSize = NSSize(width: 18, height: 18)

    /// Named explicitly so Control Center tracks one stable host identity across
    /// launches instead of a derived `Item-N` that shifts as scenes come and go.
    private static let statusItemAutosaveName = "NotchFlowMenuBarItem"
    private static let logger = Logger(
        subsystem: "com.notchflow.NotchFlow",
        category: "status-item"
    )

    private static let timerPresets: [(minutes: Int, title: String)] = [
        (5, String(localized: "Start 5-Minute Timer")),
        (10, String(localized: "Start 10-Minute Timer")),
        (25, String(localized: "Start 25-Minute Timer")),
    ]

    private let timerProvider: TimerProvider
    private let openSettings: () -> Void
    private var statusItem: NSStatusItem?

    init(timerProvider: TimerProvider, openSettings: @escaping () -> Void) {
        self.timerProvider = timerProvider
        self.openSettings = openSettings
        super.init()
    }

    /// Re-adds the item after the display arrangement changes — on releases
    /// where the app still places its own item.
    ///
    /// Through macOS 15 a status item is placed once, against the arrangement
    /// in force when it was added. Plugging in or unplugging a display moves the
    /// menu bar without re-placing it, which leaves the item at coordinates that
    /// no longer name any menu bar. Removing and re-adding is the only way to
    /// ask for a fresh placement there.
    ///
    /// From macOS 26 the item is hosted by Control Center, which re-lays it out
    /// itself. Removing it there is not a re-placement request but a removal:
    /// Control Center stops tracking the host and treats the item as one the
    /// app no longer wants, and the first time it recorded NotchFlow's item as
    /// blocked was immediately after exactly this remove-and-re-add cycle.
    func screenConfigurationDidChange() {
        guard statusItem != nil else { return }
        if #available(macOS 26, *) { return }
        stop()
        start()
    }

    /// Shows or hides the item without ever removing it on macOS 26.
    ///
    /// Control Center owns the item there. Removing it and adding it back is
    /// how the app looked like it kept discarding its own item, and Control
    /// Center answered by blocking the bundle id — every later launch was hosted
    /// and immediately hidden, with nothing in the app able to undo it. Toggling
    /// `isVisible` is the supported signal: Control Center records it as the
    /// client's visibility request and honours the next `true`.
    func setVisible(_ isVisible: Bool) {
        if #available(macOS 26, *) {
            if isVisible {
                if let statusItem {
                    statusItem.isVisible = true
                } else {
                    start()
                }
            } else {
                statusItem?.isVisible = false
            }
            return
        }
        if isVisible {
            start()
        } else {
            stop()
        }
    }

    /// Adds the menu bar item.
    ///
    /// The button is fully configured *before* the item is made visible. An
    /// earlier version instead made it visible immediately and then toggled
    /// `isVisible` off and on again half a second later to force a redraw; that
    /// removed and re-added the item inside a single run loop turn, which is a
    /// state the menu bar does not reliably recover from — the item reported
    /// itself visible while nothing was ever drawn.
    ///
    /// `autosaveName` is set rather than omitted.
    ///
    /// On macOS 26 the item is not placed by this process at all: Control Center
    /// hosts it, keyed by bundle id plus this name, and decides whether it is
    /// shown. It attributes the item to every application that ever launched
    /// this process and hides it while any of them has "Allow in the Menu Bar"
    /// turned off — a hidden item reports itself visible, has an image, and its
    /// window idles at the screen origin at the old 22-point bar height while a
    /// shown item on the same display gets 33. That state is outside the app
    /// (`scripts/menubar-owner.sh` diagnoses and repairs it); what this side
    /// controls is to never give Control Center a removal to record — see
    /// `screenConfigurationDidChange()` and the terminate path.
    func start() {
        guard statusItem == nil else { return }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = Self.statusItemAutosaveName
        statusItem.behavior = []
        guard let button = statusItem.button else {
            NSStatusBar.system.removeStatusItem(statusItem)
            return
        }

        let image =
            NSImage(named: "MenuBarIcon")
            ?? NSImage(
                systemSymbolName: "capsule.fill",
                accessibilityDescription: "NotchFlow"
            )
        image?.isTemplate = true
        image?.size = Self.iconSize
        button.image = image
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("NotchFlow")
        button.toolTip = "NotchFlow"
        statusItem.menu = makeMenu()
        statusItem.isVisible = true
        self.statusItem = statusItem
        reportPlacement(of: statusItem)
    }

    /// Records where the item actually landed.
    ///
    /// The window is laid out on a later turn, so a frame read inside `start()`
    /// is always pre-layout. Only the delayed read says where the item landed —
    /// or, on macOS 26, whether Control Center gave it a slot at all: a hosted
    /// item on the notched display reads 33 points tall, an item Control Center
    /// hid idles at the screen origin at the old 22.
    private func reportPlacement(of statusItem: NSStatusItem) {
        assert(
            statusItem.button?.image != nil,
            "Menu bar item has no image; the MenuBarIcon asset and the SF Symbol fallback both failed."
        )
        Task { @MainActor [weak statusItem] in
            try? await Task.sleep(for: .seconds(1))
            guard let statusItem else { return }
            let frame = statusItem.button?.window?.frame ?? .zero
            Self.logger.info(
                """
                status item settled: visible=\(statusItem.isVisible, privacy: .public) \
                windowFrame=\(NSStringFromRect(frame), privacy: .public)
                """
            )
        }
    }

    func stop() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for preset in Self.timerPresets {
            let item = NSMenuItem(
                title: preset.title,
                action: #selector(startTimer(_:)),
                keyEquivalent: ""
            )
            item.tag = preset.minutes
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(
            menuItem(
                title: String(localized: "Stop Timer"),
                action: #selector(stopTimer)
            ))
        menu.addItem(.separator())

        let settingsItem = menuItem(
            title: String(localized: "Settings…"),
            action: #selector(showSettings)
        )
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = menuItem(
            title: String(localized: "Quit NotchFlow"),
            action: #selector(quit)
        )
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
        return menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        timerProvider.handle(
            .start(.countdown(duration: .seconds(sender.tag * 60)))
        )
    }

    @objc private func stopTimer() {
        timerProvider.handle(.stop)
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
private final class SettingsWindowRouter {
    private static let logger = Logger(
        subsystem: "com.notchflow.NotchFlow",
        category: "settings"
    )

    /// Opens the SwiftUI `Settings` scene the way ⌘, does: by triggering the
    /// "Settings…" item SwiftUI installs in the application menu, with that item
    /// as the sender.
    ///
    /// Two other routes were tried and rejected. Sending `showSettingsWindow:`
    /// down the responder chain is refused on macOS 26 ("Please use
    /// SettingsLink for opening the Settings scene") and opens nothing. Reading
    /// `openSettings` from a zero-size `MenuBarExtra` — the route this app used
    /// before — creates a second status item, and on macOS 26 Control Center
    /// hosts it as a blank 16-point slot beside the real icon.
    ///
    /// The item is found by its key equivalent rather than its title, which is
    /// localized.
    func open() {
        bringSettingsForward()
        if let item = Self.settingsMenuItem(in: NSApp.mainMenu), let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        } else {
            Self.logger.error("No ⌘, item in the main menu; the Settings scene cannot be opened.")
        }
        DispatchQueue.main.async { [weak self] in
            self?.bringSettingsForward()
        }
    }

    private static func settingsMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.keyEquivalent == "," && item.keyEquivalentModifierMask.contains(.command) {
                return item
            }
            if let found = settingsMenuItem(in: item.submenu) {
                return found
            }
        }
        return nil
    }

    private func bringSettingsForward() {
        NSApp.activate(ignoringOtherApps: true)
        guard
            let settingsWindow = NSApp.windows.first(where: {
                $0.level == .normal && $0.canBecomeKey
            })
        else { return }
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
    }
}

