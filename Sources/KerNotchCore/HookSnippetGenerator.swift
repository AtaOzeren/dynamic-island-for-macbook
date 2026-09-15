import Foundation

public struct HookSnippetGenerator: Sendable {
    /// The URL scheme every generated hook opens.
    public static let urlScheme = "kernotch"

    /// The scheme generated hooks carried before the app was renamed. Still
    /// matched — never emitted — so an upgrade recognises and replaces a hook
    /// written by a pre-rename version instead of leaving it firing.
    public static let legacyURLScheme = "notchflow"

    /// The token the Codex installer matches to recognise the `notify` command
    /// it wrote itself.
    ///
    /// Declared here, beside the script that carries it, because the installer
    /// used to hold its own copy of the string: the generator changed, the
    /// installer went on looking for the old token, and it stopped recognising
    /// its own hook — reporting the configuration unreadable and refusing to
    /// upgrade. One constant, emitted and matched, cannot drift.
    public static let codexNotifyMarker = "kernotch_codex_notify_v5"

    /// The same, for the Codex lifecycle hooks file.
    public static let codexLifecycleHookMarker = "kernotch_codex_hook_v4"

    /// Exact markers earlier managed Codex lifecycle handlers carried. Recognising
    /// them is what lets an upgrade replace the old handler instead of leaving it
    /// beside the new one — where it kept firing, still carrying the launch
    /// fallback it was written with.
    ///
    /// The `notchflow_` spellings predate the rename and must stay: a machine
    /// still carrying one of those handlers gets it replaced on upgrade rather
    /// than left firing beside the new one.
    public static let previousCodexLifecycleHookMarkers = [
        "kernotch_codex_hook_v1", "kernotch_codex_hook_v2", "kernotch_codex_hook_v3",
        "notchflow_codex_hook_v1", "notchflow_codex_hook_v2", "notchflow_codex_hook_v3",
    ]

    /// Codex `notify` markers earlier versions emitted, the pre-rename spellings
    /// among them.
    public static let previousCodexNotifyMarkers = [
        "kernotch_codex_notify_v4", "notchflow_codex_notify_v4",
    ]

    /// The token every generated hook command carries, whatever the agent.
    ///
    /// It is what lets an installer recognise a command *it* wrote in an
    /// earlier version and replace it. Without that, upgrading only appended
    /// the new command and left the old one beside it: the previous, broken
    /// hook kept firing, and every event was delivered twice.
    public static let managedHookMarker = "kernotch_hook_v5"

    /// Exact markers emitted by earlier managed Claude Code hooks, including the
    /// `notchflow_` spellings written before the rename.
    public static let previousManagedHookMarkers = [
        "kernotch_hook_v2", "kernotch_hook_v3", "kernotch_hook_v4",
        "notchflow_hook_v2", "notchflow_hook_v3", "notchflow_hook_v4",
    ]

    /// Token sets an earlier version's command carried. A command counts as ours
    /// when it carries *every* token of *any one* set.
    ///
    /// Deliberately more than the URL scheme alone. A hook someone wrote by
    /// hand may well open a `kernotch://` URL; deriving the session with
    /// `uuid.uuid5` is this generator's own signature. Claiming too much would
    /// mean deleting a user's own hook on upgrade, which is worse than leaving
    /// a stale one behind.
    ///
    /// One set per scheme the app has ever emitted: matching them separately is
    /// what keeps a pre-rename hook recognisable, since no single command
    /// carries both spellings.
    public static let legacyManagedHookMarkerSets = [
        ["\(urlScheme)://ai-status", "uuid.uuid5("],
        ["\(legacyURLScheme)://ai-status", "uuid.uuid5("],
    ]

    public init() {}

    public func claudeCodeSettingsFragment() -> String {
        let hooks = Dictionary(
            uniqueKeysWithValues: Self.claudeCodeLifecycle.map { event in
                (event.event, [Self.claudeCodeHookGroup(for: event)])
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

    /// One settings group: the command, and the matcher narrowing it when the
    /// event has one. A group without a matcher runs for every occurrence.
    private static func claudeCodeHookGroup(for event: LifecycleEvent) -> [String: Any] {
        var group: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": HookScript.claudeCodeHookCommand(for: event),
                ]
            ]
        ]
        if let matcher = event.matcher {
            group["matcher"] = matcher
        }
        return group
    }

