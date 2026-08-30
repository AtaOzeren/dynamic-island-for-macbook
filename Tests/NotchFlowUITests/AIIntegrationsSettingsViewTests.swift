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

    @Test("an event switch writes through to the preferences")
    func eventToggleWritesThrough() {
        let store = Store()
        let view = AIIntegrationsSettingsView(preferences: store.binding)

        view.binding(for: .toolActivity).wrappedValue = true

        #expect(store.preferences.isEnabled(.toolActivity))

        view.binding(for: .taskStarted).wrappedValue = false

        #expect(!store.preferences.isEnabled(.taskStarted))
    }

    @Test("a switched-off event stops its message reaching an activity")
    func disabledEventBlocksItsMessage() {
        let store = Store()
        store.preferences.setAgent(.claudeCode, enabled: true)
        let view = AIIntegrationsSettingsView(preferences: store.binding)
        let message = IPCMessage(
            schemaVersion: "1.0",
            agentId: .claudeCode,
            sessionId: UUID(uuidString: "9E1C8518-9DA0-4E93-8313-2637D4E5769F")!,
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
}
