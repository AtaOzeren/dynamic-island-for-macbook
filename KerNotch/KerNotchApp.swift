import AppKit
import Foundation
import KerNotchCore
import KerNotchProviders
import KerNotchUI
import ServiceManagement
import SwiftUI
import os

@MainActor
private final class DisplayInventory: ObservableObject {
    @Published var displays: [DisplayDescription]

    init(displays: [DisplayDescription]) {
        self.displays = displays
    }
}

/// What the Integrations pane shows about Discord that only the running
/// integration knows, published so the settings window follows it live.
@MainActor
private final class DiscordSettingsModel: ObservableObject {
    @Published var status: DiscordConnectionStatus
    @Published var isDiscordInstalled = false

    init(status: DiscordConnectionStatus) {
        self.status = status
    }
}

@main
struct KerNotchApp: App {
    private static let isUITesting = CommandLine.arguments.contains("--ui-testing")
    private static let reopenSettingsArgument = "--show-settings-after-restart"

    /// Delivers `kernotch://` URLs while no window is open. See
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
    private let onboardingPresenter: OnboardingPresenter
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

    /// `nil` in the App Store build: the integration reaches Discord's socket
    /// outside the sandbox, so that build has no tab for it and no connection.
    private let discordIntegration: DiscordIntegration?

    /// Watches the process's own CPU and degrades, restarts, or quits the app
    /// when it runs away. Held for the app's lifetime for the plainest reason:
    /// a supervisor that deallocates takes its sampler's timer with it, which is
    /// indistinguishable from never having armed one.
    private let watchdogLaunch: WatchdogLaunch

    /// The one gate both the music backend and the Activities pane consult, so
    /// the button the user presses and the permission the provider is blocked on
    /// are the same fact.
    private let automationGate: MusicAutomationGate
    private let appliedLanguageOverride: String?

    /// False when the settings file exists but could not be read. The session
    /// then runs on defaults that are not the user's choices, so nothing is
    /// applied on the user's behalf outside KerNotch itself: not Launch at
    /// Login, not the app language, not the agents' hook files, not onboarding.
    /// Otherwise a file made unreadable by a restore or an ownership change
    /// would cost the user their login item and their installed hooks.
    private let isSettingsFileUsable: Bool

    @State private var aiPreferences: AIIntegrationPreferences
    @State private var generalPreferences: GeneralPreferences
    @State private var enabledIdentifiers: Set<ActivityProviderIdentifier>
    @State private var languageOverride: String?
    @State private var musicAutomation: [MusicAutomationAccess]
    @State private var musicAutomationRequestsInProgress: Set<MusicPlayerTarget>
    @State private var hookStates: [IPCAgentID: HookInstallationState]
    @State private var launchAtLoginNeedsApproval: Bool
    @State private var discordPreferences: DiscordIntegrationPreferences
    @StateObject private var displayInventory: DisplayInventory
    @StateObject private var discordSettings: DiscordSettingsModel

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

        #if DEBUG
        Self.startCPUDrillIfRequested(CommandLine.arguments)
        #endif

