import Foundation
import NotchFlowCore
import Testing

@testable import NotchFlowProviders

@Suite("Loopback HTTP listener", .serialized)
@MainActor
struct LoopbackHTTPListenerTests {
    private final class MessageRecorder {
        var messages: [IPCMessage] = []
    }

    @Test("delivers a validated envelope from a real loopback request")
    func deliversValidMessage() async throws {
        let fixture = Self.makeFixture()
        defer { fixture.removeDirectory() }

        #expect(try await fixture.listener.updatePreferences(.default) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.discoveryFile.path))

        let port = try #require(
            await fixture.listener.updatePreferences(.init(enabledAgentIDs: [.claudeCode]))
        )
        let publishedPort = try String(contentsOf: fixture.discoveryFile, encoding: .utf8)
        #expect(publishedPort.trimmingCharacters(in: .whitespacesAndNewlines) == String(port))

        let response = try await Self.post(
            Request(body: Self.payload(), path: "/ai-status", port: port)
        )

        #expect(response.statusCode == 204)
        #expect(fixture.recorder.messages.count == 1)
        #expect(fixture.recorder.messages.first?.agentId == .claudeCode)

        await fixture.listener.stop()
    }

    @Test("rejects garbage and the wrong route without calling the sink")
    func rejectsInvalidRequests() async throws {
        let fixture = Self.makeFixture()
        defer { fixture.removeDirectory() }
        let port = try #require(
            await fixture.listener.updatePreferences(.init(enabledAgentIDs: [.claudeCode]))
        )

        let garbageResponse = try await Self.post(
            Request(body: Data("not-json".utf8), path: "/ai-status", port: port)
        )
        let wrongRouteResponse = try await Self.post(
            Request(body: Self.payload(), path: "/other", port: port)
        )

        #expect(garbageResponse.statusCode == 400)
        #expect(wrongRouteResponse.statusCode == 404)
        #expect(fixture.recorder.messages.isEmpty)

        #expect(try await fixture.listener.updatePreferences(.default) == nil)
    }

    @Test("removes discovery and refuses connections after stop")
    func stopsListening() async throws {
        let fixture = Self.makeFixture()
        defer { fixture.removeDirectory() }
        let port = try #require(
            await fixture.listener.updatePreferences(.init(enabledAgentIDs: [.claudeCode]))
        )

        await fixture.listener.stop()

        #expect(!FileManager.default.fileExists(atPath: fixture.discoveryFile.path))
        do {
            _ = try await Self.post(
                Request(body: Self.payload(), path: "/ai-status", port: port)
            )
            Issue.record("Expected the stopped listener to refuse the connection")
        } catch {
            #expect(error is URLError)
        }
    }

    private struct Fixture {
        let listener: LoopbackHTTPListener
        let recorder: MessageRecorder
        let discoveryFile: URL
        let directory: URL

        func removeDirectory() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func makeFixture() -> Fixture {
        let recorder = MessageRecorder()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let discoveryFile = directory.appendingPathComponent("ipc-port")
        let configuration = LoopbackHTTPListenerConfiguration(
            discoveryFileURL: discoveryFile
        )
        let listener = LoopbackHTTPListener(configuration: configuration) { message in
            recorder.messages.append(message)
        }
        return Fixture(
            listener: listener,
            recorder: recorder,
            discoveryFile: discoveryFile,
            directory: directory
        )
    }

    private struct Request {
        let body: Data
        let path: String
        let port: UInt16
    }

    private static func post(_ requestParameters: Request) async throws -> HTTPURLResponse {
        let url = try #require(
            URL(string: "http://127.0.0.1:\(requestParameters.port)\(requestParameters.path)")
        )
        var request = URLRequest(url: url, timeoutInterval: 1)
        request.httpMethod = "POST"
        request.httpBody = requestParameters.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        return try #require(response as? HTTPURLResponse)
    }

    private static func payload() -> Data {
        let object: [String: Any] = [
            "schemaVersion": "1.0",
            "agentId": "claude-code",
            "sessionId": "9E1C8518-9DA0-4E93-8313-2637D4E5769F",
            "state": "working",
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
