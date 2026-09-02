import Foundation
import Testing

@testable import NotchFlowCore

@Suite("IPCMessage")
struct IPCMessageTests {
    @Test("decodes a valid version 1.0 message")
    func validMessage() throws {
        let message = try IPCMessageValidator().decode(payload())

        #expect(message.schemaVersion == "1.0")
        #expect(message.agentId == .claudeCode)
        #expect(message.sessionId == UUID(uuidString: "9E1C8518-9DA0-4E93-8313-2637D4E5769F"))
        #expect(message.state == .usingTool)
        #expect(message.detail == "Running test suite")
        #expect(message.toolName == "Bash")
        #expect(message.progress == 0.5)
        #expect(message.timestamp == Date(timeIntervalSince1970: 1_788_004_800))
    }

    @Test("rejects an unknown schema version")
    func unknownSchemaVersion() {
        expectValidationError(.unsupportedSchemaVersion("2.0")) {
            try IPCMessageValidator().decode(payload(replacing: ["schemaVersion": "2.0"]))
        }
    }

    @Test(
        "rejects each missing required field",
        arguments: ["schemaVersion", "agentId", "sessionId", "state", "detail", "timestamp"]
    )
    func missingRequiredField(field: String) {
        expectValidationError(.missingRequiredField(field)) {
            try IPCMessageValidator().decode(payload(removing: field))
        }
    }

    @Test("rejects a payload above the byte limit")
    func oversizedPayload() {
        let oversizedPayload = Data(
            repeating: UInt8(ascii: " "),
            count: IPCMessageValidator.maximumPayloadByteCount + 1
        )

        expectValidationError(
            .oversizedPayload(maximumByteCount: IPCMessageValidator.maximumPayloadByteCount)
        ) {
            try IPCMessageValidator().decode(oversizedPayload)
        }
    }

    @Test("rejects a disallowed agent id")
    func disallowedAgentId() {
        expectValidationError(.disallowedAgentId("future-agent")) {
            try IPCMessageValidator().decode(payload(replacing: ["agentId": "future-agent"]))
        }
    }

    @Test("accepts display text at the character limit")
    func detailAtCharacterLimit() throws {
        let detail = String(repeating: "a", count: IPCMessageValidator.maximumDisplayTextCharacterCount)

        let message = try IPCMessageValidator().decode(payload(replacing: ["detail": detail]))

        #expect(message.detail == detail)
    }

    @Test("rejects display text above the character limit")
    func detailAboveCharacterLimit() {
        let detail = String(
            repeating: "a",
            count: IPCMessageValidator.maximumDisplayTextCharacterCount + 1
        )

        expectValidationError(
            .stringTooLong(
                field: "detail",
                maximumCharacterCount: IPCMessageValidator.maximumDisplayTextCharacterCount
            )
        ) {
            try IPCMessageValidator().decode(payload(replacing: ["detail": detail]))
        }
    }

    @Test("rejects control characters in received strings")
    func controlCharacters() {
        expectValidationError(.unsafeString(field: "detail")) {
            try IPCMessageValidator().decode(payload(replacing: ["detail": "Running\u{0000}tests"]))
        }
    }

    @Test("rejects shell metacharacters in received strings")
    func shellMetacharacters() {
        expectValidationError(.unsafeString(field: "detail")) {
            try IPCMessageValidator().decode(
                payload(replacing: ["detail": "$(touch /tmp/notchflow-pwned)"])
            )
        }
    }

    @Test("rejects invalid UTF-8 without crashing")
    func invalidUTF8() {
        let invalidUTF8 = Data([0x7B, 0x22, 0x64, 0x65, 0x74, 0x61, 0x69, 0x6C, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D])

        expectValidationError(.malformedPayload) {
            try IPCMessageValidator().decode(invalidUTF8)
        }
    }

    @Test("accepts progress at both documented boundaries", arguments: [0.0, 1.0])
    func progressAtBoundary(progress: Double) throws {
        let message = try IPCMessageValidator().decode(payload(replacing: ["progress": progress]))

        #expect(message.progress == progress)
    }

    @Test("rejects progress outside the documented range", arguments: [-0.001, 1.001])
    func progressOutsideBoundary(progress: Double) {
        expectValidationError(.invalidProgress(progress)) {
            try IPCMessageValidator().decode(payload(replacing: ["progress": progress]))
        }
    }

