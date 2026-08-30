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

    init() {
        let musicProvider = makeMusicProvider()
        let settingsStore = SettingsStore()
        self.musicProvider = musicProvider
        self.settingsStore = settingsStore
        _aiPreferences = State(initialValue: settingsStore.aiIntegrationPreferences)

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
            VStack(alignment: .leading) {
                AIIntegrationsSettingsView(preferences: $aiPreferences)

                /// Stands in for the about pane until todo 60 builds the settings
                /// window; the backend name is the part that must survive that move.
                Text(verbatim: "NotchFlow — music backend: \(musicProvider.backendName)")
            }
            .onOpenURL { url in
                urlSchemeReceiver.handle(url)
            }
            .onChange(of: aiPreferences, initial: true) { _, preferences in
                settingsStore.aiIntegrationPreferences = preferences
                urlSchemeReceiver.preferences = preferences
            }
        }
    }
}
