import Foundation
import Testing

@testable import NotchFlowCore

@Suite("AI agent session ledger")
struct AIAgentSessionLedgerTests {
    private static let session = UUID(
        uuid: (0x3A, 0x7B, 0x11, 0x02, 0xCC, 0xD1, 0x44, 0x9E, 0x8F, 0x20, 0x51, 0x63, 0x9A, 0xB4, 0x77, 0x0E)
    )
    private static let otherSession = UUID(
        uuid: (0x9F, 0x02, 0x8C, 0x41, 0x0D, 0x55, 0x4B, 0x10, 0xA3, 0x77, 0x62, 0x18, 0x4E, 0xC9, 0x30, 0x5B)
    )
    private static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("admits the first message a session sends")
    func firstMessageIsAdmitted() {
        var ledger = AIAgentSessionLedger()

        #expect(ledger.admit(Self.message(at: 0)) == .admit)
    }

    @Test("admits messages in order")
    func newerMessagesAreAdmitted() {
        var ledger = AIAgentSessionLedger()

        #expect(ledger.admit(Self.message(at: 0, state: .thinking)) == .admit)
        #expect(ledger.admit(Self.message(at: 1, state: .usingTool)) == .admit)
        #expect(ledger.admit(Self.message(at: 2, state: .completed)) == .admit)
    }

    /// The failure this exists to prevent: a `usingTool` overtaken in flight by
    /// the `completed` behind it would otherwise reinstate a finished agent as
    /// running, with no later message to correct it.
    @Test("drops a message older than one already applied")
    func staleMessagesAreDropped() {
        var ledger = AIAgentSessionLedger()

        #expect(ledger.admit(Self.message(at: 5, state: .completed)) == .admit)
        #expect(ledger.admit(Self.message(at: 4, state: .usingTool)) == .stale)
    }

    /// Two events inside one millisecond are ordinary at this resolution.
    /// Refusing the second would drop the state change the pair reports.
    @Test("admits a message sharing the newest timestamp")
    func equalTimestampsAreAdmitted() {
        var ledger = AIAgentSessionLedger()

        #expect(ledger.admit(Self.message(at: 3, state: .working)) == .admit)
        #expect(ledger.admit(Self.message(at: 3, state: .completed)) == .admit)
    }

    @Test("judges each session against its own timeline")
    func sessionsAreIndependent() {
        var ledger = AIAgentSessionLedger()

        #expect(ledger.admit(Self.message(at: 9)) == .admit)
        #expect(ledger.admit(Self.message(at: 1, session: Self.otherSession)) == .admit)
    }

    /// A session identifier reused after the previous life ended must not be
    /// judged against the timestamp that life left behind.
    @Test("forgetting a session clears its bookmark")
    func forgettingClearsTheBookmark() {
        var ledger = AIAgentSessionLedger()

        #expect(ledger.admit(Self.message(at: 9, state: .completed)) == .admit)
        ledger.forget(Self.session)

        #expect(ledger.trackedSessionCount == 0)
        #expect(ledger.admit(Self.message(at: 1, state: .thinking)) == .admit)
    }

    private static func message(
        at offset: TimeInterval,
        state: AIAgentState = .working,
        session: UUID = session
    ) -> IPCMessage {
        IPCMessage(
            schemaVersion: IPCMessageValidator.supportedSchemaVersion,
            agentId: .claudeCode,
            sessionId: session,
            state: state,
            detail: "Working",
            toolName: nil,
            progress: nil,
            timestamp: epoch.addingTimeInterval(offset)
        )
    }
}
