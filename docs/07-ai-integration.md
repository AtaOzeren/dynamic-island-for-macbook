# AI Integration

This document specifies the AI agent state machine, the IPC protocol that carries agent state into NotchFlow, the per-agent hook integrations for Claude Code, Codex CLI, and OpenCode, and the hook installer's consent model. `HookSnippetGenerator` is the source of truth for emitted configuration; Settings shows its current output when manual setup is required.

## Design principle

NotchFlow is a status and control surface for AI coding agents, not an AI product itself. It runs no model, holds no API key, and never reads the screen to infer what an agent is doing. Every piece of AI status shown in the notch arrives as an explicit, agent-initiated message over the IPC protocol below. If an agent does not send a message, NotchFlow shows nothing for it — there is no polling, no heuristic inference, and no fallback that guesses state from window titles or process activity.

## The agent state machine

`AIActivity` (a `NotchFlowCore` activity, see `05-activity-model.md`) is driven by a state machine with seven states.

| State | Meaning | Compact render | Expanded render |
|---|---|---|---|
| `idle` | Agent registered but has no active task | Not shown (activity ends) | — |
| `thinking` | Agent is reasoning, no tool call in flight | 🤖 Claude · Thinking… | Agent name, spinner, elapsed time |
| `working` | Agent is executing a multi-step task | 🤖 Claude · Working… | Agent name, current step detail, elapsed time |
| `usingTool` | Agent is running a specific tool (shell, file edit, search) | 🤖 Claude · Running terminal… | Agent name, tool name, live detail line |
| `waitingForUser` | Agent needs input before it can continue | ⚠ Claude · Needs your input | Agent name, prompt detail, a text field and Send button |
| `completed` | Agent finished its task successfully | ✓ Claude · Task completed | Agent name, summary detail, auto-dismisses |
| `error` | Agent stopped on an error it cannot resolve alone | ✗ Claude · Task error | Agent name, error detail |

### Legal transitions

```
        ┌────────────────────────────────────────────┐
        ▼                                              │
      idle ──► thinking ──► working ──► usingTool ──────┘
                  │             │           │
                  │             └──► waitingForUser ◄────┘
                  │                       │
                  └───────────────────────┘
                          (user responds)

  thinking, working, usingTool, waitingForUser ──► completed ──┐
  thinking, working, usingTool, waitingForUser ──► error ──────┤
                                                               │
                                    ┌──────────────────────────┘
                                    ▼
                             idle  or  thinking
```

- `idle` only ever transitions to `thinking`, on a task-started event.
- `thinking`, `working`, and `usingTool` can transition among each other freely as the agent alternates between reasoning and tool execution; this is the normal work loop.
- Any of `thinking`, `working`, or `usingTool` can transition to `waitingForUser`, `completed`, or `error` — an agent can need input, finish, or fail from any point in its work loop.
- `waitingForUser` transitions back to `thinking` once the user responds (a new message resets the loop) or to `error`/`completed` if the agent gives up or wraps up without further input.
- `completed` and `error` are terminal for the current task: the activity auto-dismisses (`completed`) or waits for dismissal (`error`). From either terminal state the machine accepts a transition to `idle` (explicit teardown) or directly to `thinking` (a new task starting immediately without an explicit idle step).
- No other transition is legal. A message that requests an illegal transition (for example `idle` → `usingTool` with no preceding `thinking`) is **rejected** — the state machine returns a `.rejected` outcome and the state does not change. NotchFlow does not crash or drop the connection, but the illegal state is never applied.

## The IPC protocol

The IPC protocol is a versioned contract between an agent (or its hook script) and NotchFlow. Every message is a single JSON object called the **envelope**.

### Message envelope

