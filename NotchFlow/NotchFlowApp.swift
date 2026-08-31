import AppKit
import Foundation
import NotchFlowCore
import NotchFlowProviders
import NotchFlowUI
import SwiftUI

@main
struct NotchFlowApp: App {
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

    /// The loopback transport, held for the app's lifetime so termination can
    /// close its socket.
    private let loopbackListener: LoopbackHTTPListener

    /// The timer the menu bar starts and the island controls — one instance,
    /// shared with the registry that draws it.
    private let timerProvider: TimerProvider

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

    init() {
        let automationGate = MusicAutomationGate()
        let musicProvider = makeMusicProvider(gate: automationGate)

        // The build's backend, reportable without a window, so CI can assert the
        // two configurations differ and a support conversation can ask for one
        // line of output rather than a screenshot. This must happen before the
        // automation-access rows query macOS, which can block a headless build.
        if CommandLine.arguments.contains("--print-music-backend") {
            print(musicProvider.backendName)
            exit(EXIT_SUCCESS)
        }

        self.automationGate = automationGate
        _musicAutomation = State(
            initialValue: makeMusicAutomationAccess(gate: automationGate)
        )
        let settingsStore = SettingsStore()
        self.musicProvider = musicProvider
        self.settingsStore = settingsStore
        _aiPreferences = State(initialValue: settingsStore.aiIntegrationPreferences)
        _generalPreferences = State(initialValue: settingsStore.generalPreferences)
        _enabledIdentifiers = State(initialValue: settingsStore.enabledProviderIdentifiers)
        _languageOverride = State(initialValue: settingsStore[.languageOverride])
        Self.applyLanguageOverride(settingsStore[.languageOverride])

        // Held rather than constructed inline: the menu bar's timer control and
        // the expanded island's pause/resume have to reach the same provider
        // instance the registry observes, or a press would drive a timer
        // nothing is drawing.
        let timerProvider = TimerProvider()
        self.timerProvider = timerProvider

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
        DispatchQueue.main.async {
            // Ordering a window front before AppKit has finished launching is
            // unreliable, and `start()` orders the panel in the moment an
            // activity is already live — so it waits on the same turn the
            // onboarding window does.
            islandPresenter.start()

            presenter.presentIfNeeded(
                hasCompletedOnboarding: settingsStore[.hasCompletedOnboarding],
                detectedAgents: Self.detectedAgents()
            ) { outcome in
                settingsStore[.hasCompletedOnboarding] = true
                Self.applyHookOffers(outcome.acceptedHookOffers, to: settingsStore)
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

    /// The countdown lengths the menu offers.
    ///
    /// Fixed presets rather than a duration field: the menu bar cannot host
    /// text entry, and three durations cover the timer's stated V1 use without
    /// inventing a window the app otherwise does not have.
    private static let timerPresets: [(minutes: Int, title: String)] = [
        (5, String(localized: "Start 5-Minute Timer")),
        (10, String(localized: "Start 10-Minute Timer")),
        (25, String(localized: "Start 25-Minute Timer")),
    ]

    /// The agents whose configuration files exist, in the fixed order the
    /// onboarding screen lists them.
    private static func detectedAgents() -> [IPCAgentID] {
        let statuses = AgentDetector().detect()
        return IPCAgentID.allCases.filter { statuses[$0] == .installed }
    }

    /// Turns the accepted offers into the preference that actually gates the
    /// receivers, so an agent the user opted into during onboarding is enabled
    /// and every other one is left exactly as the safe defaults had it.
    ///
    /// Writing the hook itself is deliberately not done here: onboarding records
    /// consent, and the installer's own approval flow — the one Settings uses —
    /// stays the single place bytes reach an agent's configuration file.
    private static func applyHookOffers(_ agentIDs: [IPCAgentID], to store: SettingsStore) {
        guard !agentIDs.isEmpty else { return }
        var preferences = store.aiIntegrationPreferences
        for agentID in agentIDs {
            preferences.setAgent(agentID, enabled: true)
        }
        store.aiIntegrationPreferences = preferences
    }

    var body: some Scene {
        // An accessory app has no Dock icon and no window of its own once
        // onboarding closes, so this is the only standing way back into
        // settings — `docs/08-settings-and-localization.md` names the status
        // item and onboarding's last step as the two entry points.
        MenuBarExtra("NotchFlow", image: "MenuBarIcon") {
            // The timer's only entry point. `TimerProvider.handle(_:)` shipped
            // with nothing able to construct a `TimerCommand`, so the feature
            // was unreachable end to end; the menu is the lowest-risk surface
            // because it is the app's one standing window-less affordance.
            ForEach(Self.timerPresets, id: \.minutes) { preset in
                Button(preset.title) {
                    timerProvider.handle(
                        .start(.countdown(duration: .seconds(preset.minutes * 60)))
                    )
                }
            }

            Button(String(localized: "Stop Timer")) {
                timerProvider.handle(.stop)
            }

            Divider()

            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit NotchFlow") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            SettingsWindowView(
                general: $generalPreferences,
                enabledIdentifiers: $enabledIdentifiers,
                aiPreferences: $aiPreferences,
                languageOverride: $languageOverride,
                availableDisplays: NSScreen.screens.map(DisplayDescription.init),
                information: aboutInformation,
                languages: LanguageOption.shipped,
                musicAutomation: $musicAutomation,
                onRequestAutomation: requestAutomation
            )
            .onChange(of: aiPreferences, initial: true) { _, preferences in
                settingsStore.aiIntegrationPreferences = preferences
                urlSchemeReceiver.preferences = preferences
            }
            .onChange(of: generalPreferences) { _, preferences in
                settingsStore.generalPreferences = preferences
                islandPresenter.applyAppearance(preferences.appearance)
            }
            .onChange(of: enabledIdentifiers) { _, identifiers in
                settingsStore.enabledProviderIdentifiers = identifiers
            }
            .onChange(of: languageOverride) { _, override in
                settingsStore[.languageOverride] = override
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
        automationGate.requestAccess(for: target)
        musicAutomation = makeMusicAutomationAccess(gate: automationGate)
    }

    private var aboutInformation: AboutInformation {
        let info = Bundle.main.infoDictionary
        return AboutInformation(
            version: info?["CFBundleShortVersionString"] as? String ?? "—",
            build: info?["CFBundleVersion"] as? String ?? "—",
            musicBackendName: musicProvider.backendName
        )
    }
}
