import Foundation
import Testing
@testable import NotchFlowCore

@Suite("Loopback listener policy")
struct LoopbackListenerPolicyTests {
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
        let firstSession = UUID(uuidString: "9E1C8518-9DA0-4E93-8313-2637D4E5769F")!
        let secondSession = UUID(uuidString: "ABF5A0FC-E8F8-4095-8586-BC88C0F51067")!

        #expect(policy.evaluate(Self.payload(sessionID: firstSession)).isAccepted)
        #expect(policy.evaluate(Self.payload(sessionID: firstSession)) == .rejected(.rateLimited))
        #expect(policy.evaluate(Self.payload(sessionID: secondSession)).isAccepted)

        clock.advance(by: 1)

        #expect(policy.evaluate(Self.payload(sessionID: firstSession)).isAccepted)
        #expect(policy.evaluate(Self.payload(sessionID: firstSession)) == .rejected(.rateLimited))
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
        sessionID: UUID = UUID(uuidString: "9E1C8518-9DA0-4E93-8313-2637D4E5769F")!,
        state: String = "working"
    ) -> Data {
        let object: [String: Any] = [
            "schemaVersion": "1.0",
            "agentId": agentID,
            "sessionId": sessionID.uuidString,
            "state": state,
            "detail": "Running tests",
            "timestamp": "2026-08-30T00:00:00Z"
        ]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
