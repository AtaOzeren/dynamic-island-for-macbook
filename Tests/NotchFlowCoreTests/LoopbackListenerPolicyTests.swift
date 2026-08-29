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
        let policy = LoopbackListenerPolicy(enabledAgentIDs: [.claudeCode])

        #expect(policy.rejection(method: "POST", path: "/ai-status") == nil)
        #expect(policy.rejection(method: "GET", path: "/ai-status") == .methodNotAllowed)
        #expect(policy.rejection(method: "POST", path: "/other") == .routeNotFound)
    }

    @Test("ignores messages from disabled agents")
    func disabledAgentGate() {
        var policy = LoopbackListenerPolicy(enabledAgentIDs: [.codex])

        #expect(policy.evaluate(Self.payload(agentID: "claude-code")) == .ignored)
    }

    @Test("ignores messages from unrecognized agents")
    func unrecognizedAgentGate() {
        var policy = LoopbackListenerPolicy(enabledAgentIDs: [.claudeCode])

        #expect(policy.evaluate(Self.payload(agentID: "unknown")) == .ignored)
    }

    @Test("allows one message per session during each interval")
    func perSessionRateLimit() {
        let clock = Clock()
        let configuration = LoopbackListenerPolicyConfiguration(
            minimumInterval: 1,
            now: { clock.now }
        )
        var policy = LoopbackListenerPolicy(
            enabledAgentIDs: [.claudeCode],
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
        var policy = LoopbackListenerPolicy(enabledAgentIDs: [.claudeCode])
        let oversizedBody = Data(
            repeating: 0x20,
            count: IPCMessageValidator.maximumPayloadByteCount + 1
        )

        #expect(policy.evaluate(oversizedBody) == .rejected(.payloadTooLarge))
    }

    @Test("rejects malformed bodies without partially accepting them")
    func malformedPayload() {
        var policy = LoopbackListenerPolicy(enabledAgentIDs: [.claudeCode])

        #expect(policy.evaluate(Data("not-json".utf8)) == .rejected(.invalidPayload))
    }

    private static func payload(
        agentID: String = "claude-code",
        sessionID: UUID = UUID(uuidString: "9E1C8518-9DA0-4E93-8313-2637D4E5769F")!
    ) -> Data {
        let object: [String: Any] = [
            "schemaVersion": "1.0",
            "agentId": agentID,
            "sessionId": sessionID.uuidString,
            "state": "working",
            "detail": "Running tests",
            "timestamp": "2026-08-30T00:00:00Z"
        ]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
