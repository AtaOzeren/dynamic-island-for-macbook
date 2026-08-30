import NotchFlowCore
import SwiftUI

/// The General pane: display target, launch at login, appearance, reduced
/// motion.
///
/// Like the AI Integrations pane, it owns no state — it edits the binding the
/// composition root hands it, so the window and the store never hold two
/// generations of the same edit.
public struct GeneralSettingsView: View {
    @Binding private var preferences: GeneralPreferences
    private let availableDisplays: [DisplayDescription]
    private let metrics: SettingsPaneMetrics

    public init(
        preferences: Binding<GeneralPreferences>,
        availableDisplays: [DisplayDescription],
        metrics: SettingsPaneMetrics = .default
    ) {
        self._preferences = preferences
        self.availableDisplays = availableDisplays
        self.metrics = metrics
    }

    /// The picker's rows: the two rules, then one row per attached display.
    ///
    /// Built from the displays passed in rather than read from `NSScreen` here,
    /// so a test can enumerate the picker without a second monitor plugged in.
    public var displayOptions: [DisplayPreference] {
        [.automatic, .builtIn] + availableDisplays.map { .named($0.name) }
    }

    public func title(for preference: DisplayPreference) -> String {
        switch preference {
        case .automatic: localized("Automatic")
        case .builtIn: localized("Built-in display")
        case let .named(name): name
        }
    }

    public var displayTarget: Binding<DisplayPreference> {
        Binding(
            get: { preferences.displayTarget },
            set: { preferences.displayTarget = $0 }
        )
    }

    public var launchAtLogin: Binding<Bool> {
        Binding(
            get: { preferences.launchAtLogin },
            set: { preferences.launchAtLogin = $0 }
        )
    }

    public var appearance: Binding<SettingsAppearance> {
        Binding(
            get: { preferences.appearance },
            set: { preferences.appearance = $0 }
        )
    }

    public var reducedMotion: Binding<ReducedMotionSetting> {
        Binding(
            get: { ReducedMotionSetting(override: preferences.reducedMotionOverride) },
            set: { preferences.reducedMotionOverride = $0.override }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            displaySection
            Divider()
            appearanceSection
            Divider()
            startupSection
        }
        .settingsPaneFrame(metrics)
    }

    private var displaySection: some View {
        SettingsSection(
            title: localized("Display"),
            caption: localized("Automatic follows the display with the notch, then falls back to the built-in screen."),
            metrics: metrics
        ) {
            Picker(localized("Show the island on"), selection: displayTarget) {
                ForEach(displayOptions, id: \.self) { option in
                    Text(title(for: option)).tag(option)
                }
            }
        }
    }

    private var appearanceSection: some View {
        SettingsSection(
            title: localized("Appearance"),
            caption: localized("Reduced motion also follows the system accessibility setting unless you override it."),
            metrics: metrics
        ) {
            Picker(localized("Theme"), selection: appearance) {
                ForEach(SettingsAppearance.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            Picker(localized("Motion"), selection: reducedMotion) {
                ForEach(ReducedMotionSetting.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
        }
    }

    private var startupSection: some View {
        SettingsSection(
            title: localized("Startup"),
            caption: localized("NotchFlow has no Dock icon — it lives in the menu bar whether or not it starts at login."),
            metrics: metrics
        ) {
            Toggle(localized("Launch at login"), isOn: launchAtLogin)
        }
    }
}
