import NotchFlowCore
import SwiftUI

/// The General pane: display target, menu bar visibility, launch at login,
/// appearance, and reduced motion.
///
/// Like the AI Integrations pane, it owns no state — it edits the binding the
/// composition root hands it, so the window and the store never hold two
/// generations of the same edit.
public struct GeneralSettingsView: View {
    @Binding private var preferences: GeneralPreferences
    private let availableDisplays: [DisplayDescription]
    private let metrics: SettingsPaneMetrics
    private let onRestart: () -> Void
    public let restartRequired: Bool

    public init(
        preferences: Binding<GeneralPreferences>,
        availableDisplays: [DisplayDescription],
        metrics: SettingsPaneMetrics = .default,
        restartRequired: Bool = false,
        onRestart: @escaping () -> Void = {}
    ) {
        self._preferences = preferences
        self.availableDisplays = availableDisplays
        self.metrics = metrics
        self.restartRequired = restartRequired
        self.onRestart = onRestart
    }

    /// The picker's rows: the two rules, then one row per attached display.
    ///
    /// Built from the displays passed in rather than read from `NSScreen` here,
    /// so a test can enumerate the picker without a second monitor plugged in.
    public var displayOptions: [DisplayPreference] {
        let nameCounts = Dictionary(grouping: availableDisplays, by: \.name).mapValues(\.count)
        var seenNames: [String: Int] = [:]
        let attached = availableDisplays.map { display in
            seenNames[display.name, default: 0] += 1
            let name = nameCounts[display.name, default: 0] > 1
                ? "\(display.name) (\(seenNames[display.name, default: 1]))"
                : display.name
            return DisplayPreference.identified(id: display.identifier, name: name)
        }
        let allDisplays: [DisplayPreference] = availableDisplays.count > 1 ? [.allDisplays] : []
        return [.automatic] + allDisplays + [.builtIn] + attached
    }

    public func title(for preference: DisplayPreference) -> String {
        switch preference {
        case .automatic: localized("Automatic")
        case .allDisplays: localized("All displays")
        case .builtIn: localized("Built-in display")
        case .named(let name): name
        case .identified(_, let name): name
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

    public var menuBarIconVisibility: Binding<Bool> {
        Binding(
            get: { preferences.showMenuBarIcon },
            set: { preferences.showMenuBarIcon = $0 }
        )
    }

    public var shouldShowMenuBarPlacementHint: Bool {
        preferences.showMenuBarIcon && availableDisplays.count > 1
    }

    func requestRestart() {
        onRestart()
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
            Divider()
            applicationSection
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
            Toggle(localized("Show menu bar icon"), isOn: menuBarIconVisibility)
            if shouldShowMenuBarPlacementHint {
                Text(localized(
                    "macOS shows this icon on the main menu bar. With multiple displays, it may appear on another screen."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
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
            caption: localized(
                "NotchFlow has no Dock icon. Open the app again to show Settings when its menu bar icon is hidden."),
            metrics: metrics
        ) {
            Toggle(localized("Launch at login"), isOn: launchAtLogin)
        }
    }

    private var applicationSection: some View {
        SettingsSection(
            title: localized("Application"),
            caption: restartRequired
                ? localized("Some changes need a restart. Finish your selections, then restart NotchFlow.")
                : localized("Restarts NotchFlow without changing your settings."),
            metrics: metrics
        ) {
            if restartRequired {
                Label(localized("Restart required"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Button(action: requestRestart) {
                Label(localized("Restart NotchFlow"), systemImage: "arrow.clockwise")
            }
        }
    }
}