| Field | Type | Required | Meaning |
|---|---|---|---|
| `schemaVersion` | string | yes | The envelope schema version this message conforms to (e.g. `"1.0"`). NotchFlow rejects messages whose major version it does not understand. |
| `agentId` | string enum: `"claude-code"` \| `"codex"` \| `"opencode"` | yes | Which agent sent the message. Unknown values are handled per the security rules below. |
| `sessionId` | string (UUID) | yes | Identifies one running instance of an agent (see `Session` in `14-glossary-and-conventions.md`). Distinguishes multiple concurrent agent sessions so each gets its own `AIActivity`. |
| `state` | string enum: `"idle"` \| `"thinking"` \| `"working"` \| `"usingTool"` \| `"waitingForUser"` \| `"completed"` \| `"error"` | yes | The state described above. |
| `detail` | string | yes | A short, human-readable description shown in the expanded view (e.g. `"Editing src/App.swift"`, `"Running test suite"`). Never prompt content, code, or a transcript excerpt — see Privacy below. |
| `toolName` | string | no | The name of the tool in flight, only meaningful when `state` is `"usingTool"` (e.g. `"Bash"`, `"Edit"`). |
| `progress` | number, 0.0–1.0 | no | Fractional completion, when the agent can report one; omitted when indeterminate. |
| `timestamp` | string (ISO 8601) | yes | When the agent produced this message, used to detect and discard stale or out-of-order delivery. |

### JSON schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "NotchFlow AI Status Envelope",
  "type": "object",
  "required": ["schemaVersion", "agentId", "sessionId", "state", "detail", "timestamp"],
  "properties": {
    "schemaVersion": { "type": "string", "const": "1.0" },
    "agentId": { "type": "string", "enum": ["claude-code", "codex", "opencode"] },
    "sessionId": { "type": "string", "format": "uuid" },
    "state": {
      "type": "string",
      "enum": ["idle", "thinking", "working", "usingTool", "waitingForUser", "completed", "error"]
    },
    "detail": { "type": "string", "maxLength": 280 },
    "toolName": { "type": "string" },
    "progress": { "type": "number", "minimum": 0.0, "maximum": 1.0 },
    "timestamp": { "type": "string", "format": "date-time" }
  },
  "additionalProperties": false
}
```

### Transports

NotchFlow accepts the envelope over two transports. Both carry the identical JSON payload; the transport is purely a delivery mechanism.

| Transport | How it's invoked | Entitlement | Availability |
|---|---|---|---|
| Custom URL scheme | `open -g "notchflow://ai-status?payload=<url-encoded-json>"` | None | Works in both the App Store and Direct builds |
| Loopback HTTP listener | `POST` to `http://127.0.0.1:<port>/ai-status` with the envelope as the request body | `com.apple.security.network.server` (sandboxed build only) | Works in both builds; the App Store build must declare the entitlement, the Direct build needs no entitlement |

The **URL scheme is preferred** for hook scripts: it needs no entitlement, works identically in every build configuration, and is invoked with `open -g` so it never steals focus from the terminal or editor the agent is running in. The **HTTP listener is the fallback**, used when a caller wants a lower-latency, higher-throughput channel (for example, an editor plugin sending frequent `usingTool` progress updates) or when the calling environment cannot shell out to `open`.

Multiple sessions remain separate activities in the manager, but presentation groups sessions by `agentId`: one compact icon per agent and one minimalist expanded summary row. A count disclosure lists concurrent sessions. The summary uses the most important state in the group (`error`, then needs-input, then active work, then completed). Its navigation action traces a live CLI process to its parent app when possible, then uses deterministic running-app fallbacks; it never chooses randomly between multiple hosts.

NotchFlow binds the HTTP listener to an OS-assigned ephemeral port at launch and writes the chosen port to a discoverable location (`~/Library/Application Support/NotchFlow/ipc-port`) so a caller that prefers HTTP can read the current port without guessing or scanning.

### Security

