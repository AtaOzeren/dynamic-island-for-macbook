import KerNotchCore
import SwiftUI

public enum AIHookAction: Equatable, Sendable {
    case install
    case uninstall
    case manualSetup

    var title: String {
        switch self {
        case .install: localized("Install hook")
        case .uninstall: localized("Uninstall hook")
        case .manualSetup: localized("Manual setup")
        }
    }

    var symbolName: String {
        switch self {
        case .install: "plus.circle"
        case .uninstall: "trash"
        case .manualSetup: "doc.text"
        }
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
    private let hookStates: [IPCAgentID: HookInstallationState]
    private let metrics: SettingsPaneMetrics
    private let onPreferencesChange: (AIIntegrationPreferences) -> Void
    private let onHookAction: (IPCAgentID, AIHookAction) -> Void
    private let onPreviewAttentionGlow: () -> Void

    public init(
        preferences: Binding<AIIntegrationPreferences>,
        hookStates: [IPCAgentID: HookInstallationState] = [:],
        metrics: SettingsPaneMetrics = .default,
        onPreferencesChange: @escaping (AIIntegrationPreferences) -> Void = { _ in },
        onHookAction: @escaping (IPCAgentID, AIHookAction) -> Void = { _, _ in },
        onPreviewAttentionGlow: @escaping () -> Void = {}
    ) {
        self._preferences = preferences
        self.hookStates = hookStates
        self.metrics = metrics
        self.onPreferencesChange = onPreferencesChange
        self.onHookAction = onHookAction
        self.onPreviewAttentionGlow = onPreviewAttentionGlow
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
            set: { isEnabled in
                let wasEnabled = preferences.isEnabled(agentID)
                var updatedPreferences = preferences
                updatedPreferences.setAgent(agentID, enabled: isEnabled)
                preferences = updatedPreferences
                onPreferencesChange(updatedPreferences)

                guard isEnabled, !wasEnabled, hookAction(for: agentID) == .install else {
                    return
                }
                onHookAction(agentID, .install)
            }
        )
    }

    public func binding(for eventClass: AIEventClass) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(eventClass) },
            set: { isEnabled in
                var updatedPreferences = preferences
                updatedPreferences.setEventClass(eventClass, enabled: isEnabled)
                preferences = updatedPreferences
                onPreferencesChange(updatedPreferences)
            }
        )
    }

    /// The attention glow's switch. Presentation only, so it publishes the
    /// same value the other rows do and nothing more.
    public var attentionGlowBinding: Binding<Bool> {
        Binding(
            get: { preferences.showsAttentionGlow },
            set: { showsAttentionGlow in
                var updatedPreferences = preferences
                updatedPreferences.showsAttentionGlow = showsAttentionGlow
                preferences = updatedPreferences
                onPreferencesChange(updatedPreferences)
            }
        )
    }

    /// Plays the glow once on the island. Exposed so a test can drive the same
    /// path a press takes without rendering into a window server.
    public func previewAttentionGlow() {
        onPreviewAttentionGlow()
    }

    public func hookAction(for agentID: IPCAgentID) -> AIHookAction {
        switch hookStates[agentID] ?? .configurationMissing {
        case .configurationMissing, .hookAbsent: .install
        case .hookInstalled: .uninstall
        case .configurationUnreadable: .manualSetup
        }
    }

    public func performHookAction(for agentID: IPCAgentID) {
        onHookAction(agentID, hookAction(for: agentID))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            agentSection
            Divider()
            eventSection
            Divider()
            attentionGlowSection
        }
        .settingsPaneFrame(metrics)
    }

    private var agentSection: some View {
        SettingsSection(
            title: localized("Agents"),
            caption: localized("KerNotch shows nothing for an agent until you enable it here."),
            metrics: metrics
        ) {
            ForEach(IPCAgentID.allCases, id: \.self) { agentID in
                HStack {
                    Toggle(agentID.displayName, isOn: binding(for: agentID))
                    Spacer(minLength: metrics.rowSpacing)
                    let action = hookAction(for: agentID)
                    Button {
                        performHookAction(for: agentID)
                    } label: {
                        Label(action.title, systemImage: action.symbolName)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(action.title)
                }
            }
        }
    }

    private var eventSection: some View {
        SettingsSection(
            title: localized("Events"),
            caption: localized("A disabled event never reaches the notch — it is dropped on arrival."),
            metrics: metrics
        ) {
            ForEach(AIEventClass.allCases, id: \.self) { eventClass in
                Toggle(eventClass.displayName, isOn: binding(for: eventClass))
            }
        }
        .disabled(!isEventSectionEnabled)
    }

    /// The switch is disabled with the events for the same reason: with every
    /// agent off there is nothing that could glow. The test button is not — it
    /// is how someone sees what the switch does before deciding to enable
    /// anything.
    private var attentionGlowSection: some View {
        SettingsSection(
            title: localized("Island glow"),
            caption: localized(
                "A soft light runs around the small island when an agent finishes, asks for input, or fails."
            ),
            metrics: metrics
        ) {
            HStack {
                Toggle(localized("Show glow"), isOn: attentionGlowBinding)
                    .disabled(!isEventSectionEnabled)
                Spacer(minLength: metrics.rowSpacing)
                Button(action: previewAttentionGlow) {
                    Label(localized("Test glow"), systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(localized("Test glow"))
            }
        }
    }
}
