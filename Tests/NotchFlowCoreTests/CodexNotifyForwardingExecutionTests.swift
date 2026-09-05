import Foundation
import Testing

@testable import NotchFlowCore

/// The generated Codex `notify` command must run, not merely read well.
///
/// The shared Python preamble once imported `subprocess` for the launch
/// fallback; when that fallback went, so did the import — and the Codex
/// fragment still spawns the user's previous `notify` command with it. Only
/// executing the script with a forward target catches that class of break.
@Suite("Codex notify forwarding executes")
struct CodexNotifyForwardingExecutionTests {
    @Test("a forwarded notify command runs under python3 without a NameError")
    func forwardedNotifyRuns() throws {
        let fragment = HookSnippetGenerator().codexNotifyFragment(forwarding: ["/usr/bin/true"])
        let literal = fragment.dropFirst("notify = ".count).trimmingCharacters(in: .whitespacesAndNewlines)
        let arguments = try JSONDecoder().decode([String].self, from: Data(literal.utf8))
        try #require(arguments.count == 3)

        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchflow-codex-notify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = [
            arguments[1], arguments[2],
            #"{"type":"agent-turn-complete","thread-id":"thread-1"}"#,
        ]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let standardError = Pipe()
        process.standardError = standardError
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        let diagnostics = String(
            decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(process.terminationStatus == 0, "stderr: \(diagnostics)")
        #expect(!diagnostics.contains("NameError"), "stderr: \(diagnostics)")
    }
}
