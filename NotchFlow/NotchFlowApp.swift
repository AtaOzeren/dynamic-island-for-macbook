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

    init() {
        musicProvider = makeMusicProvider()

        // The build's backend, reportable without a window, so CI can assert the
        // two configurations differ and a support conversation can ask for one
        // line of output rather than a screenshot.
        if CommandLine.arguments.contains("--print-music-backend") {
            print(musicProvider.backendName)
            exit(EXIT_SUCCESS)
        }
    }

    var body: some Scene {
        Settings {
            /// Stands in for the about pane until todo 60 builds the settings
            /// window; the backend name is the part that must survive that move.
            Text(verbatim: "NotchFlow — music backend: \(musicProvider.backendName)")
        }
    }
}