    @Test("rejects fields outside the message schema")
    func additionalField() {
        expectValidationError(.unexpectedField("command")) {
            try IPCMessageValidator().decode(payload(replacing: ["command": "whoami"]))
        }
    }

    private func expectValidationError(
        _ expectedError: IPCMessageValidationError,
        decoding operation: () throws -> IPCMessage
    ) {
        do {
            _ = try operation()
            Issue.record("Expected validation to fail with \(expectedError)")
        } catch let error as IPCMessageValidationError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected IPCMessageValidationError, got \(error)")
        }
    }

    private func payload(
        replacing replacements: [String: Any] = [:],
        removing removedField: String? = nil
    ) throws -> Data {
        var object: [String: Any] = [
            "schemaVersion": "1.0",
            "agentId": "claude-code",
            "sessionId": "9E1C8518-9DA0-4E93-8313-2637D4E5769F",
            "state": "usingTool",
            "detail": "Running test suite",
            "toolName": "Bash",
            "progress": 0.5,
            "timestamp": "2026-08-29T12:00:00Z",
        ]
        object.merge(replacements) { _, replacement in replacement }
        if let removedField {
            object.removeValue(forKey: removedField)
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    // MARK: - Sub-agent parentage

    /// The envelope has to carry which session a sub-agent belongs to, or the
    /// island counts every delegated session as another agent running.
    @Test("accepts a sub-agent naming its root session")
    func acceptsRootSessionId() throws {
        let root = UUID()
        let session = UUID()
        let message = try IPCMessageValidator().decode(
            Data(
                """
                {"schemaVersion":"1.0","agentId":"opencode","sessionId":"\(session.uuidString)",\
                "rootSessionId":"\(root.uuidString)","sessionName":"explore","state":"usingTool",\
                "detail":"Delegated","timestamp":"2026-09-02T10:00:00.000Z"}
                """.utf8)
        )

        #expect(message.rootSessionId == root)
        #expect(message.sessionName == "explore")
    }

    /// The two fields were added after 1.0 shipped. An older hook omits them and
    /// must keep working exactly as before.
    @Test("an envelope without the sub-agent fields is still a root session")
    func envelopeWithoutRootSessionIsARoot() throws {
        let message = try IPCMessageValidator().decode(
            Data(
                """
                {"schemaVersion":"1.0","agentId":"opencode","sessionId":"\(UUID().uuidString)",\
                "state":"working","detail":"Working","timestamp":"2026-09-02T10:00:00.000Z"}
                """.utf8)
        )

        #expect(message.rootSessionId == nil)
        #expect(message.sessionName == nil)
    }

    /// A session naming itself as its parent is a root written the long way, and
    /// must not read as a sub-agent of itself.
    @Test("a session that is its own root carries no parent")
    func selfParentedSessionIsARoot() throws {
        let session = UUID()
        let message = try IPCMessageValidator().decode(
            Data(
                """
                {"schemaVersion":"1.0","agentId":"opencode","sessionId":"\(session.uuidString)",\
                "rootSessionId":"\(session.uuidString)","state":"working","detail":"Working",\
                "timestamp":"2026-09-02T10:00:00.000Z"}
                """.utf8)
        )

        #expect(message.rootSessionId == nil)
        #expect(AIAgentActivity(message: message).isSubagent == false)
    }

    @Test("rejects a root session that is not a UUID")
    func rejectsMalformedRootSessionId() {
        #expect(throws: IPCMessageValidationError.invalidSessionId("not-a-uuid")) {
            try IPCMessageValidator().decode(
                Data(
                    """
                    {"schemaVersion":"1.0","agentId":"opencode","sessionId":"\(UUID().uuidString)",\
                    "rootSessionId":"not-a-uuid","state":"working","detail":"Working",\
                    "timestamp":"2026-09-02T10:00:00.000Z"}
                    """.utf8)
            )
        }
    }

    /// A sub-agent name reaches the screen, so it goes through the same guard
    /// every other display string does.
    @Test("rejects a sub-agent name carrying shell metacharacters")
    func rejectsUnsafeSessionName() {
        #expect(throws: IPCMessageValidationError.unsafeString(field: "sessionName")) {
            try IPCMessageValidator().decode(
                Data(
                    """
                    {"schemaVersion":"1.0","agentId":"opencode","sessionId":"\(UUID().uuidString)",\
                    "sessionName":"rm -rf $HOME","state":"working","detail":"Working",\
                    "timestamp":"2026-09-02T10:00:00.000Z"}
                    """.utf8)
            )
        }
    }
}
