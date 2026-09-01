import Foundation
import Testing

@testable import NotchFlowCore

@Suite("Loopback listener policy")
struct LoopbackListenerPolicyTests {
    private static let defaultSessionID = UUID(
        uuid: (0x9E, 0x1C, 0x85, 0x18, 0x9D, 0xA0, 0x4E, 0x93, 0x83, 0x13, 0x26, 0x37, 0xD4, 0xE5, 0x76, 0x9F)
    )

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSinceReferenceDate: 0)

        func advance(by interval: TimeInterval) {
            now = now.addingTimeInterval(interval)
        }
    }

    @Test("accepts only POST requests to the AI status route")
    func routeGate() {
        let policy = LoopbackListenerPolicy(preferences: .init(enabledAgentIDs: [.claudeCode]))

        #expect(policy.rejection(method: "POST", path: "/ai-status") == nil)
        #expect(policy.rejection(method: "GET", path: "/ai-status") == .methodNotAllowed)
        #expect(policy.rejection(method: "POST", path: "/other") == .routeNotFound)
    }

    @Test("ignores messages from disabled agents")
    func disabledAgentGate() {
        var policy = LoopbackListenerPolicy(preferences: .init(enabledAgentIDs: [.codex]))

        #expect(policy.evaluate(Self.payload(agentID: "claude-code")) == .ignored)
    }

    @Test("ignores messages from unrecognized agents")
    func unrecognizedAgentGate() {
        var policy = LoopbackListenerPolicy(preferences: .init(enabledAgentIDs: [.claudeCode]))

        #expect(policy.evaluate(Self.payload(agentID: "unknown")) == .ignored)
    }

    @Test("ignores an event class the user disabled")
    func disabledEventClassGate() {
        var policy = LoopbackListenerPolicy(
            preferences: .init(
                enabledAgentIDs: [.claudeCode],
                enabledEventClasses: [.taskCompleted]
            )
        )

        #expect(policy.evaluate(Self.payload(state: "usingTool")) == .ignored)
        #expect(policy.evaluate(Self.payload(state: "completed")).isAccepted)
    }

    /// The acceptance criterion's other half: `usingTool` is off by default, so
    /// a hook that emits it against untouched settings must produce nothing.
    @Test("ignores tool activity under the documented defaults")
    func toolActivityDefaultsOff() {
        var policy = LoopbackListenerPolicy(
            preferences: .init(enabledAgentIDs: [.claudeCode])
        )

        #expect(policy.evaluate(Self.payload(state: "usingTool")) == .ignored)
        #expect(policy.evaluate(Self.payload(state: "thinking")).isAccepted)
    }

    /// Silencing an event must not spend its session's rate-limit budget, or a
    /// flood of disabled messages would suppress the ones the user kept on.
    @Test("a dropped event leaves the session's rate limit untouched")
    func droppedEventDoesNotConsumeRateLimit() {
        var policy = LoopbackListenerPolicy(
            preferences: .init(enabledAgentIDs: [.claudeCode]),
            configuration: LoopbackListenerPolicyConfiguration(minimumInterval: 1_000)
        )

        #expect(policy.evaluate(Self.payload(state: "usingTool")) == .ignored)
        #expect(policy.evaluate(Self.payload(state: "completed")).isAccepted)
    }

    /// `idle` ends an activity and has no switch of its own; if a disabled
    /// neighbour could suppress it, a stale agent card would never clear.
    @Test("passes states no event class names")
    func unswitchedStatesAlwaysPass() {
        var policy = LoopbackListenerPolicy(
            preferences: .init(enabledAgentIDs: [.claudeCode], enabledEventClasses: [])
        )

        #expect(policy.evaluate(Self.payload(state: "working")).isAccepted)
    }

    @Test("allows one message per session during each interval")
    func perSessionRateLimit() {
        let clock = Clock()
        let configuration = LoopbackListenerPolicyConfiguration(
            minimumInterval: 1,
            now: { clock.now }
        )
        var policy = LoopbackListenerPolicy(
            preferences: .init(enabledAgentIDs: [.claudeCode]),
            configuration: configuration
        )
        let firstSession = Self.defaultSessionID
        let secondSession = UUID(
            uuid: (0xAB, 0xF5, 0xA0, 0xFC, 0xE8, 0xF8, 0x40, 0x95, 0x85, 0x86, 0xBC, 0x88, 0xC0, 0xF5, 0x10, 0x67)
        )

        #expect(policy.evaluate(Self.payload(sessionID: firstSession)).isAccepted)
        #expect(policy.evaluate(Self.payload(sessionID: firstSession)) == .rejected(.rateLimited))
        #expect(policy.evaluate(Self.payload(sessionID: secondSession)).isAccepted)

        clock.advance(by: 1)

        #expect(policy.evaluate(Self.payload(sessionID: firstSession)).isAccepted)
        #expect(policy.evaluate(Self.payload(sessionID: firstSession)) == .rejected(.rateLimited))
    }

    /// A fast tool call puts `completed` within milliseconds of the `working`
    /// before it. Dropping that leaves the island showing an agent that
    /// finished as still running, with nothing later to correct it.
    @Test("never rate-limits a change of state")
    func stateChangesBypassTheRateLimit() {
        let clock = Clock()
        var policy = LoopbackListenerPolicy(
            preferences: .init(
                enabledAgentIDs: [.claudeCode],
                enabledEventClasses: Set(AIEventClass.allCases)
            ),
            configuration: LoopbackListenerPolicyConfiguration(
                minimumInterval: 1_000,
                now: { clock.now }
            )
        )

        #expect(policy.evaluate(Self.payload(state: "usingTool")).isAccepted)
        #expect(policy.evaluate(Self.payload(state: "working")).isAccepted)
        #expect(policy.evaluate(Self.payload(state: "completed")).isAccepted)
    }

    /// The limiter still exists: an agent repeating one state as fast as it can
    /// must not drive a redraw per message.
    @Test("still rate-limits a repeated state")
    func repeatedStatesAreRateLimited() {
        let clock = Clock()
        var policy = LoopbackListenerPolicy(
            preferences: .init(
                enabledAgentIDs: [.claudeCode],
                enabledEventClasses: Set(AIEventClass.allCases)
            ),
            configuration: LoopbackListenerPolicyConfiguration(
                minimumInterval: 1,
                now: { clock.now }
            )
        )

        #expect(policy.evaluate(Self.payload(state: "usingTool")).isAccepted)
        #expect(policy.evaluate(Self.payload(state: "usingTool")) == .rejected(.rateLimited))

        clock.advance(by: 1)

        #expect(policy.evaluate(Self.payload(state: "usingTool")).isAccepted)
    }

    /// Two agents can be mid-task at once; one being chatty must not silence
    /// the other.
    @Test("rate limits each session independently across state changes")
    func rateLimitIsPerSession() {
        let other = UUID(
            uuid: (0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x47, 0x88, 0x89, 0x9A, 0xAB, 0xBC, 0xCD, 0xDE, 0xEF, 0xF0)
        )
        var policy = LoopbackListenerPolicy(
            preferences: .init(
                enabledAgentIDs: [.claudeCode],
                enabledEventClasses: Set(AIEventClass.allCases)
            ),
            configuration: LoopbackListenerPolicyConfiguration(minimumInterval: 1_000)
        )

        #expect(policy.evaluate(Self.payload(state: "usingTool")).isAccepted)
        #expect(policy.evaluate(Self.payload(sessionID: other, state: "usingTool")).isAccepted)
        #expect(policy.evaluate(Self.payload(state: "usingTool")) == .rejected(.rateLimited))
    }

    @Test("rejects bodies above the validator size cap")
    func payloadSizeGate() {
        var policy = LoopbackListenerPolicy(preferences: .init(enabledAgentIDs: [.claudeCode]))
        let oversizedBody = Data(
            repeating: 0x20,
            count: IPCMessageValidator.maximumPayloadByteCount + 1
        )

        #expect(policy.evaluate(oversizedBody) == .rejected(.payloadTooLarge))
    }

    @Test("rejects malformed bodies without partially accepting them")
    func malformedPayload() {
        var policy = LoopbackListenerPolicy(preferences: .init(enabledAgentIDs: [.claudeCode]))

        #expect(policy.evaluate(Data("not-json".utf8)) == .rejected(.invalidPayload))
    }

    private static func payload(
        agentID: String = "claude-code",
        sessionID: UUID = defaultSessionID,
        state: String = "working"
    ) -> Data {
        let object: [String: Any] = [
            "schemaVersion": "1.0",
            "agentId": agentID,
            "sessionId": sessionID.uuidString,
            "state": state,
            "detail": "Running tests",
            "timestamp": "2026-08-30T00:00:00Z",
        ]
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            preconditionFailure("Test payload must be JSON serializable: \(error)")
        }
    }
}
