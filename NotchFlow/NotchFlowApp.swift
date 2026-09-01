import AppKit
import Foundation
import NotchFlowCore
import NotchFlowProviders
import NotchFlowUI
import ServiceManagement
import SwiftUI

@main
struct NotchFlowApp: App {
    private static let isUITesting = CommandLine.arguments.contains("--ui-testing")

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

    @State private var aiPreferences: AIIntegrationPreferences
    @State private var generalPreferences: GeneralPreferences
    @State private var enabledIdentifiers: Set<ActivityProviderIdentifier>
    @State private var languageOverride: String?
    @State private var musicAutomation: [MusicAutomationAccess]
    @State private var hookStates: [IPCAgentID: HookInstallationState]
    @State private var availableDisplays: [DisplayDescription]

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
        _hookStates = State(initialValue: [:])
        let currentDisplays = NSScreen.screens.map(DisplayDescription.init)
        _availableDisplays = State(initialValue: currentDisplays)
        let settingsStore = SettingsStore()
        self.musicProvider = musicProvider
        self.settingsStore = settingsStore
        _aiPreferences = State(initialValue: settingsStore.aiIntegrationPreferences)
        var initialGeneralPreferences = settingsStore.generalPreferences
        initialGeneralPreferences.displayTarget = normalizeDisplayPreference(
            initialGeneralPreferences.displayTarget,
            availableDisplayCount: currentDisplays.count
        )
        initialGeneralPreferences.launchAtLogin = Self.launchAtLoginIsRequested
        initialGeneralPreferences.appearance = .dark
        _generalPreferences = State(initialValue: initialGeneralPreferences)
        _enabledIdentifiers = State(initialValue: settingsStore.enabledProviderIdentifiers)
        _languageOverride = State(initialValue: settingsStore[.languageOverride])
        Self.applyLanguageOverride(settingsStore[.languageOverride])

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
            timerProvider: timerProvider
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
        let activityManager = manager
        let messageSink: @MainActor @Sendable (IPCMessage) -> Void = { message in
            let activity = AIAgentActivity(message: message)
            if activity.endsPresentation {
                activityManager.end(activity.identity)
            } else {
                activityManager.register(activity)
            }
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
        URLSchemeAppDelegate.onTerminate = {
            statusItemPresenter.stop()
            Self.stopSynchronously(loopbackListener)
        }

        // Deferred to the first turn of the run loop rather than run inline:
        // ordering a window front and activating the app before AppKit has
        // finished launching is unreliable, and this is the one screen that has
        // to come forward on its own in an app with no Dock icon.
        //
        // Detection is an autoclosure so a returning user — the overwhelmingly
        // common case — never probes the file system for agent configuration.
        let presenter = onboardingPresenter
        let manualSetupPresenter = manualSetupPresenter
        DispatchQueue.main.async {
            // Ordering a window front before AppKit has finished launching is
            // unreliable. `start()` orders the persistent compact panel in, so
            // it waits on the same turn the onboarding window does.
            statusItemPresenter.start()
            islandPresenter.start()

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

    var body: some Scene {
        // `openSettings` exists only in SwiftUI's scene environment. This
        // zero-size scene captures that official action for Finder reopen
        // events; the visible, reliable menu bar item is AppKit-owned.
        MenuBarExtra(isInserted: .constant(true)) {
            EmptyView()
        } label: {
            SettingsActionBridge(router: settingsWindowRouter)
        }

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
            availableDisplays: availableDisplays,
            information: aboutInformation,
            languages: LanguageOption.shipped,
            musicAutomation: $musicAutomation,
            hookStates: hookStates,
            onRequestAutomation: requestAutomation,
            onHookAction: handleHookAction
        )
        .onAppear {
            aiPreferences = settingsStore.aiIntegrationPreferences
            hookStates = Self.currentHookStates()
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
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        ) { _ in
            refreshAvailableDisplays()
        }
        .onChange(of: aiPreferences, initial: true) { _, preferences in
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
        .onChange(of: generalPreferences, initial: true) { _, preferences in
            do {
                try Self.applyLaunchAtLogin(preferences.launchAtLogin)
            } catch {
                Self.present(error)
                generalPreferences.launchAtLogin = Self.launchAtLoginIsRequested
                return
            }
            settingsStore.generalPreferences = preferences
            islandPresenter.applyAppearance(preferences.appearance)
            islandPresenter.applyReducedMotion(preferences.reducedMotionOverride)
            islandPresenter.applyDisplayTarget()
        }
        .onChange(of: enabledIdentifiers) { _, identifiers in
            settingsStore.enabledProviderIdentifiers = identifiers
        }
        .onChange(of: languageOverride) { _, override in
            settingsStore[.languageOverride] = override
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
        automationGate.requestAccess(for: target)
        refreshMusicAutomationState()
    }

    private func refreshMusicAutomationState() {
        musicAutomation = makeMusicAutomationAccess(gate: automationGate)
        (musicProvider as? AppleScriptMusicProvider)?.refreshCurrentState()
    }

    private func reloadMusicAutomationState() {
        musicAutomation = automationGate.reloadAccess()
    }

    private func handleHookAction(_ agentID: IPCAgentID, _ action: AIHookAction) {
        do {
            switch action {
            case .install:
                try Self.installHook(for: agentID)
                aiPreferences.setAgent(agentID, enabled: true)
            case .uninstall:
                try Self.uninstallHook(for: agentID)
                aiPreferences.setAgent(agentID, enabled: false)
            case .manualSetup:
                Self.presentManualSetup(for: agentID, with: manualSetupPresenter)
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

    private static var launchAtLoginIsRequested: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: true
        case .notRegistered, .notFound: false
        @unknown default: false
        }
    }

    private static func applyLaunchAtLogin(_ shouldLaunch: Bool) throws {
        let service = SMAppService.mainApp
        if shouldLaunch {
            guard !launchAtLoginIsRequested else { return }
            try service.register()
        } else {
            guard launchAtLoginIsRequested else { return }
            try service.unregister()
        }
    }

    private static func currentHookStates() -> [IPCAgentID: HookInstallationState] {
        Dictionary(uniqueKeysWithValues: IPCAgentID.allCases.map { agentID in
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

private extension NotchFlowApp {
    func refreshAvailableDisplays() {
        let displays = NSScreen.screens.map(DisplayDescription.init)
        availableDisplays = displays
        generalPreferences.displayTarget = normalizeDisplayPreference(
            generalPreferences.displayTarget,
            availableDisplayCount: displays.count
        )
    }

    var aboutInformation: AboutInformation {
        let info = Bundle.main.infoDictionary
        return AboutInformation(
            version: info?["CFBundleShortVersionString"] as? String ?? "—",
            build: info?["CFBundleVersion"] as? String ?? "—",
            musicBackendName: musicProvider.backendName
        )
    }
}

@MainActor
private final class StatusItemPresenter: NSObject {
    private static let visibilityRestorationDelay = Duration.milliseconds(500)
    private static let timerPresets: [(minutes: Int, title: String)] = [
        (5, String(localized: "Start 5-Minute Timer")),
        (10, String(localized: "Start 10-Minute Timer")),
        (25, String(localized: "Start 25-Minute Timer")),
    ]

    private let timerProvider: TimerProvider
    private let openSettings: () -> Void
    private var statusItem: NSStatusItem?
    private var visibilityRestorationTask: Task<Void, Never>?

    init(timerProvider: TimerProvider, openSettings: @escaping () -> Void) {
        self.timerProvider = timerProvider
        self.openSettings = openSettings
    }

    func start() {
        guard statusItem == nil else { return }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "NotchFlowStatusItem"
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(
            systemSymbolName: "capsule.fill",
            accessibilityDescription: "NotchFlow"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.setAccessibilityLabel("NotchFlow")
        statusItem.button?.toolTip = "NotchFlow"
        statusItem.menu = makeMenu()
        statusItem.isVisible = true
        self.statusItem = statusItem
        visibilityRestorationTask = Task { @MainActor [weak self, weak statusItem] in
            try? await Task.sleep(for: Self.visibilityRestorationDelay)
            guard
                Task.isCancelled == false,
                let self,
                self.statusItem === statusItem,
                let statusItem
            else { return }

            statusItem.isVisible = false
            await Task.yield()
            statusItem.isVisible = true
        }
    }

    func stop() {
        visibilityRestorationTask?.cancel()
        visibilityRestorationTask = nil
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

        menu.addItem(menuItem(
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
    private var action: OpenSettingsAction?
    private var hasPendingRequest = false

    func install(_ action: OpenSettingsAction) {
        self.action = action
        guard hasPendingRequest else { return }
        hasPendingRequest = false
        action()
    }

    func open() {
        guard let action else {
            hasPendingRequest = true
            return
        }
        action()
    }
}

private struct SettingsActionBridge: View {
    @Environment(\.openSettings) private var openSettings
    let router: SettingsWindowRouter

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                router.install(openSettings)
            }
    }
}
