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
    private let urlSchemeReceiver = URLSchemeReceiver()

    /// Held here rather than in the pane so the switches and the receivers read
    /// one value; the documented defaults stand in until the settings store
    /// (todo 59) can persist the user's actual choices.
    @State private var aiPreferences = AIIntegrationPreferences.default

    init() {
        let musicProvider = makeMusicProvider()
        self.musicProvider = musicProvider

        // Every provider enabled, matching the documented defaults until the
        // settings store (todo 59) can supply the user's actual choices; the
        // registry takes the set as a parameter precisely so that swap is a
        // one-line change here rather than a change to the wiring.
        registry = ProviderComposition.makeRegistry(
            musicProvider: musicProvider,
            timerProvider: TimerProvider(),
            enabledIdentifiers: Set(ActivityProviderIdentifier.allCases)
        )

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
                urlSchemeReceiver.preferences = preferences
            }
        }
    }
}
