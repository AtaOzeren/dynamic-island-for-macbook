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

        let registry = ProviderComposition.makeRegistry(
            musicProvider: musicProvider,
            timerProvider: TimerProvider(),
            enabledIdentifiers: settingsStore.enabledProviderIdentifiers
        )
        self.registry = registry
        settingsStore.observeProviderEnablement { identifier, isEnabled in
            registry.setEnabled(isEnabled, for: identifier)
        }

        registry.startObserving(into: manager)

        let islandPresenter = IslandPresenter(manager: manager, settingsStore: settingsStore)
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
        let activityManager = manager
        urlSchemeReceiver.onMessage = { message in
            let activity = AIAgentActivity(message: message)
            if activity.endsPresentation {
                activityManager.end(activity.identity)
            } else {
                activityManager.register(activity)
            }
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