        self.automationGate = automationGate
        self.settingsWindowRouter = settingsWindowRouter
        // Onboarding's last step opens the same Settings scene ⌘, does, so it
        // rides the router rather than a second, divergent open path.
        self.onboardingPresenter = OnboardingPresenter(openSettings: settingsWindowRouter.open)
        _musicAutomation = State(initialValue: makePendingMusicAutomationAccess())
        _musicAutomationRequestsInProgress = State(initialValue: [])
        _hookStates = State(initialValue: [:])
        let currentDisplays = NSScreen.screens.map(DisplayDescription.init)
        let displayInventory = DisplayInventory(displays: currentDisplays)
        _displayInventory = StateObject(wrappedValue: displayInventory)
        // Only a bundled app has a preferences domain of its own to import
        // from; an unbundled `swift run` would read the installed app's domain
        // and could never remove from it.
        let settingsStorage = FileSettingsStorage()
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            settingsStorage.importPreferences(from: .standard, domain: bundleIdentifier)
        }
        let settingsStore = SettingsStore(storage: settingsStorage, migrations: [.removingRetiredKeys])
        let isSettingsFileUsable = settingsStorage.isSavingEnabled
        self.isSettingsFileUsable = isSettingsFileUsable
        self.musicProvider = musicProvider
        self.settingsStore = settingsStore
        _aiPreferences = State(initialValue: settingsStore.aiIntegrationPreferences)
        var initialGeneralPreferences = settingsStore.generalPreferences
        initialGeneralPreferences.displayTarget = normalizeDisplayPreference(
            initialGeneralPreferences.displayTarget,
            availableDisplayCount: currentDisplays.count
        )
        initialGeneralPreferences.appearance = .dark
        if isSettingsFileUsable == false {
            // Shows what macOS actually has, rather than a default that would
            // read as the login item having been switched off.
            initialGeneralPreferences.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        _generalPreferences = State(initialValue: initialGeneralPreferences)
        _launchAtLoginNeedsApproval = State(
            initialValue: SMAppService.mainApp.status == .requiresApproval
        )
        if isSettingsFileUsable {
            do {
                try Self.applyLaunchAtLogin(initialGeneralPreferences.launchAtLogin)
            } catch {
                Self.present(error)
            }
        }
        _enabledIdentifiers = State(initialValue: settingsStore.enabledProviderIdentifiers)
        let appliedLanguageOverride = settingsStore[.languageOverride]
        self.appliedLanguageOverride = appliedLanguageOverride
        _languageOverride = State(initialValue: appliedLanguageOverride)
        if isSettingsFileUsable {
            Self.applyLanguageOverride(appliedLanguageOverride)
        }

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

        let microphoneMonitor = MicrophoneActivityMonitor()
        let microphoneRecording = SystemAudioRecordingObserver(monitor: microphoneMonitor)
        let registry = ProviderComposition.makeRegistry(
            musicProvider: musicProvider,
            timerProvider: timerProvider,
            microphoneRecording: microphoneRecording,
            enabledIdentifiers: settingsStore.enabledProviderIdentifiers
        )
        self.registry = registry
        settingsStore.observeProviderEnablement { identifier, isEnabled in
            registry.setEnabled(isEnabled, for: identifier)
        }

        registry.startObserving(into: manager)
        appleClockMirror?.start()

        // Applied before the island draws anything, so a Discord call already in
        // progress at launch appears as the call rather than flashing as the
        // microphone indicator first.
        #if APPSTORE_BUILD
            let discordIntegration: DiscordIntegration? = nil
        #else
            let discordIntegration: DiscordIntegration? = DiscordIntegration(
                manager: manager,
                microphoneMonitor: microphoneMonitor,
                microphoneRecording: microphoneRecording,
                clientID: DiscordApplication.builtInClientID(infoDictionary: Bundle.main.infoDictionary)
            )
        #endif
        self.discordIntegration = discordIntegration
        let discordSettings = DiscordSettingsModel(status: discordIntegration?.status ?? .inactive)
        _discordSettings = StateObject(wrappedValue: discordSettings)
        _discordPreferences = State(initialValue: settingsStore.discordIntegrationPreferences)
        discordIntegration?.onStatusChange = { status in
            discordSettings.status = status
        }
        discordIntegration?.apply(settingsStore.discordIntegrationPreferences)

        // The providers are handed in so a press inside the expanded island
        // reaches the backend that owns the state it is about. The presenter
        // holds no provider logic of its own — it routes.
        let islandPresenter = IslandPresenter(
            manager: manager,
            settingsStore: settingsStore,
            musicProvider: musicProvider,
            timerProvider: timerProvider,
            discordVoice: discordIntegration?.voiceChannelLeaving,
            screenConfigurationSettled: { displays in
                statusItemPresenter.screenConfigurationDidChange()
                displayInventory.displays = displays
            }
        )
        self.islandPresenter = islandPresenter

        // The URL scheme is the transport every installed hook actually uses, so
        // its two ends are wired here rather than on a scene: KerNotch is an
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

        // The watchdog is built here and armed after launch, so its sampler and
        // its restart ledger are anchored once for the process. The context
        // closure reads the two facts a diagnostics report wants that only the
        // main thread knows; kind names only, never activity content, because a
        // report is a file the user may hand to someone else.
        let activityManagerForContext = manager
        watchdogLaunch = WatchdogLaunch(
            island: islandPresenter,
            stopListener: { Self.stopSynchronously(loopbackListener) },
            context: {
                CPUWatchdogSupervisor.Context(
                    displayTarget: String(
                        describing: settingsStore.generalPreferences.displayTarget
                    ),
                    activityKinds: activityManagerForContext.activeActivities.map {
                        String(describing: $0.kind)
                    }
                )
            }
        )

        // A listening socket outliving the process that owned it is a defect,
        // and an accessory app is quit from a menu item rather than by closing
        // a window — so termination is the only hook that always runs.
        // The status item is not removed here: on macOS 26 Control Center
        // records a removal as the app discarding its item. The process is
        // exiting; the item goes with it.
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
        let watchdogLaunch = watchdogLaunch
        URLSchemeAppDelegate.onDidFinishLaunching = {
            // Ordering a window front, or adding a menu bar item, before AppKit
            // has finished launching is unreliable — the screen arrangement is
            // not settled, and a status item placed against it lands on no
            // menu bar at all.
            statusItemPresenter.setVisible(settingsStore.generalPreferences.showMenuBarIcon)
            islandPresenter.start()

            // After the island is up, in both directions: the watchdog's first
            // context read needs a presenter that has a panel, and a notice has
            // nowhere to be announced until there is one.
            watchdogLaunch.startIfAllowed(
                isUITesting: Self.isUITesting,
                isDisabledBySetting: settingsStore[.cpuWatchdogDisabled]
            )
            watchdogLaunch.presentNoticeIfNeeded()

            if isSettingsFileUsable {
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
            } else {
                Self.presentUnreadableSettingsNotice()
            }

            if CommandLine.arguments.contains(Self.reopenSettingsArgument) {
                settingsWindowRouter.open()
            }

        }
    }

    /// Runs the synthetic CPU load requested by `--cpu-drill*` so the
    /// verification drills have real load to catch. DEBUG builds only —
    /// the release path never reads these flags.
    #if DEBUG
    private static func startCPUDrillIfRequested(_ arguments: [String]) {
        guard arguments.contains(where: { $0.hasPrefix("--cpu-drill") }) else { return }
        guard let options = LaunchArguments.parseCPUDrill(arguments) else {
            print(
                "--cpu-drill: malformed value; expected background:<percent>:<seconds>, main:<seconds>, or --cpu-drill-fast-clock"
            )
            return
        }
        switch options.drill {
        case .background(let percent, let seconds):
            startBackgroundDrill(percent: percent, seconds: seconds)
        case .mainThread(let seconds):
            startMainThreadDrill(seconds: seconds)
        case nil:
            break
        }
    }

    /// Holds `percent` of one core for `seconds`, closing the loop on CPU time
    /// actually consumed rather than on a fixed spin/sleep cycle.
    ///
    /// A fixed cycle does not survive contact with a `.utility` thread: its
    /// sleeps are coalesced and it lands on efficiency cores, so the sleep half
    /// overshoots unpredictably. Measured on this Mac, a 10 ms cycle asked for
    /// 30% and delivered ~16% — under the watchdog's own 20% threshold, which
    /// made the plan's own degrade drill verify nothing at all. Comparing
    /// `CLOCK_THREAD_CPUTIME_ID` against the elapsed suspending clock converges
    /// on the requested share whatever the scheduler does with the sleeps.
    private static func startBackgroundDrill(percent: Int, seconds: Int) {
        let dutyFraction = Double(percent) / 100
        let spinSliceNanoseconds: UInt64 = 2_000_000
        let idleSliceSeconds = 0.002
        let drill = Thread {
            let startWall = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let startCPU = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            let runNanoseconds = UInt64(seconds) * 1_000_000_000

            while true {
                let elapsed = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- startWall
                guard elapsed < runNanoseconds else { return }

                let consumed = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) &- startCPU
                guard Double(consumed) < Double(elapsed) * dutyFraction else {
                    Thread.sleep(forTimeInterval: idleSliceSeconds)
                    continue
                }
                let sliceEnd = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                    &+ spinSliceNanoseconds
                while clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) < sliceEnd {}
            }
        }
        drill.qualityOfService = .utility
        drill.start()
    }

    /// Dispatched rather than run inline so the app finishes launching first;
    /// the drill then blocks the main thread, which is the point. The 10 s
    /// delay gives the watchdog a healthy baseline before the hang starts.
    private static func startMainThreadDrill(seconds: Int) {
        DispatchQueue.main.async {
            Thread.sleep(forTimeInterval: 10)
            let deadline = Date().addingTimeInterval(TimeInterval(seconds))
            while Date() < deadline {}
        }
    }
    #endif

    /// Closes the listener's socket before the process exits.
    ///
    /// `applicationWillTerminate` returns into `exit()`, so an `async` stop
    /// detached into a `Task` would be killed mid-cancel and leave the port
    /// bound. The semaphore waits on the actor's own `stop()` instead — bounded,
    /// because it is a cancel and a file removal with nothing to block on.
    /// `nonisolated` because the watchdog's alarm path calls it from the
    /// watchdog queue: an alarm fires exactly when the main thread may be unable
    /// to answer, so requiring main here would deadlock the recovery.
    private nonisolated static func stopSynchronously(_ listener: LoopbackHTTPListener) {
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
                presentListenerFailure()
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
        // The only scene. No `MenuBarExtra`: Control Center hosts one as a
        // blank slot beside the real icon on macOS 26. Settings is opened by
        // `SettingsWindowRouter` instead.
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
            onPreviewAttentionGlow: islandPresenter.previewAttentionGlow,
            launchAtLoginNeedsApproval: launchAtLoginNeedsApproval,
            restartRequired: languageOverride != appliedLanguageOverride,
            onRestart: restartApplication,
            discordPreferences: $discordPreferences,
            discordSettings: discordIntegration.map { integration in
                DiscordSettingsState(
                    isDiscordInstalled: discordSettings.isDiscordInstalled,
                    isConnectionAvailable: integration.isConnectionAvailable,
                    status: discordSettings.status
                )
            },
            onDiscordPreferencesChange: applyDiscordPreferences,
            onDiscordAction: handleDiscordAction
        )
        .onAppear {
            aiPreferences = settingsStore.aiIntegrationPreferences
            discordPreferences = settingsStore.discordIntegrationPreferences
            refreshDiscordInstallation()
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
            refreshDiscordInstallation()
        }
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: .musicAutomationPermissionDidChange
            )
        ) { _ in
            refreshMusicAutomationState()
        }
        .onChange(of: generalPreferences, initial: true) { previous, preferences in
            // With an unreadable settings file, only a switch the user actually
            // flips reaches macOS; the window echoing its values back does not.
            if isSettingsFileUsable || previous.launchAtLogin != preferences.launchAtLogin {
                do {
                    try Self.applyLaunchAtLogin(preferences.launchAtLogin)
                } catch {
                    Self.present(error)
                }
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

    /// The only place in KerNotch that can raise a system permission prompt,
    /// and it runs solely from the button in the Activities pane.
    ///
    /// Every row is re-read afterwards, not just the one asked for, because the
    /// System Settings pane the denied row points at can change any target's
    /// answer while KerNotch is running — refreshing one would leave the other
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
        islandPresenter.applyAttentionGlowPreference(preferences.showsAttentionGlow)
        Task {
            do {
                _ = try await loopbackListener.updatePreferences(preferences)
            } catch {
                Self.presentListenerFailure()
            }
        }
    }

    private func applyDiscordPreferences(_ preferences: DiscordIntegrationPreferences) {
        settingsStore.discordIntegrationPreferences = preferences
        discordIntegration?.apply(preferences)
    }

    private func handleDiscordAction(_ action: DiscordSettingsAction) {
        switch action {
        case .connect:
            discordIntegration?.authorize()
        case .disconnect:
            discordIntegration?.forgetAuthorization()
        case .reconnect:
            discordIntegration?.reconnect()
        }
    }

    /// Read when the settings window is shown or the app comes forward, never on
    /// a timer: the answer only changes when the user installs or removes
    /// Discord, and both happen outside KerNotch.
    private func refreshDiscordInstallation() {
        discordSettings.isDiscordInstalled = discordIntegration?.isDiscordInstalled ?? false
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

    private static func presentUnreadableSettingsNotice() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "KerNotch could not read its settings.")
        alert.informativeText = String(
            localized:
                "KerNotch is using default settings for now and will not save changes. Launch at Login, the app language and agent hooks are left exactly as they are. Check that this file belongs to you, then restart KerNotch: \(FileSettingsStorage.defaultFileURL.path)"
        )
        alert.runModal()
    }

    /// Says what a failed loopback start means for the user, in their language.
    ///
    /// `NSAlert(error:)` rendered the listener's error as "The operation couldn't
    /// be completed (… error 0.)", which names neither what broke nor what to do.
    /// The underlying cause is a diagnostic, so the listener logs it instead.
    private static func presentListenerFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "KerNotch could not start listening for agent updates.")
        alert.informativeText = String(
            localized:
                "Agent status will not appear in the notch until listening starts. Turn the agent off and on again, or restart KerNotch."
        )
        alert.runModal()
    }

}

