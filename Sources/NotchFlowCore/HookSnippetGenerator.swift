import Foundation

public struct HookSnippetGenerator: Sendable {
    /// The token the Codex installer matches to recognise the `notify` command
    /// it wrote itself.
    ///
    /// Declared here, beside the script that carries it, because the installer
    /// used to hold its own copy of the string: the generator changed, the
    /// installer went on looking for the old token, and it stopped recognising
    /// its own hook — reporting the configuration unreadable and refusing to
    /// upgrade. One constant, emitted and matched, cannot drift.
    public static let codexNotifyMarker = "notchflow_codex_notify_v3"

    /// The same, for the Codex lifecycle hooks file.
    public static let codexLifecycleHookMarker = "notchflow_codex_hook_v2"

    /// The token every generated hook command carries, whatever the agent.
    ///
    /// It is what lets an installer recognise a command *it* wrote in an
    /// earlier version and replace it. Without that, upgrading only appended
    /// the new command and left the old one beside it: the previous, broken
    /// hook kept firing, and every event was delivered twice.
    public static let managedHookMarker = "notchflow_hook_v2"

    /// Every token an earlier version's command carried, all of which must be
    /// present for it to count as ours.
    ///
    /// Deliberately more than the URL scheme alone. A hook someone wrote by
    /// hand may well open a `notchflow://` URL; deriving the session with
    /// `uuid.uuid5` is this generator's own signature. Claiming too much would
    /// mean deleting a user's own hook on upgrade, which is worse than leaving
    /// a stale one behind.
    public static let legacyManagedHookMarkers = [
        "notchflow://ai-status",
        "uuid.uuid5(",
    ]

    public init() {}

    public static func statusURL(for message: IPCMessage) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(message)

