import NotchFlowCore
import SwiftUI

/// The four tabs of the settings window, in the order
/// `docs/08-settings-and-localization.md` lists them.
public enum SettingsTab: String, CaseIterable, Equatable, Hashable, Sendable {
    case general
    case activities
    case aiIntegrations
    case about

    public var displayName: String {
        switch self {
        case .general: localized("General")
        case .activities: localized("Activities")
        case .aiIntegrations: localized("AI Integrations")
        case .about: localized("About")
        }
    }

    public var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .activities: "square.stack"
        case .aiIntegrations: "sparkles"
        case .about: "info.circle"
        }
    }
}

/// The settings window's content: the four panes behind a `TabView`.
///
/// It holds no preference state of its own — every pane binds straight through
/// to the composition root's values, so the window is a layout decision and the
/// store stays the single source of truth. The only state here is which tab is
/// showing, which is not a preference.
public struct SettingsWindowView: View {
    @Binding private var general: GeneralPreferences
    @Binding private var enabledIdentifiers: Set<ActivityProviderIdentifier>
    @Binding private var aiPreferences: AIIntegrationPreferences
    @Binding private var languageOverride: String?
    @Binding private var musicAutomation: [MusicAutomationAccess]

    private let availableDisplays: [DisplayDescription]
    private let information: AboutInformation
    private let languages: [LanguageOption]
    private let metrics: SettingsPaneMetrics
    private let automationRequestsInProgress: Set<MusicPlayerTarget>
    private let onRequestAutomation: (MusicPlayerTarget) -> Void
    private let hookStates: [IPCAgentID: HookInstallationState]
    private let onAIPreferencesChange: (AIIntegrationPreferences) -> Void
    private let onHookAction: (IPCAgentID, AIHookAction) -> Void
    private let restartRequired: Bool
    private let onRestart: () -> Void

    @State private var selectedTab: SettingsTab = .general

    public init(
        general: Binding<GeneralPreferences>,
        enabledIdentifiers: Binding<Set<ActivityProviderIdentifier>>,
        aiPreferences: Binding<AIIntegrationPreferences>,
        languageOverride: Binding<String?>,
        availableDisplays: [DisplayDescription],
        information: AboutInformation,
        languages: [LanguageOption] = [.systemDefault],
        musicAutomation: Binding<[MusicAutomationAccess]> = .constant([]),
        hookStates: [IPCAgentID: HookInstallationState] = [:],
        metrics: SettingsPaneMetrics = .default,
        automationRequestsInProgress: Set<MusicPlayerTarget> = [],
        onRequestAutomation: @escaping (MusicPlayerTarget) -> Void = { _ in },
        onAIPreferencesChange: @escaping (AIIntegrationPreferences) -> Void = { _ in },
        onHookAction: @escaping (IPCAgentID, AIHookAction) -> Void = { _, _ in },
        restartRequired: Bool = false,
        onRestart: @escaping () -> Void = {}
    ) {
        self._general = general
        self._enabledIdentifiers = enabledIdentifiers
        self._aiPreferences = aiPreferences
        self._languageOverride = languageOverride
        self._musicAutomation = musicAutomation
        self.hookStates = hookStates
        self.availableDisplays = availableDisplays
        self.information = information
        self.languages = languages
        self.metrics = metrics
        self.automationRequestsInProgress = automationRequestsInProgress
        self.onRequestAutomation = onRequestAutomation
        self.onAIPreferencesChange = onAIPreferencesChange
        self.onHookAction = onHookAction
        self.restartRequired = restartRequired
        self.onRestart = onRestart
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                ScrollView {
                    pane(for: tab)
                }
                .tabItem {
                    Label(tab.displayName, systemImage: tab.symbolName)
                }
                .tag(tab)
            }
        }
        .frame(width: metrics.width)
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(
                preferences: $general,
                availableDisplays: availableDisplays,
                metrics: metrics,
                restartRequired: restartRequired,
                onRestart: onRestart
            )
        case .activities:
            ActivitiesSettingsView(
                enabledIdentifiers: $enabledIdentifiers,
                musicAutomation: $musicAutomation,
                metrics: metrics,
                automationRequestsInProgress: automationRequestsInProgress,
                onRequestAutomation: onRequestAutomation
            )
        case .aiIntegrations:
            AIIntegrationsSettingsView(
                preferences: $aiPreferences,
                hookStates: hookStates,
                metrics: metrics,
                onPreferencesChange: onAIPreferencesChange,
                onHookAction: onHookAction
            )
        case .about:
            AboutSettingsView(
                information: information,
                languageOverride: $languageOverride,
                languages: languages,
                metrics: metrics,
                restartRequired: restartRequired
            )
        }
    }
}