    public func codexNotifyFragment(forwarding existingArguments: [String] = []) -> String {
        let forwardedJSON = HookTextEncoding.jsonLiteral(existingArguments)
        let script =
            HookScript.pythonPreamble(agentID: "codex")
                + """
                \(Self.codexNotifyMarker) = True
                import subprocess
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
                event = kernotch_load(event_args[0])
                kernotch_send(
                    kernotch_payload(
                        kernotch_session(event.get("thread-id") or event.get("thread_id")),
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
        // Node does not await promises in exit handlers, so spawnSync is reserved
        // for the bounded loopback farewell while live events keep using fetch.
        import { spawnSync } from "node:child_process"
        import { createHash } from "node:crypto"
        import { readFileSync } from "node:fs"
        import { homedir } from "node:os"
        import { join } from "node:path"

        const PORT_FILE = join(homedir(), "Library", "Application Support", "KerNotch", "ipc-port")

        const sessionUUID = (agentId: string, sessionId: string) => {
          const bytes = createHash("sha256").update(`${agentId}:${sessionId}`).digest().subarray(0, 16)
          bytes[6] = (bytes[6] & 0x0f) | 0x50
          bytes[8] = (bytes[8] & 0x3f) | 0x80
          const hex = bytes.toString("hex")
          return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
        }

        const discoveryPort = () => {
          try {
            return readFileSync(PORT_FILE, "utf8").trim()
          } catch {
            return ""
          }
        }

        // Live events use non-blocking fetch so hook traffic never delays the
        // agent; the exit handler has a separate synchronous delivery path.
        const deliver = (body: string) => {
          const port = discoveryPort()
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
              .catch(() => clearTimeout(timeout))
            return
          }
        }

        const deliverBeforeExit = (body: string) => {
          const port = discoveryPort()
          if (!port) return
          spawnSync("/usr/bin/curl", [
            "-s",
            "--max-time", "2",
            "--request", "POST",
            "--header", "Content-Type: application/json",
            "--data-binary", body,
            `http://127.0.0.1:${port}/ai-status`,
          ], { stdio: "ignore" })
        }

        export const KerNotchPlugin: Plugin = async ({ client, directory }) => {
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
          // sub-agents with it.
          const MAX_FAREWELLS = 8
          let saidGoodbye = false
          const sayGoodbye = () => {
            if (saidGoodbye) return
            saidGoodbye = true
            for (const sessionId of Array.from(liveRoots).slice(0, MAX_FAREWELLS)) {
              deliverBeforeExit(envelope("idle", sessionId, "Session ended"))
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
                // The question tool stops the turn exactly like a permission
                // prompt does, but reports through its own event; without it a
                // question showed nothing more than a tool in flight.
                case "question.asked":
                  await notify("waitingForUser", event.properties.sessionID, "Question asked")
                  break
                // Answered, declined, or granted, the turn carries on, so the
                // island stops asking for the user before the next tool runs.
                case "permission.replied":
                case "question.replied":
                case "question.rejected":
                  await notify("working", event.properties.sessionID, "Working…")
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
        /// Narrows the hook to some occurrences of the event. Claude Code
        /// compares a matcher made only of names as an exact list.
        var matcher: String?
        var carriesToolName = false
        var carriesSubagentIdentity = false
        var carriesFailureReason = false
        /// Tools that stop the turn to ask the user something. When one of them
        /// is the tool in question, the hook reports `waitingForUser` with the
        /// tool's own detail instead of the event's state.
        var userInputTools: [UserInputTool] = []
    }

    /// A tool whose use means the agent is waiting on the user rather than
    /// working.
    struct UserInputTool {
        let toolName: String
        let detail: String
    }

    /// The notification types that mean Claude Code cannot continue without the
    /// user.
    ///
    /// Everything else Claude Code notifies about is status, not a request:
    /// `idle_prompt` fires a minute after every finished turn, `auth_success`
    /// after a login. Unfiltered, each of those turned into a yellow "needs your
    /// input" card that stayed for half an hour on an agent that needed nothing.
    static let claudeCodeNeedsInputNotificationTypes = [
        "permission_prompt",
        "elicitation_dialog",
        "elicitation_url_dialog",
        "agent_needs_input",
        "worker_permission_prompt",
    ]

    /// Claude Code's tools that ask the user rather than act.
    ///
    /// Their `PreToolUse` used to report `usingTool`, which the default event
    /// switches drop, so a question or a plan waiting for approval never showed
    /// on the island at all.
    static let claudeCodeUserInputTools = [
        UserInputTool(toolName: "AskUserQuestion", detail: "Question asked"),
        UserInputTool(toolName: "ExitPlanMode", detail: "Plan approval needed"),
    ]

    /// The Claude Code hook events KerNotch subscribes to.
    ///
    /// Only names Claude Code actually emits appear here — an event that does
    /// not exist is a hook that never fires, which reads on screen exactly like
    /// a broken island. `Stop` is the single end-of-turn event; a turn that
    /// ends on an API error arrives through `StopFailure` instead.
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
            carriesToolName: true,
            userInputTools: claudeCodeUserInputTools
        ),
        LifecycleEvent(event: "PostToolUse", state: "working", detail: "Tool completed"),
        // A tool that failed or was interrupted leaves the turn running just as
        // a finished one does, so the island returns to working instead of
        // holding whatever the tool started with — a question's yellow included.
        LifecycleEvent(event: "PostToolUseFailure", state: "working", detail: "Tool failed"),
        // Fires as the permission dialog appears, which is also how the question
        // and plan-approval tools reach the user, so it shares their details.
        LifecycleEvent(
            event: "PermissionRequest",
            state: "waitingForUser",
            detail: "Needs attention",
            userInputTools: claudeCodeUserInputTools
        ),
        LifecycleEvent(
            event: "Notification",
            state: "waitingForUser",
            detail: "Needs attention",
            matcher: claudeCodeNeedsInputNotificationTypes.joined(separator: "|")
        ),
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

    /// The Codex hook events KerNotch subscribes to, in `hooks.json`.
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