        var components = URLComponents()
        components.scheme = "notchflow"
        components.host = "ai-status"
        components.queryItems = [
            URLQueryItem(name: "payload", value: String(decoding: payload, as: UTF8.self))
        ]
        guard let url = components.url else {
            preconditionFailure("The fixed NotchFlow URL components must form a URL")
        }
        return url
    }

    public func claudeCodeSettingsFragment() -> String {
        let hooks = Dictionary(uniqueKeysWithValues: Self.claudeCodeLifecycle.map { event in
            (
                event.event,
                [
                    [
                        "hooks": [
                            [
                                "type": "command",
                                "command": HookScript.claudeCodeHookCommand(
                                    state: event.state,
                                    detail: event.detail,
                                    carriesToolName: event.carriesToolName
                                ),
                            ]
                        ]
                    ]
                ]
            )
        })
        let fragment: [String: Any] = [
            "hooks": hooks
        ]

        guard
            let data = try? JSONSerialization.data(
                withJSONObject: fragment,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        else {
            preconditionFailure("The fixed Claude Code hook fragment must encode as JSON")
        }
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    public func codexNotifyFragment(forwarding existingArguments: [String] = []) -> String {
        let forwardedJSON = HookTextEncoding.jsonLiteral(existingArguments)
        let script =
            HookScript.pythonPreamble(agentID: "codex")
            + """
            \(Self.codexNotifyMarker) = True
            forward = json.loads(\(HookTextEncoding.pythonStringLiteral(forwardedJSON)))
            event_args = sys.argv[1:]
            forward and subprocess.Popen(
                forward + event_args,
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if not event_args:
                sys.exit(0)
            event = notchflow_load(event_args[0])
            notchflow_send(
                notchflow_payload(
                    notchflow_session(event.get("thread-id") or event.get("thread_id")),
                    "completed",
                    "Turn completed",
                )
            )
            """
        return "notify = \(HookTextEncoding.jsonLiteral(["/usr/bin/python3", "-c", script]))\n"
    }

    public func codexLifecycleHooksFragment() -> String {
        let handler: [String: Any] = [
            "type": "command",
            "command": HookScript.codexLifecycleHookCommand(),
            "async": true,
            "timeout": 5,
        ]
        let hooks = Dictionary(uniqueKeysWithValues: Self.codexLifecycleEvents.map { event in
            (event.event, [["hooks": [handler]]])
        })
        let document: [String: Any] = ["hooks": hooks]

        guard
            let data = try? JSONSerialization.data(
                withJSONObject: document,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        else {
            preconditionFailure("The fixed Codex lifecycle hooks must encode as JSON")
        }
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    public func openCodePluginFile() -> String {
        Self.openCodePluginSource
    }

    /// Stored rather than returned inline, so an embedded TypeScript module is
    /// a constant rather than a hundred-line function body.
    private static let openCodePluginSource = """
        import type { Plugin } from "@opencode-ai/plugin"
        import { spawn } from "node:child_process"
        import { createHash } from "node:crypto"
        import { readFileSync } from "node:fs"
        import { homedir } from "node:os"
        import { join } from "node:path"

        const PORT_FILE = join(homedir(), "Library", "Application Support", "NotchFlow", "ipc-port")

        const sessionUUID = (agentId: string, sessionId: string) => {
          const bytes = createHash("sha256").update(`${agentId}:${sessionId}`).digest().subarray(0, 16)
          bytes[6] = (bytes[6] & 0x0f) | 0x50
          bytes[8] = (bytes[8] & 0x3f) | 0x80
          const hex = bytes.toString("hex")
          return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
        }

        // Falls back to the URL scheme when the island is not listening: `open`
        // launches NotchFlow, the loopback socket only reaches it once running.
        const deliver = (body: string) => {
          let port = ""
          try {
            port = readFileSync(PORT_FILE, "utf8").trim()
          } catch {
            port = ""
          }
          if (port) {
            const controller = new AbortController()
            const timeout = setTimeout(() => controller.abort(), 2000)
            fetch(`http://127.0.0.1:${port}/ai-status`, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body,
              signal: controller.signal,
            })
              .then(() => clearTimeout(timeout))
              .catch(() => {
                clearTimeout(timeout)
                openURL(body)
              })
            return
          }
          openURL(body)
        }

        const openURL = (body: string) => {
          const url = `notchflow://ai-status?payload=${encodeURIComponent(body)}`
          const child = spawn("open", ["-g", url], { detached: true, stdio: "ignore" })
          child.unref()
        }

        const notify = (state: string, sessionId: string, detail: string, toolName?: string) => {
          if (!sessionId) return
          const payload: Record<string, unknown> = {
            schemaVersion: "1.0",
            agentId: "opencode",
            sessionId: sessionUUID("opencode", sessionId),
            state,
            detail,
            timestamp: new Date().toISOString(),
          }
          if (state === "usingTool" && toolName) payload.toolName = toolName
          deliver(JSON.stringify(payload))
        }

        export const NotchFlowPlugin: Plugin = async () => ({
          // No "session.created": opening a session is not work, and a
          // "thinking" state with no expiry would hold the island for as long
          // as the window stayed open. "chat.message" is the real start.
          event: async ({ event }) => {
            switch (event.type) {
              case "session.idle":
                notify("completed", event.properties.sessionID, "Task completed")
                break
              case "session.error":
                notify("error", event.properties.sessionID, "Session error")
                break
              case "session.deleted":
                notify("idle", event.properties.info.id, "Session ended")
                break
              case "permission.asked":
                notify("waitingForUser", event.properties.sessionID, "Needs attention")
                break
            }
          },
          "chat.message": async (_input, output) => {
            notify("thinking", output.message.sessionID, "Task started")
          },
          "tool.execute.before": async (input) => {
            notify("usingTool", input.sessionID, "Using tool", input.tool)
          },
          "tool.execute.after": async (input) => {
            notify("working", input.sessionID, "Working…")
          },
        })

        """

    // MARK: - Lifecycle tables

    struct LifecycleEvent {
        let event: String
        let state: String
        let detail: String
        var carriesToolName = false
    }

    /// The Claude Code hook events NotchFlow subscribes to.
    ///
    /// Only names Claude Code actually emits appear here — an event that does
    /// not exist is a hook that never fires, which reads on screen exactly like
    /// a broken island. `Stop` is the single end-of-turn event; failures arrive
    /// through `Notification`, not through a separate failure hook.
    /// Deliberately no `SessionStart`.
    ///
    /// Opening a session is not work. Registering one on `SessionStart` put the
    /// agent on screen as "Thinking…" the moment a window opened and left it
    /// there — `thinking` has no expiry — so an idle terminal claimed the island
    /// indefinitely. The first event that means anything is the user submitting
    /// a prompt, and `Stop` clears the card five seconds after the turn ends, so
    /// the island is empty between turns without a session event to bracket it.
    private static let claudeCodeLifecycle: [LifecycleEvent] = [
        LifecycleEvent(event: "UserPromptSubmit", state: "thinking", detail: "Task started"),
        LifecycleEvent(
            event: "PreToolUse",
            state: "usingTool",
            detail: "Using tool",
            carriesToolName: true
        ),
        LifecycleEvent(event: "PostToolUse", state: "working", detail: "Tool completed"),
        LifecycleEvent(event: "SubagentStop", state: "working", detail: "Subagent finished"),
        LifecycleEvent(event: "Notification", state: "waitingForUser", detail: "Needs attention"),
        LifecycleEvent(event: "Stop", state: "completed", detail: "Task completed"),
        LifecycleEvent(event: "SessionEnd", state: "idle", detail: "Session ended"),
    ]

    static let codexLifecycleEvents: [LifecycleEvent] = [
        LifecycleEvent(event: "UserPromptSubmit", state: "thinking", detail: "Task started"),
        LifecycleEvent(
            event: "PreToolUse",
            state: "usingTool",
            detail: "Using tool",
            carriesToolName: true
        ),
        LifecycleEvent(event: "PostToolUse", state: "working", detail: "Working…"),
        LifecycleEvent(
            event: "PermissionRequest",
            state: "waitingForUser",
            detail: "Needs attention"
        ),
        LifecycleEvent(event: "Stop", state: "completed", detail: "Task completed"),
    ]

    /// A Python string literal for `value`, produced by the JSON encoder because
    /// JSON string syntax is a subset of Python's.
}

/// Escaping shared by the generator and the scripts it embeds.
enum HookTextEncoding {
    /// Wraps `value` as a single-quoted shell word.
    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static func pythonStringLiteral(_ value: String) -> String {
        jsonLiteral(value)
    }

    static func jsonLiteral<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            preconditionFailure("Hook snippets only encode strings and string arrays")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
