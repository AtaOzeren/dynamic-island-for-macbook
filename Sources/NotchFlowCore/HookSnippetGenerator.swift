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
    public static let managedHookMarker = "notchflow_hook_v3"

    /// Exact markers emitted by earlier managed Claude Code hooks.
    public static let previousManagedHookMarkers = ["notchflow_hook_v2"]

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
        let hooks = Dictionary(
            uniqueKeysWithValues: Self.claudeCodeLifecycle.map { event in
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
                                        carriesToolName: event.carriesToolName,
                                        carriesSubagentIdentity: event.carriesSubagentIdentity
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
        let hooks = Dictionary(
            uniqueKeysWithValues: Self.codexLifecycleEvents.map { event in
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
        import { spawn, spawnSync } from "node:child_process"
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

        const statusURL = (body: string) =>
          `notchflow://ai-status?payload=${encodeURIComponent(body)}`

        const openURL = (body: string) => {
          const child = spawn("open", ["-g", statusURL(body)], { detached: true, stdio: "ignore" })
          child.unref()
        }

        export const NotchFlowPlugin: Plugin = async ({ client, directory }) => {
          // The task tool gives every sub-agent a real child session with its own
          // id. Reported as-is, four sub-agents read as four more agents running;
          // the island needs the session the user actually started, so parentage
          // is tracked here and the root is sent alongside each message.
          const parents = new Map<string, string>()
          const names = new Map<string, string>()
          // The top-level sessions this process has reported, so it can end them
          // on the way out.
          const liveRoots = new Set<string>()

          const remember = (info: any) => {
            if (!info?.id) return
            parents.set(info.id, info.parentID ?? "")
            if (info.parentID && typeof info.title === "string" && info.title) {
              if (!names.has(info.id)) names.set(info.id, info.title)
            }
          }

          // Only for a session that started before this plugin loaded; the
          // events above cover every session created while it is running.
          const fetchParent = async (sessionId: string): Promise<string> => {
            try {
              const response = await client.session.get({ path: { id: sessionId } })
              const info = (response as any)?.data ?? response
              return info?.parentID ?? ""
            } catch {
              return ""
            }
          }

          const rootOf = async (sessionId: string): Promise<string> => {
            let current = sessionId
            const seen = new Set<string>()
            while (!seen.has(current)) {
              seen.add(current)
              let parent = parents.get(current)
              if (parent === undefined) {
                parent = await fetchParent(current)
                parents.set(current, parent)
              }
              if (!parent) return current
              current = parent
            }
            // A parent cycle is not a shape opencode produces, but treating the
            // session as its own root keeps one bad edge from hanging the hook.
            return current
          }

          const envelope = (state: string, sessionId: string, detail: string) =>
            JSON.stringify({
              schemaVersion: "1.0",
              agentId: "opencode",
              sessionId: sessionUUID("opencode", sessionId),
              state,
              detail,
              timestamp: new Date().toISOString(),
            })

          // `session.idle` means the session stopped, not that it succeeded. A
          // turn that died on a rate limit goes idle exactly like one that
          // finished, and opencode emits no event for the failure itself
          // (anomalyco/opencode#10432), so the only way to tell them apart is to
          // ask what the last message actually says.
          //
          // Reporting the difference is the whole point: a green tick on a turn
          // that never ran is worse than no island at all.
          const OUTCOME_REASONS: Record<number, string> = {
            401: "authFailed",
            403: "authFailed",
            402: "quotaExhausted",
            429: "quotaExhausted",
            529: "providerUnavailable",
          }

          const classify = (error: any): string | null => {
            if (!error) return null
            // An aborted turn is neither a success nor a failure: the user or
            // the agent stopped it on purpose, and it is by far the most common
            // stored error. Painting those red would turn a cancel loop into a
            // wall of alarm.
            if (error.name === "MessageAbortedError") return null
            const status = Number(error.data?.statusCode)
            if (OUTCOME_REASONS[status]) return OUTCOME_REASONS[status]
            if (status >= 400 && status < 500) return "requestRejected"
            const body = String(error.data?.message ?? "")
            if (body.includes("overloaded_error")) return "providerUnavailable"
            return "unknown"
          }

          const lastAssistantError = async (sessionId: string): Promise<any> => {
            try {
              const response = await client.session.messages({ path: { id: sessionId } })
              const messages = ((response as any)?.data ?? response) as any[]
              if (!Array.isArray(messages)) return null
              for (let i = messages.length - 1; i >= 0; i--) {
                const info = messages[i]?.info ?? messages[i]
                if (info?.role !== "assistant") continue
                return info?.error ?? null
              }
            } catch {
              // The island degrades to what it knew before this lookup existed.
            }
            return null
          }

          const settle = async (sessionId: string) => {
            if (!sessionId) return
            const reason = classify(await lastAssistantError(sessionId))
            if (reason === null) {
              await notify("completed", sessionId, "Task completed")
              return
            }
            await notify("error", sessionId, "Task failed", undefined, undefined, reason)
          }

          const notify = async (
            state: string,
            sessionId: string,
            detail: string,
            toolName?: string,
            agentName?: string,
            reason?: string,
          ) => {
            if (!sessionId) return
            if (agentName) names.set(sessionId, agentName)
            const root = await rootOf(sessionId)
            const payload: Record<string, unknown> = {
              schemaVersion: "1.0",
              agentId: "opencode",
              sessionId: sessionUUID("opencode", sessionId),
              state,
              detail,
              timestamp: new Date().toISOString(),
            }
            if (directory) payload.workspace = directory
            if (root && root !== sessionId) {
              payload.rootSessionId = sessionUUID("opencode", root)
              const name = names.get(sessionId)
              if (name) payload.sessionName = name
            }
            if (state === "usingTool" && toolName) payload.toolName = toolName
            if (state === "error" && reason) payload.reason = reason
            if (root === sessionId) liveRoots.add(sessionId)
            deliver(JSON.stringify(payload))
          }

          // Quitting opencode is neither the end of a turn nor the deletion of a
          // session, so nothing else reports it: the last state sits on the
          // island until its silence timeout while the process behind it is
          // gone. Saying so on the way out is the only message that can.
          //
          // Sending the roots alone is enough — the island ends an instance's
          // sub-agents with it, and a handful of synchronous `open` calls on
          // exit is a cost the user feels.
          const MAX_FAREWELLS = 8
          let saidGoodbye = false
          const sayGoodbye = () => {
            if (saidGoodbye) return
            saidGoodbye = true
            for (const sessionId of Array.from(liveRoots).slice(0, MAX_FAREWELLS)) {
              // Synchronous on purpose: an exit handler is the last code this
              // process runs, and `fetch` would never get its turn.
              spawnSync("open", ["-g", statusURL(envelope("idle", sessionId, "Session ended"))])
            }
            liveRoots.clear()
          }

          // Only `exit`. Registering a SIGINT or SIGTERM listener would suppress
          // Node's default termination, and an agent that no longer quits on
          // Ctrl-C is a far worse defect than a card that lingers — a signal
          // that skips this handler is what the island's silence timeout is for.
          process.on("exit", sayGoodbye)

          return {
            // No "session.created" state message: opening a session is not work,
            // and a "thinking" state with no expiry would hold the island for as
            // long as the window stayed open. "chat.message" is the real start —
            // the event is watched only to learn the session's parent.
            event: async ({ event }) => {
              switch (event.type) {
                case "session.created":
                  remember(event.properties.info)
                  break
                case "session.updated":
                  remember(event.properties.info)
                  break
                case "session.idle":
                  await settle(event.properties.sessionID)
                  break
                case "session.deleted":
                  await notify("idle", event.properties.info.id, "Session ended")
                  parents.delete(event.properties.info.id)
                  names.delete(event.properties.info.id)
                  liveRoots.delete(event.properties.info.id)
                  break
                case "permission.asked":
                  await notify("waitingForUser", event.properties.sessionID, "Needs attention")
                  break
              }
            },
            "chat.message": async (input, output) => {
              await notify(
                "thinking",
                output.message.sessionID,
                "Task started",
                undefined,
                (input as any)?.agent,
              )
            },
            "tool.execute.before": async (input) => {
              await notify("usingTool", input.sessionID, "Using tool", input.tool, (input as any)?.agent)
            },
            "tool.execute.after": async (input) => {
              await notify("working", input.sessionID, "Working…", undefined, (input as any)?.agent)
            },
          }
        }

        """

    // MARK: - Lifecycle tables

    struct LifecycleEvent {
        let event: String
        let state: String
        let detail: String
        var carriesToolName = false
        var carriesSubagentIdentity = false
        var carriesFailureReason = false
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
    /// Sub-agent hooks carry their own identity below the root session, so their
    /// completion updates the child rather than reopening the root turn.
    private static let claudeCodeLifecycle: [LifecycleEvent] = [
        LifecycleEvent(event: "UserPromptSubmit", state: "thinking", detail: "Task started"),
        LifecycleEvent(
            event: "PreToolUse",
            state: "usingTool",
            detail: "Using tool",
            carriesToolName: true
        ),
        LifecycleEvent(event: "PostToolUse", state: "working", detail: "Tool completed"),
        LifecycleEvent(event: "Notification", state: "waitingForUser", detail: "Needs attention"),
        LifecycleEvent(event: "Stop", state: "completed", detail: "Task completed"),
        // `Stop` fires when Claude finishes responding; `StopFailure` when the
        // turn ends on an API error instead. Without this the island had no
        // signal at all for a rate-limited turn — the card simply sat at
        // "working" until its silence bound ran out, half an hour later, saying
        // nothing about why.
        LifecycleEvent(
            event: "StopFailure",
            state: "error",
            detail: "Task failed",
            carriesFailureReason: true
        ),
        LifecycleEvent(event: "SessionEnd", state: "idle", detail: "Session ended"),
        LifecycleEvent(
            event: "SubagentStart",
            state: "working",
            detail: "Sub-agent started",
            carriesSubagentIdentity: true
        ),
        LifecycleEvent(
            event: "SubagentStop",
            state: "completed",
            detail: "Sub-agent completed",
            carriesSubagentIdentity: true
        ),
    ]

    /// The Codex hook events NotchFlow subscribes to, in `hooks.json`.
    ///
    /// Mirrors the Claude Code set event for event where Codex offers an
    /// equivalent, so a semantic milestone — prompt, tool, turn, session end —
    /// reads the same on the island whichever agent produced it. Codex has no
    /// `Notification` event, so `PermissionRequest` alone covers "needs the
    /// user". `SessionEnd` fires when Codex closes normally, when the
    /// conversation is archived or deleted while open, or after it has been
    /// idle and unopened for thirty minutes — the last two can arrive long
    /// after `Stop`, which is exactly why the mapping is `idle`: the envelope
    /// ends the presentation outright rather than restarting a dismiss timer.
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
        LifecycleEvent(event: "SessionEnd", state: "idle", detail: "Session ended"),
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
