import NotchFlowCore
import SwiftUI

/// The AI Integrations pane: one switch per agent, one per event class.
///
/// The pane owns no state. It reads and writes a binding the composition root
/// hands it, because the same value gates both receivers — a pane holding its
/// own copy would let the screen and the receivers disagree about what is
/// enabled, which is exactly the bug the toggles exist to prevent.
public struct AIIntegrationsSettingsView: View {
    @Binding private var preferences: AIIntegrationPreferences
    private let metrics: SettingsPaneMetrics

    public init(
        preferences: Binding<AIIntegrationPreferences>,
        metrics: SettingsPaneMetrics = .default
    ) {
        self._preferences = preferences
        self.metrics = metrics
    }

    /// Event switches are disabled while no agent is, because with every agent
    /// off there is nothing for them to gate; the row would otherwise read as a
    /// control that does nothing.
    public var isEventSectionEnabled: Bool {
        !preferences.enabledAgentIDs.isEmpty
    }

    public func binding(for agentID: IPCAgentID) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(agentID) },
            set: { preferences.setAgent(agentID, enabled: $0) }
        )
    }

    public func binding(for eventClass: AIEventClass) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(eventClass) },
            set: { preferences.setEventClass(eventClass, enabled: $0) }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            agentSection
            Divider()
            eventSection
        }
        .settingsPaneFrame(metrics)
    }

    private var agentSection: some View {
        SettingsSection(
            title: "Agents",
            caption: "NotchFlow shows nothing for an agent until you enable it here.",
            metrics: metrics
        ) {
            ForEach(IPCAgentID.allCases, id: \.self) { agentID in
                Toggle(agentID.displayName, isOn: binding(for: agentID))
            }
        }
    }

    private var eventSection: some View {
        SettingsSection(
            title: "Events",
            caption: "A disabled event never reaches the notch — it is dropped on arrival.",
            metrics: metrics
        ) {
            ForEach(AIEventClass.allCases, id: \.self) { eventClass in
                Toggle(eventClass.displayName, isOn: binding(for: eventClass))
            }
        }
        .disabled(!isEventSectionEnabled)
    }
}
