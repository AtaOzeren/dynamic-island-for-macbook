import NotchFlowCore
import SwiftUI

/// What the About pane reports about the running build.
///
/// Passed in rather than read from `Bundle.main` inside the view, on the same
/// rationale as `GeneralSettingsView.availableDisplays`: a test can assert the
/// pane renders the backend name without launching an app bundle, and the
/// composition root stays the only place that knows which backend it built.
public struct AboutInformation: Equatable, Sendable {
    public let version: String
    public let build: String
    public let musicBackendName: String

    public init(version: String, build: String, musicBackendName: String) {
        self.version = version
        self.build = build
        self.musicBackendName = musicBackendName
    }
}

/// A language the user can force NotchFlow into, overriding the system locale.
public struct LanguageOption: Equatable, Hashable, Sendable {
    /// `nil` is "follow the system", the documented default — the same
    /// nil-means-follow shape `reducedMotionOverride` uses.
    public let code: String?
    public let displayName: String

    public init(code: String?, displayName: String) {
        self.code = code
        self.displayName = displayName
    }

    public static let systemDefault = LanguageOption(code: nil, displayName: "System default")
}

/// The About pane: version, build, music backend, and the language override.
public struct AboutSettingsView: View {
    @Binding private var languageOverride: String?
    private let information: AboutInformation
    private let languages: [LanguageOption]
    private let metrics: SettingsPaneMetrics

    public init(
        information: AboutInformation,
        languageOverride: Binding<String?>,
        languages: [LanguageOption] = [.systemDefault],
        metrics: SettingsPaneMetrics = .default
    ) {
        self.information = information
        self._languageOverride = languageOverride
        self.languages = languages
        self.metrics = metrics
    }

    /// Always offers "System default" first, even when a caller passes a list
    /// that omits it — a picker a user cannot get back out of is a trap.
    public var languageOptions: [LanguageOption] {
        [.systemDefault] + languages.filter { $0.code != nil }
    }

    public var selectedLanguage: Binding<LanguageOption> {
        Binding(
            get: {
                languageOptions.first { $0.code == languageOverride } ?? .systemDefault
            },
            set: { languageOverride = $0.code }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            buildSection
            Divider()
            languageSection
        }
        .settingsPaneFrame(metrics)
    }

    private var buildSection: some View {
        SettingsSection(
            title: "NotchFlow",
            caption: "MIT licensed. Music is read through the backend this build was compiled against.",
            metrics: metrics
        ) {
            LabeledContent("Version", value: "\(information.version) (\(information.build))")
            LabeledContent("Music backend", value: information.musicBackendName)
        }
    }

    private var languageSection: some View {
        SettingsSection(
            title: "Language",
            caption: "Takes effect the next time NotchFlow starts.",
            metrics: metrics
        ) {
            Picker("App language", selection: selectedLanguage) {
                ForEach(languageOptions, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
        }
    }
}
