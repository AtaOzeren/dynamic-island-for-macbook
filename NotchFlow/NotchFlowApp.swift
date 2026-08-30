import AppKit
import Foundation
import NotchFlowCore
import NotchFlowProviders
import NotchFlowUI
import SwiftUI

@main
struct NotchFlowApp: App {
    /// The composition root's single music backend, selected at compile time by
    /// `makeMusicProvider()`.
    private let musicProvider: any MusicProvider
    private let manager = ActivityManager()
    private let registry: ActivityProviderRegistry
    private let settingsStore: SettingsStore
    private let urlSchemeReceiver = URLSchemeReceiver()
    private let onboardingPresenter = OnboardingPresenter()

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

        // The build's backend, reportable without a window, so CI can assert the
        // two configurations differ and a support conversation can ask for one
        // line of output rather than a screenshot. It exits before observation
        // starts: a probe that registered with the system power and recording
        // sources would be doing the work this todo exists to make conditional.
        if CommandLine.arguments.contains("--print-music-backend") {
            print(musicProvider.backendName)
            exit(EXIT_SUCCESS)
        }

        registry.startObserving(into: manager)

        // Deferred to the first turn of the run loop rather than run inline:
        // ordering a window front and activating the app before AppKit has
        // finished launching is unreliable, and this is the one screen that has
        // to come forward on its own in an app with no Dock icon.
        //
        // Detection is an autoclosure so a returning user — the overwhelmingly
        // common case — never probes the file system for agent configuration.
        let presenter = onboardingPresenter
        DispatchQueue.main.async {
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
            .onOpenURL { url in
                urlSchemeReceiver.handle(url)
            }
            .onChange(of: aiPreferences, initial: true) { _, preferences in
                settingsStore.aiIntegrationPreferences = preferences
                urlSchemeReceiver.preferences = preferences
            }
            .onChange(of: generalPreferences) { _, preferences in
                settingsStore.generalPreferences = preferences
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
