import Foundation

public enum HookSnippetGenerationError: Error, Equatable, Sendable {
    case invalidNotifierExecutablePath
}

public struct HookSnippetGenerator: Sendable {
    private let notifierExecutablePath: String

    public init(notifierExecutablePath: String) {
        self.notifierExecutablePath = notifierExecutablePath
    }

    public func claudeCodeSettingsFragment() throws -> String {
        let command =
            "\(try shellSingleQuotedNotifierPath()) --agent claude-code "
            + #"--state usingTool --session "$CLAUDE_SESSION_ID" &"#
        let fragment: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "hooks": [
                            [
                                "type": "command",
                                "command": command,
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(
            withJSONObject: fragment,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard let output = String(bytes: data, encoding: .utf8) else {
            throw HookSnippetGenerationError.invalidNotifierExecutablePath
        }
        return output + "\n"
    }

    public func codexNotifyFragment() -> String {
        let arguments = [notifierExecutablePath, "--agent", "codex"]
        return "notify = \(Self.jsonLiteral(arguments))\n"
    }

    public func openCodePluginFile() -> String {
        return """
            import type { Plugin } from "@opencode-ai/plugin"
            import { spawn } from "node:child_process"

            const notifierExecutablePath = \(Self.jsonLiteral(notifierExecutablePath))

            const notify = (state: string, sessionId: string) => {
              const child = spawn(
                notifierExecutablePath,
                ["--agent", "opencode", "--state", state, "--session", sessionId],
                { detached: true, stdio: "ignore" },
              )
              child.unref()
            }

            export const NotchFlowPlugin: Plugin = async () => ({
              event: async ({ event }) => {
                switch (event.type) {
                  case "session.created":
                    notify("thinking", event.properties.info.id)
                    break
                  case "session.idle":
                    notify("completed", event.properties.sessionID)
                    break
                  case "session.error":
                    notify("error", event.properties.sessionID)
                    break
                }
              },
              "tool.execute.before": async (input) => {
                notify("usingTool", input.sessionID)
              },
              "tool.execute.after": async (input) => {
                notify("working", input.sessionID)
              },
            })

            """
    }

    private func shellSingleQuotedNotifierPath() throws -> String {
        guard !notifierExecutablePath.isEmpty,
            notifierExecutablePath.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            })
        else {
            throw HookSnippetGenerationError.invalidNotifierExecutablePath
        }

        return "'\(notifierExecutablePath.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func jsonLiteral<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            preconditionFailure("Hook snippets only encode strings and string arrays")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