extension KerNotchApp {
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
    private static let statusItemAutosaveName = "KerNotchMenuBarItem"
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

    /// Re-adds the item after the display arrangement changes.
    ///
    /// Through macOS 15 an item is placed once, against the arrangement in
    /// force when it was added, and removing and re-adding is the only way to
    /// ask for a fresh placement. From macOS 26 Control Center places it and
    /// treats a removal as the app discarding its item, so nothing is done.
    func screenConfigurationDidChange() {
        guard statusItem != nil else { return }
        if #available(macOS 26, *) { return }
        stop()
        start()
    }

    /// Shows or hides the item. On macOS 26 it is never removed — Control
    /// Center records a removal as the app discarding its item — so hiding is
    /// `isVisible`, which it records as the client's request and honours.
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
    /// On macOS 26 Control Center hosts the item, keyed by bundle id plus
    /// `autosaveName`, and hides it while any application that ever launched
    /// this process has "Allow in the Menu Bar" off. That state is outside the
    /// app (`scripts/menubar-owner.sh` repairs it); this side only makes sure
    /// Control Center never sees a removal to record.
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
                accessibilityDescription: "KerNotch"
            )
        image?.isTemplate = true
        image?.size = Self.iconSize
        button.image = image
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("KerNotch")
        button.toolTip = "KerNotch"
        statusItem.menu = makeMenu()
        statusItem.isVisible = true
        self.statusItem = statusItem
    }

    /// Records where the item actually landed.
    ///
    /// The window is laid out on a later turn, so a frame read inside `start()`
    /// is always pre-layout. Only the delayed read says where the item landed —
    /// or, on macOS 26, whether Control Center gave it a slot at all: a hosted
    /// item on the notched display reads 33 points tall, an item Control Center
    /// hid idles at the screen origin at the old 22.
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
            title: String(localized: "Quit KerNotch"),
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
final class SettingsWindowRouter {
    private static let logger = Logger(
        subsystem: "com.kernotch.KerNotch",
        category: "settings"
    )

