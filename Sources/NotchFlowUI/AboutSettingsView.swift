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

    public static var systemDefault: LanguageOption {
        LanguageOption(code: nil, displayName: localized("System default"))
    }

    /// The languages this build actually ships, read from the catalog rather
    /// than hardcoded.
    ///
    /// A literal list is a second place to remember: adding a language to the
    /// catalogs and forgetting the list yields a translation no user can
    /// select, and removing one yields a picker entry that resolves to English.
    /// `Bundle.module.localizations` cannot drift from the compiled catalog
    /// because it *is* the compiled catalog.
    public static var shipped: [LanguageOption] {
        options(forLanguageCodes: Bundle.module.localizations)
    }

    /// Named separately from `shipped` so the naming is testable without a
    /// compiled catalog: SwiftPM copies `.xcstrings` rather than compiling it,
    /// so under `swift test` `Bundle.module.localizations` reports only the
    /// source language and `shipped` can never be more than a smoke check.
    ///
    /// Each name is the language's own endonym — "Türkçe", not "Turkish" —
    /// because a user hunting for their language reads the list in that
    /// language, not in the one the app happens to be running in.
    static func options(forLanguageCodes codes: [String]) -> [LanguageOption] {
        codes
            .filter { $0 != "Base" }
            .compactMap { code in
                guard let name = Locale(identifier: code).localizedString(forLanguageCode: code) else {
                    return nil
                }
                return LanguageOption(code: code, displayName: name.localizedCapitalized)
            }
            .sorted { $0.displayName < $1.displayName }
    }
}

/// The About pane: version, build, music backend, and the language override.
public struct AboutSettingsView: View {
    @Binding private var languageOverride: String?
    private let information: AboutInformation
    private let languages: [LanguageOption]
    private let metrics: SettingsPaneMetrics
    public let restartRequired: Bool

    public init(
        information: AboutInformation,
        languageOverride: Binding<String?>,
        languages: [LanguageOption] = [.systemDefault],
        metrics: SettingsPaneMetrics = .default,
        restartRequired: Bool = false
    ) {
        self.information = information
        self._languageOverride = languageOverride
        self.languages = languages
        self.metrics = metrics
        self.restartRequired = restartRequired
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
            title: localized("NotchFlow"),
            caption: localized("MIT licensed. Music is read through the backend this build was compiled against."),
            metrics: metrics
        ) {
            LabeledContent(localized("Version"), value: "\(information.version) (\(information.build))")
            LabeledContent(localized("Music backend"), value: information.musicBackendName)
        }
    }

    private var languageSection: some View {
        SettingsSection(
            title: localized("Language"),
            caption: localized("Takes effect the next time NotchFlow starts."),
            metrics: metrics
        ) {
            Picker(localized("App language"), selection: selectedLanguage) {
                ForEach(languageOptions, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            if restartRequired {
                Label(localized("Restart required"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}
