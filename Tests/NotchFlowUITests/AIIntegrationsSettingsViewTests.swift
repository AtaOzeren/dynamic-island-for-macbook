import Foundation
import SwiftUI
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// The UI half of todo 58: a switch must move the value both receivers read, so
/// flipping it off is what makes the event stop arriving — not merely what makes
/// it stop showing.
@Suite("AIIntegrationsSettingsView")
@MainActor
struct AIIntegrationsSettingsViewTests {
    private final class Store: @unchecked Sendable {
        var preferences: AIIntegrationPreferences = .default

        var binding: Binding<AIIntegrationPreferences> {
            Binding(get: { self.preferences }, set: { self.preferences = $0 })
        }
    }

    @Test("an agent switch writes through to the preferences")
    func agentToggleWritesThrough() {
        let store = Store()
        let view = AIIntegrationsSettingsView(preferences: store.binding)

        view.binding(for: .claudeCode).wrappedValue = true

        #expect(store.preferences.isEnabled(.claudeCode))

        view.binding(for: .claudeCode).wrappedValue = false

        #expect(!store.preferences.isEnabled(.claudeCode))
    }

    @Test("an agent switch publishes the persisted preference value immediately")
    func agentTogglePublishesPreferenceChange() {
        let store = Store()
        var published: [AIIntegrationPreferences] = []
        let view = AIIntegrationsSettingsView(
            preferences: store.binding,
            onPreferencesChange: { published.append($0) }
        )

        view.binding(for: .codex).wrappedValue = true

        #expect(published.count == 1)
        #expect(published.first?.isEnabled(.codex) == true)
    }

    @Test("an event switch writes through to the preferences")
    func eventToggleWritesThrough() {
        let store = Store()
        let view = AIIntegrationsSettingsView(preferences: store.binding)

        view.binding(for: .toolActivity).wrappedValue = true

        #expect(store.preferences.isEnabled(.toolActivity))

        view.binding(for: .taskStarted).wrappedValue = false

        #expect(!store.preferences.isEnabled(.taskStarted))
    }

    @Test("an event switch publishes the persisted preference value immediately")
    func eventTogglePublishesPreferenceChange() {
        let store = Store()
        var published: [AIIntegrationPreferences] = []
        let view = AIIntegrationsSettingsView(
            preferences: store.binding,
            onPreferencesChange: { published.append($0) }
        )

        view.binding(for: .toolActivity).wrappedValue = true

        #expect(published.count == 1)
        #expect(published.first?.isEnabled(.toolActivity) == true)
    }

    @Test("a switched-off event stops its message reaching an activity")
    func disabledEventBlocksItsMessage() {
        let store = Store()
        store.preferences.setAgent(.claudeCode, enabled: true)
        let view = AIIntegrationsSettingsView(preferences: store.binding)
        let message = IPCMessage(
            schemaVersion: "1.0",
            agentId: .claudeCode,
            sessionId: UUID(
                uuid: (0x9E, 0x1C, 0x85, 0x18, 0x9D, 0xA0, 0x4E, 0x93, 0x83, 0x13, 0x26, 0x37, 0xD4, 0xE5, 0x76, 0x9F)
            ),
            state: .completed,
            detail: "Done",
            toolName: nil,
            progress: nil,
            timestamp: Date(timeIntervalSinceReferenceDate: 0)
        )

        #expect(store.preferences.allows(message))

        view.binding(for: .taskCompleted).wrappedValue = false

        #expect(!store.preferences.allows(message))
    }

    @Test("event switches stay inert while every agent is off")
    func eventSectionFollowsAgentEnablement() {
        let store = Store()
        let view = AIIntegrationsSettingsView(preferences: store.binding)

        #expect(!view.isEventSectionEnabled)

        view.binding(for: .codex).wrappedValue = true

        #expect(AIIntegrationsSettingsView(preferences: store.binding).isEventSectionEnabled)
    }

    @Test("hook action follows installation state")
    func hookActionFollowsInstallationState() {
        let store = Store()
        let absent = AIIntegrationsSettingsView(
            preferences: store.binding,
            hookStates: [.codex: .hookAbsent]
        )
        #expect(absent.hookAction(for: .codex) == .install)

        let installed = AIIntegrationsSettingsView(
            preferences: store.binding,
            hookStates: [.codex: .hookInstalled]
        )
        #expect(installed.hookAction(for: .codex) == .uninstall)

        let unreadable = AIIntegrationsSettingsView(
            preferences: store.binding,
            hookStates: [.codex: .configurationUnreadable]
        )
        #expect(unreadable.hookAction(for: .codex) == .manualSetup)
    }

    @Test("hook button dispatches explicit user action")
    func hookButtonDispatchesAction() {
        let store = Store()
        var received: [(IPCAgentID, AIHookAction)] = []
        let view = AIIntegrationsSettingsView(
            preferences: store.binding,
            hookStates: [.claudeCode: .hookAbsent],
            onHookAction: { received.append(($0, $1)) }
        )

        view.performHookAction(for: .claudeCode)

        #expect(received.count == 1)
        #expect(received.first?.0 == .claudeCode)
        #expect(received.first?.1 == .install)
    }

    @Test("enabling an agent automatically installs its missing hook once")
    func enablingAgentInstallsMissingHookOnce() {
        let store = Store()
        var received: [(IPCAgentID, AIHookAction)] = []
        let view = AIIntegrationsSettingsView(
            preferences: store.binding,
            hookStates: [.codex: .hookAbsent],
            onHookAction: { received.append(($0, $1)) }
        )

        view.binding(for: .codex).wrappedValue = true
        view.binding(for: .codex).wrappedValue = true

        #expect(store.preferences.isEnabled(.codex))
        #expect(received.count == 1)
        #expect(received.first?.0 == .codex)
        #expect(received.first?.1 == .install)
    }

    @Test("an already installed hook is not reinstalled when its agent is enabled")
    func enablingAgentKeepsInstalledHook() {
        let store = Store()
        var received: [(IPCAgentID, AIHookAction)] = []
        let view = AIIntegrationsSettingsView(
            preferences: store.binding,
            hookStates: [.claudeCode: .hookInstalled],
            onHookAction: { received.append(($0, $1)) }
        )

        view.binding(for: .claudeCode).wrappedValue = true

        #expect(store.preferences.isEnabled(.claudeCode))
        #expect(received.isEmpty)
    }

    @Test("disabling an agent does not silently uninstall its hook")
    func disablingAgentKeepsHookInstalled() {
        let store = Store()
        store.preferences.setAgent(.opencode, enabled: true)
        var received: [(IPCAgentID, AIHookAction)] = []
        let view = AIIntegrationsSettingsView(
            preferences: store.binding,
            hookStates: [.opencode: .hookInstalled],
            onHookAction: { received.append(($0, $1)) }
        )

        view.binding(for: .opencode).wrappedValue = false

        #expect(!store.preferences.isEnabled(.opencode))
        #expect(received.isEmpty)
    }
}
