import CoreGraphics
import NotchFlowCore
import SwiftUI

/// The AI Integrations pane's fixed visual budget, the counterpart to
/// `ManualSetupMetrics` — one edit changes the pane's density.
public struct AIIntegrationsSettingsMetrics: Equatable, Sendable {
    public static let `default` = AIIntegrationsSettingsMetrics()

    public let contentInset: CGFloat
    public let sectionSpacing: CGFloat
    public let rowSpacing: CGFloat
    public let titleSize: CGFloat
    public let bodySize: CGFloat
    public let footnoteSize: CGFloat
    public let width: CGFloat

    public init(
        contentInset: CGFloat = 20,
        sectionSpacing: CGFloat = 16,
        rowSpacing: CGFloat = 8,
        titleSize: CGFloat = 15,
        bodySize: CGFloat = 12,
        footnoteSize: CGFloat = 11,
        width: CGFloat = 440
    ) {
        self.contentInset = contentInset
        self.sectionSpacing = sectionSpacing
        self.rowSpacing = rowSpacing
        self.titleSize = titleSize
        self.bodySize = bodySize
        self.footnoteSize = footnoteSize
        self.width = width
    }
}

/// The AI Integrations pane: one switch per agent, one per event class.
///
/// The pane owns no state. It reads and writes a binding the composition root
/// hands it, because the same value gates both receivers — a pane holding its
/// own copy would let the screen and the receivers disagree about what is
/// enabled, which is exactly the bug the toggles exist to prevent.
public struct AIIntegrationsSettingsView: View {
    @Binding private var preferences: AIIntegrationPreferences
    private let metrics: AIIntegrationsSettingsMetrics

    public init(
        preferences: Binding<AIIntegrationPreferences>,
        metrics: AIIntegrationsSettingsMetrics = .default
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
        .padding(metrics.contentInset)
        .frame(width: metrics.width, alignment: .leading)
    }

    private var agentSection: some View {
        section(
            title: "Agents",
            caption: "NotchFlow shows nothing for an agent until you enable it here."
        ) {
            ForEach(IPCAgentID.allCases, id: \.self) { agentID in
                Toggle(agentID.displayName, isOn: binding(for: agentID))
            }
        }
    }

    private var eventSection: some View {
        section(
            title: "Events",
            caption: "A disabled event never reaches the notch — it is dropped on arrival."
        ) {
            ForEach(AIEventClass.allCases, id: \.self) { eventClass in
                Toggle(eventClass.displayName, isOn: binding(for: eventClass))
            }
        }
        .disabled(!isEventSectionEnabled)
    }

    private func section(
        title: String,
        caption: String,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            Text(title)
                .font(.system(size: metrics.titleSize, weight: .semibold))
            Text(caption)
                .font(.system(size: metrics.footnoteSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            rows()
                .font(.system(size: metrics.bodySize))
                .toggleStyle(.switch)
        }
    }
}
