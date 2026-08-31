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
}
