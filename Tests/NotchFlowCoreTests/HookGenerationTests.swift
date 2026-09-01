import Foundation
import Testing

@testable import NotchFlowCore

@Suite("HookGeneration")
struct HookGenerationTests {
    @Test("builds a URL that round-trips through the IPC parser")
    func statusURLRoundTrip() throws {
        let message = IPCMessage(
            schemaVersion: IPCMessageValidator.supportedSchemaVersion,
            agentId: .claudeCode,
            sessionId: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            state: .usingTool,
            detail: "Editing App.swift",
            toolName: "Edit",
            progress: 0.5,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let url = try HookSnippetGenerator.statusURL(for: message)

        #expect(url.scheme == "notchflow")
        #expect(url.host == "ai-status")
        #expect(try IPCURLParser().parse(url) == message)
    }

    @Test("generates Claude Code lifecycle hooks using stdin event fields")
    func claudeCodeSettingsFragment() throws {
        let fragment = HookSnippetGenerator().claudeCodeSettingsFragment()
        let settings = try #require(
            JSONSerialization.jsonObject(with: Data(fragment.utf8)) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        #expect(
            Set(hooks.keys) == [
                "SessionStart",
                "UserPromptSubmit",
                "PreToolUse",
                "PostToolUse",
                "Notification",
                "Stop",
                "StopFailure",
                "SessionEnd",
            ]
        )
        let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        let hookGroup = try #require(preToolUse.first)
        let commands = try #require(hookGroup["hooks"] as? [[String: String]])
        let command = try #require(commands.first)

        #expect(command["type"] == "command")
        #expect(command["command"]?.contains("EVENT=$(cat)") == true)
        #expect(command["command"]?.contains("session_id") == true)
        #expect(command["command"]?.contains("uuid.uuid5") == true)
        #expect(command["command"]?.contains(#"open -g "$URL" &"#) == true)
        #expect(command["command"]?.contains("CLAUDE_SESSION_ID") == false)

        #expect(try hookCommand(for: "Stop", in: hooks).contains(#""state":"completed""#))
        #expect(try hookCommand(for: "StopFailure", in: hooks).contains(#""state":"error""#))
        #expect(try hookCommand(for: "SessionEnd", in: hooks).contains(#""state":"idle""#))
    }

    @Test("generates a direct Codex Python notify fragment")
    func codexNotifyFragment() throws {
        let fragment = HookSnippetGenerator().codexNotifyFragment()
        let assignmentPrefix = "notify = "

        #expect(fragment.hasPrefix(assignmentPrefix))

        let encodedArguments = fragment.dropFirst(assignmentPrefix.count)
        let arguments = try #require(
            JSONSerialization.jsonObject(with: Data(encodedArguments.utf8)) as? [String]
        )

        #expect(arguments.count == 3)
        #expect(arguments[0] == "python3")
        #expect(arguments[1] == "-c")
        #expect(arguments[2].contains("sys.argv[1:]"))
        #expect(arguments[2].contains("thread-id"))
        #expect(arguments[2].contains("uuid.uuid5"))
        #expect(arguments[2].contains("subprocess.Popen"))
        #expect(arguments[2].contains("notchflow://ai-status"))
    }

    @Test("Codex notify forwards events to an existing notifier")
    func codexNotifyForwardsExistingNotifier() throws {
        let existing = ["/Applications/Notifier.app/Contents/MacOS/Notifier", "turn-ended"]
        let fragment = HookSnippetGenerator().codexNotifyFragment(forwarding: existing)
        let arguments = try #require(
            JSONSerialization.jsonObject(
                with: Data(fragment.dropFirst("notify = ".count).utf8)
            ) as? [String]
        )

        #expect(arguments[2].contains(existing[0]))
        #expect(arguments[2].contains(existing[1]))
        #expect(arguments[2].contains("subprocess.Popen(forward+event_args"))
    }

    @Test("generates Codex lifecycle hooks for visible task states")
    func codexLifecycleHooksFragment() throws {
        let fragment = HookSnippetGenerator().codexLifecycleHooksFragment()
        let document = try #require(
            JSONSerialization.jsonObject(with: Data(fragment.utf8)) as? [String: Any]
        )
        let hooks = try #require(document["hooks"] as? [String: Any])

        #expect(
            Set(hooks.keys) == [
                "UserPromptSubmit",
                "PreToolUse",
                "PostToolUse",
                "PermissionRequest",
                "Stop",
            ]
        )

        for event in hooks.keys {
            let groups = try #require(hooks[event] as? [[String: Any]])
            let group = try #require(groups.first)
            let handlers = try #require(group["hooks"] as? [[String: Any]])
            let handler = try #require(handlers.first)
            let command = try #require(handler["command"] as? String)

            #expect(handler["type"] as? String == "command")
            #expect(handler["async"] as? Bool == true)
            #expect(command.contains("notchflow_codex_hook_v1=True"))
            #expect(command.contains("hook_event_name"))
            #expect(command.contains("session_id"))
            #expect(command.contains("uuid.uuid5"))
            #expect(command.contains("notchflow://ai-status"))
        }

        let promptCommand = try hookCommand(for: "UserPromptSubmit", in: hooks)
        #expect(promptCommand.contains(#""UserPromptSubmit":("thinking","Task started")"#))
        #expect(promptCommand.contains(#""PermissionRequest":("waitingForUser","Needs attention")"#))
        #expect(promptCommand.contains(#""Stop":("completed","Task completed")"#))
    }

    @Test("generates an OpenCode plugin that invokes open directly")
    func openCodePluginFile() {
        let plugin = HookSnippetGenerator().openCodePluginFile()

        #expect(plugin.contains(#"import type { Plugin } from "@opencode-ai/plugin""#))
        #expect(plugin.contains(#"spawn("open", ["-g", url]"#))
        #expect(plugin.contains(#"agentId: "opencode""#))
        #expect(plugin.contains(#"encodeURIComponent(JSON.stringify(payload))"#))
        #expect(plugin.contains(#"createHash("sha256")"#))
        #expect(plugin.contains(#""session.created""#))
        #expect(plugin.contains(#""tool.execute.before": async"#))
        #expect(plugin.contains(#""tool.execute.after": async"#))
        #expect(plugin.contains(#""session.idle""#))
        #expect(plugin.contains(#""session.error""#))
    }

    @Test("generation is idempotent")
    func idempotentGeneration() throws {
        let generator = HookSnippetGenerator()

        let firstClaudeFragment = generator.claudeCodeSettingsFragment()
        let firstCodexFragment = generator.codexNotifyFragment()
        let firstCodexLifecycleFragment = generator.codexLifecycleHooksFragment()
        let firstOpenCodePlugin = generator.openCodePluginFile()

        #expect(generator.claudeCodeSettingsFragment() == firstClaudeFragment)
        #expect(generator.codexNotifyFragment() == firstCodexFragment)
        #expect(generator.codexLifecycleHooksFragment() == firstCodexLifecycleFragment)
        #expect(generator.openCodePluginFile() == firstOpenCodePlugin)
    }

    private func hookCommand(
        for event: String,
        in hooks: [String: Any]
    ) throws -> String {
        let groups = try #require(hooks[event] as? [[String: Any]])
        let group = try #require(groups.first)
        let commands = try #require(group["hooks"] as? [[String: Any]])
        return try #require(commands.first?["command"] as? String)
    }
}
