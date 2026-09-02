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

    @Test("Codex PreToolUse carries Claude Code tool metadata through loopback")
    func codexPreToolUseToolNameMatchesClaudeCode() async throws {
        let fixture = Self.makeFixture()
        defer { fixture.removeDirectory() }
        let port = try #require(
            await fixture.listener.updatePreferences(
                .init(
                    enabledAgentIDs: [.claudeCode, .codex],
                    enabledEventClasses: [.toolActivity]
                )
            )
        )

        for agentID in [IPCAgentID.claudeCode, .codex] {
            let response = try await Self.post(
                Request(
                    body: try Self.preToolUsePayload(for: agentID),
                    path: "/ai-status",
                    port: port
                )
            )
            #expect(response.statusCode == 204)
        }

        let activities = fixture.recorder.messages.map(AIAgentActivity.init(message:))
        #expect(activities.map(\.agent) == [.claudeCode, .codex])
        #expect(activities.map(\.state) == [.usingTool, .usingTool])
        #expect(activities.map(\.toolName) == ["Bash", "Bash"])

        await fixture.listener.stop()
    }

    @Test("Claude Code subagent lifecycle projects a named child session")
    func claudeCodeSubagentLifecycleProjectsChild() async throws {
        let fixture = Self.makeFixture()
        defer { fixture.removeDirectory() }
        let port = try #require(
            await fixture.listener.updatePreferences(.init(enabledAgentIDs: [.claudeCode]))
        )
        let rootSessionID = UUID(uuidString: "2EB063BD-B9AC-5E7A-AAAE-E7C220A61388")!
        let childSessionID = UUID(uuidString: "90E7A3AD-2EB1-58C6-A687-ED845E8A8CFB")!

        for state in [AIAgentState.working, .completed] {
            let response = try await Self.post(
                Request(
                    body: try JSONSerialization.data(
                        withJSONObject: [
                            "schemaVersion": IPCMessageValidator.supportedSchemaVersion,
                            "agentId": IPCAgentID.claudeCode.rawValue,
                            "sessionId": childSessionID.uuidString,
                            "rootSessionId": rootSessionID.uuidString,
                            "sessionName": "Explore",
                            "state": state.rawValue,
                            "detail": state == .working ? "Sub-agent started" : "Sub-agent completed",
                            "timestamp": ISO8601DateFormatter().string(from: Date()),
                        ]
                    ),
                    path: "/ai-status",
                    port: port
                )
            )
            #expect(response.statusCode == 204)
        }

        let activities = fixture.recorder.messages.map(AIAgentActivity.init(message:))
        #expect(activities.count == 2)
        #expect(activities.allSatisfy { $0.sessionID == childSessionID })
        #expect(activities.allSatisfy { $0.rootSessionID == rootSessionID })
        #expect(activities.allSatisfy { $0.sessionName == "Explore" })
        #expect(activities.map(\.state) == [.working, .completed])

        await fixture.listener.stop()
    }

    @Test("workspace metadata projects end-to-end and handles optional absence")
    func workspaceMetadataProjectsEndToEnd() async throws {
        let fixture = Self.makeFixture()
        defer { fixture.removeDirectory() }
        let port = try #require(
            await fixture.listener.updatePreferences(.init(enabledAgentIDs: [.claudeCode]))
        )

        let sessionID = UUID()
        let workspacePath = "/Users/test/projects/notchflow"

        let responseWithWorkspace = try await Self.post(
            Request(
                body: try JSONSerialization.data(
                    withJSONObject: [
                        "schemaVersion": IPCMessageValidator.supportedSchemaVersion,
                        "agentId": IPCAgentID.claudeCode.rawValue,
                        "sessionId": sessionID.uuidString,
                        "workspace": workspacePath,
                        "state": AIAgentState.working.rawValue,
                        "detail": "Working on feature",
                        "timestamp": ISO8601DateFormatter().string(from: Date()),
                    ]
                ),
                path: "/ai-status",
                port: port
            )
        )
        #expect(responseWithWorkspace.statusCode == 204)

        let responseWithoutWorkspace = try await Self.post(
            Request(
                body: try JSONSerialization.data(
                    withJSONObject: [
                        "schemaVersion": IPCMessageValidator.supportedSchemaVersion,
                        "agentId": IPCAgentID.claudeCode.rawValue,
                        "sessionId": UUID().uuidString,
                        "state": AIAgentState.working.rawValue,
                        "detail": "Working on another task",
                        "timestamp": ISO8601DateFormatter().string(from: Date()),
                    ]
                ),
                path: "/ai-status",
                port: port
            )
        )
        #expect(responseWithoutWorkspace.statusCode == 204)

        let activities = fixture.recorder.messages.map(AIAgentActivity.init(message:))
        #expect(activities.count == 2)
        #expect(activities[0].workspace == workspacePath)
        #expect(activities[1].workspace == nil)

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

    @Test("publishes the discovery file readable only by its owner")
    func discoveryFileIsOwnerOnly() async throws {
        let fixture = Self.makeFixture()
        defer { fixture.removeDirectory() }

        _ = try #require(
            await fixture.listener.updatePreferences(.init(enabledAgentIDs: [.claudeCode]))
        )

        let filePermissions = try #require(
            FileManager.default.attributesOfItem(atPath: fixture.discoveryFile.path)[
                .posixPermissions] as? NSNumber
        )
        let directoryPermissions = try #require(
            FileManager.default.attributesOfItem(atPath: fixture.directory.path)[
                .posixPermissions] as? NSNumber
        )

        #expect(filePermissions.intValue & 0o077 == 0)
        #expect(directoryPermissions.intValue & 0o077 == 0)

        await fixture.listener.stop()
    }

    @Test("binds loopback only, so a non-loopback interface cannot reach it")
    func bindsLoopbackOnly() async throws {
        let fixture = Self.makeFixture()
        defer { fixture.removeDirectory() }

        let port = try #require(
            await fixture.listener.updatePreferences(.init(enabledAgentIDs: [.claudeCode]))
        )

        for address in Self.nonLoopbackIPv4Addresses() {
            do {
                _ = try await Self.post(
                    Request(body: Self.payload(), path: "/ai-status", port: port, host: address)
                )
                Issue.record("Listener answered on non-loopback address \(address)")
            } catch {
                #expect(error is URLError)
            }
        }
        #expect(fixture.recorder.messages.isEmpty)

        await fixture.listener.stop()
    }

    @Test("rejects a payload above the validator's cap without calling the sink")
    func rejectsOversizedPayload() async throws {
        let fixture = Self.makeFixture()
        defer { fixture.removeDirectory() }

        let port = try #require(
            await fixture.listener.updatePreferences(.init(enabledAgentIDs: [.claudeCode]))
        )

        let oversized = Data(
            repeating: UInt8(ascii: "a"),
            count: IPCMessageValidator.maximumPayloadByteCount + 1
        )
        let response = try await Self.post(
            Request(body: oversized, path: "/ai-status", port: port)
        )

        #expect(response.statusCode == 413)
        #expect(fixture.recorder.messages.isEmpty)

        await fixture.listener.stop()
    }

    @Test("drops a message for an agent the preferences do not enable")
    func gatesOnPreferences() async throws {
        let fixture = Self.makeFixture()
        defer { fixture.removeDirectory() }

        // The socket exists because `codex` is on; the payload names
        // `claude-code`, so only the preference gate can stop it.
        let port = try #require(
            await fixture.listener.updatePreferences(.init(enabledAgentIDs: [.codex]))
        )

        let response = try await Self.post(
            Request(body: Self.payload(), path: "/ai-status", port: port)
        )

        #expect(response.statusCode == 204)
        #expect(fixture.recorder.messages.isEmpty)

        await fixture.listener.stop()
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
        var host: String = "127.0.0.1"
    }

    /// Every IPv4 address this machine answers on that is not `127.0.0.0/8`.
    ///
    /// Read from the live interface list rather than hard-coded, because the
    /// binding claim under test is "only loopback" — an address the test invents
    /// would prove nothing if this host does not own it.
    private static func nonLoopbackIPv4Addresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var addresses: [String] = []
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let rawAddress = interface.pointee.ifa_addr,
                rawAddress.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard
                getnameinfo(
                    rawAddress,
                    socklen_t(rawAddress.pointee.sa_len),
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0
            else { continue }

            let addressBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let address = String(decoding: addressBytes, as: UTF8.self)
            if !address.hasPrefix("127.") {
                addresses.append(address)
            }
        }
        return addresses
    }

    private static func post(_ requestParameters: Request) async throws -> HTTPURLResponse {
        let url = try #require(
            URL(
                string:
                    "http://\(requestParameters.host):\(requestParameters.port)\(requestParameters.path)"
            )
        )
        var request = URLRequest(url: url, timeoutInterval: 1)
        request.httpMethod = "POST"
        request.httpBody = requestParameters.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        return try #require(response as? HTTPURLResponse)
    }

    private static func preToolUsePayload(for agentID: IPCAgentID) throws -> Data {
        let object: [String: Any] = [
            "schemaVersion": "1.0",
            "agentId": agentID.rawValue,
            "sessionId": agentID == .claudeCode
                ? "9E1C8518-9DA0-4E93-8313-2637D4E5769F"
                : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "state": "usingTool",
            "detail": "Using tool",
            "toolName": "Bash",
            "timestamp": "2026-09-02T00:00:00Z",
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
