import Foundation
import Testing
@testable import NotchFlowCore

@Suite("IPC URL Parser")
struct IPCURLParserTests {
    @Test("decodes a valid AI status URL")
    func validURL() throws {
        let message = try IPCURLParser().parse(url(payload: payload()))

        #expect(message.schemaVersion == "1.0")
        #expect(message.agentId == .claudeCode)
        #expect(message.sessionId == UUID(uuidString: "9E1C8518-9DA0-4E93-8313-2637D4E5769F"))
        #expect(message.state == .usingTool)
        #expect(message.detail == "Running test suite")
        #expect(message.toolName == "Bash")
        #expect(message.progress == 0.5)
        #expect(message.timestamp == Date(timeIntervalSince1970: 1_788_004_800))
    }

    @Test("accepts the URL scheme case-insensitively")
    func uppercaseScheme() throws {
        let message = try IPCURLParser().parse(url(payload: payload(), scheme: "NOTCHFLOW"))

        #expect(message.agentId == .claudeCode)
    }

    @Test("uses the first payload query item")
    func firstPayload() throws {
        let firstPayload = payload(replacing: ["detail": "First"])
        let secondPayload = payload(replacing: ["detail": "Second"])
        var components = URLComponents()
        components.scheme = "notchflow"
        components.host = "ai-status"
        components.queryItems = [
            URLQueryItem(name: "payload", value: String(decoding: firstPayload, as: UTF8.self)),
            URLQueryItem(name: "payload", value: String(decoding: secondPayload, as: UTF8.self))
        ]

        let message = try IPCURLParser().parse(try #require(components.url))

        #expect(message.detail == "First")
    }

    @Test("rejects an unsupported scheme")
    func unsupportedScheme() {
        expectParserError(.unsupportedScheme, parsing: url(payload: payload(), scheme: "https"))
    }

    @Test("rejects an unsupported endpoint")
    func unsupportedEndpoint() {
        expectParserError(.unsupportedEndpoint, parsing: url(payload: payload(), host: "other"))
    }

    @Test("rejects a missing payload")
    func missingPayload() {
        expectParserError(.missingPayload, parsing: URL(string: "notchflow://ai-status")!)
    }

    @Test("rejects a non-UTF-8 payload")
    func nonUTF8Payload() {
        expectParserError(
            .undecodablePayload,
            parsing: URL(string: "notchflow://ai-status?payload=%FF")!
        )
    }

    @Test("surfaces malformed JSON as a validation error")
    func garbagePayload() {
        expectParserError(
            .invalidMessage(.malformedPayload),
            parsing: url(payload: Data("garbage".utf8))
        )
    }

    @Test("surfaces validator failures")
    func invalidMessage() {
        expectParserError(
            .invalidMessage(.unsafeString(field: "detail")),
            parsing: url(payload: payload(replacing: ["detail": "unsafe; detail"]))
        )
    }

    @Test(
        "rejects degenerate URLs without crashing",
        arguments: ["", "notchflow://", "://", "notchflow://ai-status?payload=%ZZ"]
    )
    func degenerateURL(rawURL: String) {
        guard let input = URL(string: rawURL) else {
            return
        }

        #expect(throws: (any Error).self) {
            try IPCURLParser().parse(input)
        }
    }

    private func expectParserError(_ expectedError: IPCURLParserError, parsing url: URL) {
        do {
            _ = try IPCURLParser().parse(url)
            Issue.record("Expected \(expectedError)")
        } catch let error as IPCURLParserError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func url(
        payload: Data,
        scheme: String = "notchflow",
        host: String = "ai-status"
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "payload", value: String(decoding: payload, as: UTF8.self))
        ]
        return components.url!
    }

    private func payload(replacing replacements: [String: Any] = [:]) -> Data {
        var object: [String: Any] = [
            "schemaVersion": "1.0",
            "agentId": "claude-code",
            "sessionId": "9E1C8518-9DA0-4E93-8313-2637D4E5769F",
            "state": "usingTool",
            "detail": "Running test suite",
            "toolName": "Bash",
            "progress": 0.5,
            "timestamp": "2026-08-29T12:00:00Z"
        ]
        for (key, value) in replacements {
            object[key] = value
        }
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
