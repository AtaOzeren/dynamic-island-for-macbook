import Foundation
import Testing
@testable import NotchFlowCore

@Suite("AI integration preferences")
struct AIIntegrationPreferencesTests {
    private static func message(
        agentID: IPCAgentID = .claudeCode,
        state: AIAgentState = .thinking
    ) -> IPCMessage {
        IPCMessage(
            schemaVersion: "1.0",
            agentId: agentID,
            sessionId: UUID(uuidString: "9E1C8518-9DA0-4E93-8313-2637D4E5769F")!,
            state: state,
            detail: "Running tests",
            toolName: nil,
            progress: nil,
            timestamp: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    /// The two conservative defaults `docs/08` calls out by name.
    @Test("defaults to every agent off and tool activity off")
    func documentedDefaults() {
        let preferences = AIIntegrationPreferences.default

        #expect(preferences.enabledAgentIDs.isEmpty)
        #expect(preferences.isEnabled(.taskStarted))
        #expect(preferences.isEnabled(.taskCompleted))
        #expect(preferences.isEnabled(.taskError))
        #expect(preferences.isEnabled(.needsInput))
        #expect(!preferences.isEnabled(.toolActivity))
    }

    @Test("blocks every event from a disabled agent")
    func disabledAgentBlocksAllEvents() {
        let preferences = AIIntegrationPreferences(enabledAgentIDs: [.codex])

        for state in AIAgentState.allCases {
            #expect(!preferences.allows(Self.message(agentID: .claudeCode, state: state)))
        }
    }

    @Test("blocks only the disabled event class from an enabled agent")
    func disabledEventClassBlocksOneState() {
        let preferences = AIIntegrationPreferences(
            enabledAgentIDs: [.claudeCode],
            enabledEventClasses: [.taskStarted]
        )

        #expect(preferences.allows(Self.message(state: .thinking)))
        #expect(!preferences.allows(Self.message(state: .completed)))
        #expect(!preferences.allows(Self.message(state: .usingTool)))
    }

    /// `idle` ends an activity and `working` advances one; neither has a switch
    /// in the settings table, so neither may be silenced by an empty set.
    @Test("passes states the settings table gives no switch")
    func unswitchedStatesPassRegardless() {
        let preferences = AIIntegrationPreferences(
            enabledAgentIDs: [.claudeCode],
            enabledEventClasses: []
        )

        #expect(preferences.allows(Self.message(state: .idle)))
        #expect(preferences.allows(Self.message(state: .working)))
    }

    @Test("every switchable state maps to exactly one event class")
    func eventClassMappingIsTotal() {
        let mapped = AIAgentState.allCases.compactMap(\.eventClass)

        #expect(Set(mapped) == Set(AIEventClass.allCases))
        #expect(mapped.count == AIEventClass.allCases.count)
    }

    @Test("event class keys match the documented settings paths")
    func settingsKeyPaths() {
        #expect(AIEventClass.taskStarted.settingsKeyPath == "ai.events.taskStarted")
        #expect(AIEventClass.taskCompleted.settingsKeyPath == "ai.events.taskCompleted")
        #expect(AIEventClass.taskError.settingsKeyPath == "ai.events.taskError")
        #expect(AIEventClass.needsInput.settingsKeyPath == "ai.events.needsInput")
        #expect(AIEventClass.toolActivity.settingsKeyPath == "ai.events.toolActivity")
    }

    @Test("toggling round-trips through the setters")
    func settersRoundTrip() {
        var preferences = AIIntegrationPreferences.default

        preferences.setAgent(.opencode, enabled: true)
        preferences.setEventClass(.toolActivity, enabled: true)

        #expect(preferences.isEnabled(.opencode))
        #expect(preferences.isEnabled(.toolActivity))

        preferences.setAgent(.opencode, enabled: false)
        preferences.setEventClass(.toolActivity, enabled: false)

        #expect(!preferences.isEnabled(.opencode))
        #expect(!preferences.isEnabled(.toolActivity))
    }
}
