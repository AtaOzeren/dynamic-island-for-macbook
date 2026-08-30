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

    @State private var aiPreferences: AIIntegrationPreferences
    @State private var generalPreferences: GeneralPreferences
    @State private var enabledIdentifiers: Set<ActivityProviderIdentifier>
    @State private var languageOverride: String?

    init() {
        let musicProvider = makeMusicProvider()
        let settingsStore = SettingsStore()
        self.musicProvider = musicProvider
        self.settingsStore = settingsStore
        _aiPreferences = State(initialValue: settingsStore.aiIntegrationPreferences)
        _generalPreferences = State(initialValue: settingsStore.generalPreferences)
        _enabledIdentifiers = State(initialValue: settingsStore.enabledProviderIdentifiers)
        _languageOverride = State(initialValue: settingsStore[.languageOverride])

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
    }

    var body: some Scene {
        Settings {
            SettingsWindowView(
                general: $generalPreferences,
                enabledIdentifiers: $enabledIdentifiers,
                aiPreferences: $aiPreferences,
                languageOverride: $languageOverride,
                availableDisplays: NSScreen.screens.map(DisplayDescription.init),
                information: aboutInformation
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

    private var aboutInformation: AboutInformation {
        let info = Bundle.main.infoDictionary
        return AboutInformation(
            version: info?["CFBundleShortVersionString"] as? String ?? "—",
            build: info?["CFBundleVersion"] as? String ?? "—",
            musicBackendName: musicProvider.backendName
        )
    }
}
