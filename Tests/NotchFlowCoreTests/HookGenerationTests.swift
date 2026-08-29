import Foundation
import Testing
@testable import NotchFlowCore

@Suite("HookGeneration")
struct HookGenerationTests {
    private let notifierPath = #"/Applications/Notch "Flow"/bin/notchflow-notify"#

    @Test("generates a valid Claude Code settings fragment")
    func claudeCodeSettingsFragment() throws {
        let fragment = try HookSnippetGenerator(
            notifierExecutablePath: notifierPath
        ).claudeCodeSettingsFragment()
        let settings = try #require(
            JSONSerialization.jsonObject(with: Data(fragment.utf8)) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        let hookGroup = try #require(preToolUse.first)
        let commands = try #require(hookGroup["hooks"] as? [[String: String]])
        let command = try #require(commands.first)

        #expect(command["type"] == "command")
        #expect(
            command["command"]
                == #"'/Applications/Notch "Flow"/bin/notchflow-notify' --agent claude-code --state usingTool --session "$CLAUDE_SESSION_ID" &"#
        )
    }

    @Test("generates a valid Codex notify fragment")
    func codexNotifyFragment() throws {
        let generator = HookSnippetGenerator(notifierExecutablePath: notifierPath)
        let fragment = generator.codexNotifyFragment()
        let assignmentPrefix = "notify = "

        #expect(fragment.hasPrefix(assignmentPrefix))

        let encodedArguments = fragment.dropFirst(assignmentPrefix.count)
        let arguments = try #require(
            JSONSerialization.jsonObject(with: Data(encodedArguments.utf8)) as? [String]
        )

        #expect(arguments == [notifierPath, "--agent", "codex"])
        #expect(fragment.contains(#"Notch \"Flow\""#))
    }

    @Test("generates an OpenCode TypeScript plugin")
    func openCodePluginFile() throws {
        let generator = HookSnippetGenerator(notifierExecutablePath: notifierPath)
        let plugin = generator.openCodePluginFile()
        let pathDeclarationPrefix = "const notifierExecutablePath = "
        let pathDeclaration = try #require(
            plugin.split(separator: "\n").first {
                $0.hasPrefix(pathDeclarationPrefix)
            }
        )
        let encodedPath = pathDeclaration.dropFirst(pathDeclarationPrefix.count)
        let decodedPath = try JSONDecoder().decode(
            String.self,
            from: Data(encodedPath.utf8)
        )

        #expect(decodedPath == notifierPath)
        #expect(plugin.contains(#"import type { Plugin } from "@opencode-ai/plugin""#))
        #expect(plugin.contains(#""session.created""#))
        #expect(plugin.contains(#""tool.execute.before": async"#))
        #expect(plugin.contains(#""tool.execute.after": async"#))
        #expect(plugin.contains(#""session.idle""#))
        #expect(plugin.contains(#""session.error""#))
    }

    @Test("generation is idempotent")
    func idempotentGeneration() throws {
        let generator = HookSnippetGenerator(notifierExecutablePath: notifierPath)

        let firstClaudeFragment = try generator.claudeCodeSettingsFragment()
        let firstCodexFragment = generator.codexNotifyFragment()
        let firstOpenCodePlugin = generator.openCodePluginFile()

        #expect(try generator.claudeCodeSettingsFragment() == firstClaudeFragment)
        #expect(generator.codexNotifyFragment() == firstCodexFragment)
        #expect(generator.openCodePluginFile() == firstOpenCodePlugin)
    }
}