    /// How many times `open()` tries to deliver the Settings action before
    /// giving up. The first attempt covers the common case — the app is
    /// already active, or the window already exists — and the retries cover
    /// the two races: an activation that has not landed yet, and a main menu
    /// whose ⌘, item SwiftUI has not installed yet (the relaunch path).
    private static let maximumAttempts = 6

    /// Space between attempts. One run loop turn is the least an activation
    /// needs; 100 ms leaves headroom for a busy launch without a perceptible
    /// delay when a retry is needed.
    private static let attemptDelay: TimeInterval = 0.1

    /// Opens the `Settings` scene the way ⌘, does: through the menu item
    /// SwiftUI installs for it, with that item as the sender. A
    /// `MenuBarExtra` bridge for `openSettings` costs a blank status item
    /// slot, so the item is the path.
    ///
    /// Delivery is verified, not assumed. `NSApp.activate` takes effect on a
    /// later pass of the event loop, and the send can race the launch-time
    /// installation of the menu. A failed send is retried a bounded number of
    /// times so an open that races activation lands once activation settles,
    /// instead of being dropped silently.
    func open() {
        open(attempt: 1)
    }

    private func open(attempt: Int) {
        bringSettingsForward()

        guard let item = Self.settingsMenuItem(in: NSApp.mainMenu), let action = item.action else {
            Self.logger.error(
                "No ⌘, item in the main menu (attempt \(attempt, privacy: .public) of \(Self.maximumAttempts, privacy: .public))."
            )
            return retryOrGiveUp(attempt: attempt)
        }

        guard NSApp.sendAction(action, to: item.target, from: item) else {
            Self.logger.error(
                "Settings send failed \(attempt, privacy: .public)/\(Self.maximumAttempts, privacy: .public); active: \(NSApp.isActive)."
            )
            return retryOrGiveUp(attempt: attempt)
        }

        // The scene creates its window asynchronously, so fronting must wait a
        // turn; fronting before SwiftUI has built the window fronts nothing.
        // A second, delayed front covers an activation that has still not
        // landed by then — the window is open either way, but an accessory app
        // that never became active leaves it behind whoever holds focus.
        DispatchQueue.main.async { [weak self] in
            self?.bringSettingsForward()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.attemptDelay) { [weak self] in
            self?.bringSettingsForward()
        }
    }