- The HTTP listener binds to `127.0.0.1` only — never `0.0.0.0` or any externally reachable interface. It is unreachable from outside the local machine under any network configuration.
- Every incoming payload, on either transport, is validated against the JSON schema above before it reaches `ActivityManager`. A payload that fails validation is dropped and logged; it never partially updates state.
- The listener rate-limits per `sessionId` to prevent a misbehaving script from flooding the notch with updates.
- Oversized payloads are rejected outright (the `detail` field's `maxLength` in the schema is the primary bound; the HTTP listener additionally caps total request body size).
- A message whose `agentId` is not one NotchFlow recognizes, or one the user has not explicitly enabled in AI Integrations settings, is ignored — it does not create an activity, and it is not surfaced to the user as an error, since an unrecognized agent is expected to be either a future integration or an unrelated local process probing the port.

## Per-agent integration

Three agents are supported in V1: Claude Code, Codex CLI, and OpenCode. Each integrates through its own existing extension point — NotchFlow adds no agent-side software beyond a small emitted snippet.

### Claude Code

Claude Code supports hook configuration in `~/.claude/settings.json`. NotchFlow maps its lifecycle hooks onto agent state so a tool call cannot leave a permanently active card after the turn ends.

| Claude Code hook event | NotchFlow state sent |
|---|---|
| `SessionStart` | `thinking` |
| `UserPromptSubmit` | `working` |
| `PreToolUse` | `usingTool` (detail "Using tool"; the session id is derived from the event JSON's `session_id` field) |
| `PostToolUse` | `working` |
| `Notification` | `waitingForUser` |
| `Stop` | `completed` |
| `StopFailure` | `error` |
| `SessionEnd` | `idle` (ends presentation immediately) |

Claude Code hooks receive the event as JSON on stdin. The generated hook command is **asynchronous** — it fires the IPC call and returns immediately — so NotchFlow's presence never adds latency to the agent's own execution. The snippet uses the URL-scheme transport with `open -g` precisely because it backgrounds trivially from a shell hook.

<!-- notchflow-snippet: claude-code -->
```json
{
  "hooks" : {
    "Notification" : [
      {
        "hooks" : [
          {
            "command" : "EVENT=$(cat); URL=$(python3 -c 'import json,sys,urllib.parse,uuid; event=json.loads(sys.argv[1]); raw_session=event[\"session_id\"]; session=str(uuid.uuid5(uuid.NAMESPACE_URL,\"claude-code:\"+raw_session)); payload={\"schemaVersion\":\"1.0\",\"agentId\":\"claude-code\",\"sessionId\":session,\"state\":\"waitingForUser\",\"detail\":\"Needs attention\",\"timestamp\":__import__(\"datetime\").datetime.now(__import__(\"datetime\").timezone.utc).isoformat(timespec=\"milliseconds\").replace(\"+00:00\",\"Z\")}; print(\"notchflow://ai-status?payload=\"+urllib.parse.quote(json.dumps(payload,separators=(\",\",\":\")),safe=\"\"))' $EVENT); [ -n \"$URL\" ] && open -g \"$URL\" &",
            "type" : "command"
          }
        ]
      }
    ],
    "PostToolUse" : [
      {
        "hooks" : [
          {
            "command" : "EVENT=$(cat); URL=$(python3 -c 'import json,sys,urllib.parse,uuid; event=json.loads(sys.argv[1]); raw_session=event[\"session_id\"]; session=str(uuid.uuid5(uuid.NAMESPACE_URL,\"claude-code:\"+raw_session)); payload={\"schemaVersion\":\"1.0\",\"agentId\":\"claude-code\",\"sessionId\":session,\"state\":\"working\",\"detail\":\"Tool completed\",\"timestamp\":__import__(\"datetime\").datetime.now(__import__(\"datetime\").timezone.utc).isoformat(timespec=\"milliseconds\").replace(\"+00:00\",\"Z\")}; print(\"notchflow://ai-status?payload=\"+urllib.parse.quote(json.dumps(payload,separators=(\",\",\":\")),safe=\"\"))' $EVENT); [ -n \"$URL\" ] && open -g \"$URL\" &",
            "type" : "command"
          }
        ]
      }
    ],
    "PreToolUse" : [
      {
        "hooks" : [
          {
            "command" : "EVENT=$(cat); URL=$(python3 -c 'import json,sys,urllib.parse,uuid; event=json.loads(sys.argv[1]); raw_session=event[\"session_id\"]; session=str(uuid.uuid5(uuid.NAMESPACE_URL,\"claude-code:\"+raw_session)); payload={\"schemaVersion\":\"1.0\",\"agentId\":\"claude-code\",\"sessionId\":session,\"state\":\"usingTool\",\"detail\":\"Using tool\",\"timestamp\":__import__(\"datetime\").datetime.now(__import__(\"datetime\").timezone.utc).isoformat(timespec=\"milliseconds\").replace(\"+00:00\",\"Z\")}; print(\"notchflow://ai-status?payload=\"+urllib.parse.quote(json.dumps(payload,separators=(\",\",\":\")),safe=\"\"))' $EVENT); [ -n \"$URL\" ] && open -g \"$URL\" &",
            "type" : "command"
          }
        ]
      }
    ],
    "SessionEnd" : [
      {
        "hooks" : [
          {
            "command" : "EVENT=$(cat); URL=$(python3 -c 'import json,sys,urllib.parse,uuid; event=json.loads(sys.argv[1]); raw_session=event[\"session_id\"]; session=str(uuid.uuid5(uuid.NAMESPACE_URL,\"claude-code:\"+raw_session)); payload={\"schemaVersion\":\"1.0\",\"agentId\":\"claude-code\",\"sessionId\":session,\"state\":\"idle\",\"detail\":\"Session ended\",\"timestamp\":__import__(\"datetime\").datetime.now(__import__(\"datetime\").timezone.utc).isoformat(timespec=\"milliseconds\").replace(\"+00:00\",\"Z\")}; print(\"notchflow://ai-status?payload=\"+urllib.parse.quote(json.dumps(payload,separators=(\",\",\":\")),safe=\"\"))' $EVENT); [ -n \"$URL\" ] && open -g \"$URL\" &",
            "type" : "command"
          }
        ]
      }
    ],
    "SessionStart" : [
      {
        "hooks" : [
          {
            "command" : "EVENT=$(cat); URL=$(python3 -c 'import json,sys,urllib.parse,uuid; event=json.loads(sys.argv[1]); raw_session=event[\"session_id\"]; session=str(uuid.uuid5(uuid.NAMESPACE_URL,\"claude-code:\"+raw_session)); payload={\"schemaVersion\":\"1.0\",\"agentId\":\"claude-code\",\"sessionId\":session,\"state\":\"thinking\",\"detail\":\"Session started\",\"timestamp\":__import__(\"datetime\").datetime.now(__import__(\"datetime\").timezone.utc).isoformat(timespec=\"milliseconds\").replace(\"+00:00\",\"Z\")}; print(\"notchflow://ai-status?payload=\"+urllib.parse.quote(json.dumps(payload,separators=(\",\",\":\")),safe=\"\"))' $EVENT); [ -n \"$URL\" ] && open -g \"$URL\" &",
            "type" : "command"
          }
        ]
      }
    ],
    "Stop" : [
      {
        "hooks" : [
          {
            "command" : "EVENT=$(cat); URL=$(python3 -c 'import json,sys,urllib.parse,uuid; event=json.loads(sys.argv[1]); raw_session=event[\"session_id\"]; session=str(uuid.uuid5(uuid.NAMESPACE_URL,\"claude-code:\"+raw_session)); payload={\"schemaVersion\":\"1.0\",\"agentId\":\"claude-code\",\"sessionId\":session,\"state\":\"completed\",\"detail\":\"Task completed\",\"timestamp\":__import__(\"datetime\").datetime.now(__import__(\"datetime\").timezone.utc).isoformat(timespec=\"milliseconds\").replace(\"+00:00\",\"Z\")}; print(\"notchflow://ai-status?payload=\"+urllib.parse.quote(json.dumps(payload,separators=(\",\",\":\")),safe=\"\"))' $EVENT); [ -n \"$URL\" ] && open -g \"$URL\" &",
            "type" : "command"
          }
        ]
      }
    ],
    "StopFailure" : [
      {
        "hooks" : [
          {
            "command" : "EVENT=$(cat); URL=$(python3 -c 'import json,sys,urllib.parse,uuid; event=json.loads(sys.argv[1]); raw_session=event[\"session_id\"]; session=str(uuid.uuid5(uuid.NAMESPACE_URL,\"claude-code:\"+raw_session)); payload={\"schemaVersion\":\"1.0\",\"agentId\":\"claude-code\",\"sessionId\":session,\"state\":\"error\",\"detail\":\"Task failed\",\"timestamp\":__import__(\"datetime\").datetime.now(__import__(\"datetime\").timezone.utc).isoformat(timespec=\"milliseconds\").replace(\"+00:00\",\"Z\")}; print(\"notchflow://ai-status?payload=\"+urllib.parse.quote(json.dumps(payload,separators=(\",\",\":\")),safe=\"\"))' $EVENT); [ -n \"$URL\" ] && open -g \"$URL\" &",
            "type" : "command"
          }
        ]
      }
    ],
    "UserPromptSubmit" : [
      {
        "hooks" : [
          {
            "command" : "EVENT=$(cat); URL=$(python3 -c 'import json,sys,urllib.parse,uuid; event=json.loads(sys.argv[1]); raw_session=event[\"session_id\"]; session=str(uuid.uuid5(uuid.NAMESPACE_URL,\"claude-code:\"+raw_session)); payload={\"schemaVersion\":\"1.0\",\"agentId\":\"claude-code\",\"sessionId\":session,\"state\":\"working\",\"detail\":\"Working\",\"timestamp\":__import__(\"datetime\").datetime.now(__import__(\"datetime\").timezone.utc).isoformat(timespec=\"milliseconds\").replace(\"+00:00\",\"Z\")}; print(\"notchflow://ai-status?payload=\"+urllib.parse.quote(json.dumps(payload,separators=(\",\",\":\")),safe=\"\"))' $EVENT); [ -n \"$URL\" ] && open -g \"$URL\" &",
            "type" : "command"
          }
        ]
      }
    ]
  }
}
```

### Codex CLI

Codex CLI supports one `notify` argv setting in `~/.codex/config.toml`. Codex spawns that program directly and appends event JSON as the final argument. NotchFlow therefore emits a direct three-element Python command (`python3`, `-c`, script), without shell interpolation. The script reads Codex's appended argument, derives the session UUID from `thread-id`, and launches `open -g` detached.

The installer parses both single-line and multiline root `notify` arrays. If another notifier already exists, NotchFlow preserves its argv and forwards every event to it before sending its own status. This is required for tools such as Codex Computer Use: installing NotchFlow must not disable an existing notification integration. Original bytes are still backed up and restored on uninstall.

<!-- notchflow-snippet: codex -->
```toml
notify = ["python3","-c","import datetime,json,subprocess,sys,urllib.parse,uuid; notchflow_codex_notify_v2=True; notchflow_forward_b64='W10='; forward=[]; event_args=sys.argv[1:]; event_json=event_args[0]; event=json.loads(event_json); raw_session=event[\"thread-id\"]; session=str(uuid.uuid5(uuid.NAMESPACE_URL,\"codex:\"+raw_session)); payload={\"schemaVersion\":\"1.0\",\"agentId\":\"codex\",\"sessionId\":session,\"state\":\"completed\",\"detail\":\"Turn completed\",\"timestamp\":datetime.datetime.now(datetime.timezone.utc).isoformat(timespec=\"milliseconds\").replace(\"+00:00\",\"Z\")}; url=\"notchflow://ai-status?payload=\"+urllib.parse.quote(json.dumps(payload,separators=(\",\",\":\")),safe=\"\"); forward and subprocess.Popen(forward+event_args,start_new_session=True,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); subprocess.Popen([\"open\",\"-g\",url],start_new_session=True,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"]
```

### OpenCode

OpenCode uses a plugin file convention: a plugin file placed in OpenCode's plugin directory observes session lifecycle events and can act on them directly. NotchFlow's installer writes a small TypeScript plugin that maps those events onto the same IPC envelope and sends it via the URL scheme, the same way the Claude Code and Codex snippets do: `session.created` becomes `thinking`, `session.idle` becomes `completed`, `session.error` becomes `error`, `tool.execute.before` becomes `usingTool`, and `tool.execute.after` becomes `working`. The plugin derives a stable session UUID from the session id and dispatches each message as a detached `open -g` call, so it never blocks OpenCode's own execution.

The literal plugin file the installer writes, exactly as `HookSnippetGenerator` emits it:

<!-- notchflow-snippet: opencode -->
```ts
import type { Plugin } from "@opencode-ai/plugin"
import { spawn } from "node:child_process"
import { createHash } from "node:crypto"

const sessionUUID = (agentId: string, sessionId: string) => {
  const bytes = createHash("sha256").update(`${agentId}:${sessionId}`).digest().subarray(0, 16)
  bytes[6] = (bytes[6] & 0x0f) | 0x50
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  const hex = bytes.toString("hex")
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

const notify = (state: string, sessionId: string, detail: string) => {
  const payload = {
    schemaVersion: "1.0",
    agentId: "opencode",
    sessionId: sessionUUID("opencode", sessionId),
    state,
    detail,
    timestamp: new Date().toISOString(),
  }
  const url = `notchflow://ai-status?payload=${encodeURIComponent(JSON.stringify(payload))}`
  const child = spawn("open", ["-g", url], { detached: true, stdio: "ignore" })
  child.unref()
}

export const NotchFlowPlugin: Plugin = async () => ({
  event: async ({ event }) => {
    switch (event.type) {
      case "session.created":
        notify("thinking", event.properties.info.id, "Session started")
        break
      case "session.idle":
        notify("completed", event.properties.sessionID, "Session completed")
        break
      case "session.error":
        notify("error", event.properties.sessionID, "Session error")
        break
    }
  },
  "tool.execute.before": async (input) => {
    notify("usingTool", input.sessionID, "Using tool")
  },
  "tool.execute.after": async (input) => {
    notify("working", input.sessionID, "Tool completed")
  },
})
```

## The hook installer

NotchFlow writes an agent configuration only after that agent has been explicitly enabled or its install action accepted. The installer flow is:

1. **Detect.** On first run and on demand from Settings, NotchFlow checks for the presence of `~/.claude/settings.json`, `~/.codex/config.toml`, and an OpenCode plugin directory, to determine which agents are installed on the machine.
2. **Propose.** For each detected agent, NotchFlow shows the user the exact snippet it would add or change — not a summary, the literal text — before touching anything.
3. **Consent.** Nothing is written until the user explicitly approves. There is no "recommended settings" default that writes on the user's behalf.
4. **Back up.** Before writing, NotchFlow copies the original file alongside itself (e.g. `settings.json.notchflow-backup`) so the change is trivially reversible outside the app as well as through it.
5. **Uninstall.** A one-click "Remove NotchFlow hooks" action in Settings reverses the change, restoring the backed-up file or removing exactly the entries NotchFlow added.
6. **Repair.** On later launches, an enabled agent whose generated hook is missing or older is repaired automatically. This reuses the user's existing enablement consent; disabled agents are never changed.

### Sandbox note

The App Store build's App Sandbox does not permit writing to `~/.claude` or `~/.codex`, and it has no user-selected-file entitlement or file-picker flow. It therefore shows each hook or plugin as a copyable snippet for manual installation. The Direct build has no sandbox restriction on the home directory and may write directly once the user consents in-app; if the user declines, it also leaves the snippet available for manual installation.

## Privacy

NotchFlow stores no prompt content, no code, and no transcript from any agent. Only the state enum, the short `detail` label, and the optional `toolName` cross the process boundary — never the arguments passed to a tool, the diff produced by an edit, or any excerpt of the agent's reasoning. This is deliberate: the notch is a status indicator, not a monitoring surface, and the IPC envelope's schema physically has no field wide enough to carry more than a one-line label.

## Agents not in V1

Claude Desktop, ChatGPT desktop, Cursor, Copilot, and Gemini CLI expose no public status hook as of V1 and are therefore not integrated. Each is revisited in `13-deferred-backlog.md` if and when a public extension point appears.
