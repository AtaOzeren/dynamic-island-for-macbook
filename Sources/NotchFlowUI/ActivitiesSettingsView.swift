import NotchFlowCore
import SwiftUI

/// The Activities pane: one switch per provider the user can turn off.
///
/// The switch does not merely hide a card — the composition root stops the
/// provider observing, which is why the caption names what stops rather than
/// what disappears.
public struct ActivitiesSettingsView: View {
    @Binding private var enabledIdentifiers: Set<ActivityProviderIdentifier>
    private let metrics: SettingsPaneMetrics

    public init(
        enabledIdentifiers: Binding<Set<ActivityProviderIdentifier>>,
        metrics: SettingsPaneMetrics = .default
    ) {
        self._enabledIdentifiers = enabledIdentifiers
        self.metrics = metrics
    }

    public func binding(for identifier: ActivityProviderIdentifier) -> Binding<Bool> {
        Binding(
            get: { enabledIdentifiers.contains(identifier) },
            set: { isEnabled in
                if isEnabled {
                    enabledIdentifiers.insert(identifier)
                } else {
                    enabledIdentifiers.remove(identifier)
                }
            }
        )
    }

    public var body: some View {
        SettingsSection(
            title: "Activities",
            caption: "A switched-off activity stops being observed, not just hidden.",
            metrics: metrics
        ) {
            ForEach(ActivityProviderIdentifier.allCases, id: \.self) { identifier in
                Toggle(isOn: binding(for: identifier)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(identifier.displayName)
                        Text(identifier.caption)
                            .font(.system(size: metrics.footnoteSize))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .settingsPaneFrame(metrics)
    }
}