    private func retryOrGiveUp(attempt: Int) {
        guard attempt < Self.maximumAttempts else {
            Self.logger.error(
                "Settings scene could not be opened after \(Self.maximumAttempts, privacy: .public) attempts."
            )
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.attemptDelay) { [weak self] in
            self?.open(attempt: attempt + 1)
        }
    }

    /// The Settings scene's menu item, matched two ways because either alone
    /// misses a real machine.
    ///
    /// The key equivalent is read back localized: on a Turkish keyboard the
    /// item SwiftUI writes reports `"ö"`, not `","`, so an exact-string match
    /// never finds it and Settings silently never opened there. The action —
    /// SwiftUI's private `menuAction:` — is layout-independent, and the item
    /// carries a non-nil target (a SwiftUI menu-item callback), so the send
    /// below reaches it directly without a key window to walk a responder
    /// chain from. Both probes verified live on macOS 26.
    static func settingsMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            let opensSettingsByShortcut =
                item.keyEquivalent == "," && item.keyEquivalentModifierMask.contains(.command)
            let opensSettingsByAction = item.action == Selector(("menuAction:"))
            if opensSettingsByShortcut || opensSettingsByAction {
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
        guard let settingsWindow = Self.settingsWindow(in: NSApp.windows) else { return }
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
    }

    /// The Settings scene's window, identified rather than guessed.
    ///
    /// SwiftUI gives the scene's window its own identifier; matching on that
    /// stops the router from keying whichever ordinary window happens to be
    /// first in `NSApp.windows`. Onboarding, manual setup, and alert windows
    /// are all ordinary keyable windows that must not be brought forward in
    /// the settings window's place, and none of them carries an identifier.
    static func settingsWindow(in windows: [NSWindow]) -> NSWindow? {
        windows.first { window in
            guard window.level == .normal,
                let identifier = window.identifier?.rawValue.lowercased()
            else { return false }
            return identifier.contains("settings")
        }
    }
}
