# AI Integration

This document specifies the AI agent state machine, the IPC protocol that carries agent state into NotchFlow, the per-agent hook integrations for Claude Code, Codex CLI, and OpenCode, and the hook installer's consent model. It is a design specification — nothing in this folder is code.

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

Claude Code supports hook configuration in `~/.claude/settings.json`. NotchFlow's installer adds a hook entry that maps Claude Code's `PreToolUse` event to an IPC message.

| Claude Code hook event | NotchFlow state sent |
|---|---|
| `PreToolUse` | `usingTool` (with `toolName` set to `$CLAUDE_SESSION_ID`) |

The generated snippet covers `PreToolUse` only — the hook that fires most frequently and gives the most useful signal (the agent is actively running a tool). Other lifecycle events (`SessionStart`, `PostToolUse`, `Notification`, `Stop`) are not wired in V1; the agent's state transitions to `usingTool` on tool invocation and the activity ends when the session ends or the user dismisses it.

Claude Code hooks receive the event as JSON on stdin. The generated hook command is **asynchronous** — it fires the IPC call and returns immediately — so NotchFlow's presence never adds latency to the agent's own execution. The snippet uses the URL-scheme transport with `open -g` precisely because it backgrounds trivially from a shell hook.

Example snippet NotchFlow proposes for `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "notchflow-notify --agent claude-code --state usingTool --session \"$CLAUDE_SESSION_ID\" &"
          }
        ]
      }
    ]
  }
}
```

### Codex CLI

Codex CLI supports a `notify` program setting in `~/.codex/config.toml`, invoked with a single JSON argument describing the event. NotchFlow's installer points this setting at a small forwarding call that translates the Codex event into the envelope and sends it via the URL scheme.

Example snippet NotchFlow proposes for `~/.codex/config.toml`:

```toml
notify = ["notchflow-notify", "--agent", "codex"]
```

### OpenCode

OpenCode uses a plugin file convention: a plugin file placed in OpenCode's plugin directory observes session lifecycle events (start, tool call, idle, completion) and can act on them directly. NotchFlow's installer writes a small plugin that maps those events to the same IPC envelope and sends it via the URL scheme, the same way the Claude Code and Codex snippets do.

## The hook installer

NotchFlow never edits an agent's configuration file silently. The installer flow is:

1. **Detect.** On first run and on demand from Settings, NotchFlow checks for the presence of `~/.claude/settings.json`, `~/.codex/config.toml`, and an OpenCode plugin directory, to determine which agents are installed on the machine.
2. **Propose.** For each detected agent, NotchFlow shows the user the exact snippet it would add or change — not a summary, the literal text — before touching anything.
3. **Consent.** Nothing is written until the user explicitly approves. There is no "recommended settings" default that writes on the user's behalf.
4. **Back up.** Before writing, NotchFlow copies the original file alongside itself (e.g. `settings.json.notchflow-backup`) so the change is trivially reversible outside the app as well as through it.
5. **Uninstall.** A one-click "Remove NotchFlow hooks" action in Settings reverses the change, restoring the backed-up file or removing exactly the entries NotchFlow added.

### Sandbox note

The App Store build's App Sandbox does not permit writing to `~/.claude` or `~/.codex` without the user granting access to that specific location. In the App Store build, the installer opens an `NSOpenPanel` scoped to the target file, and on approval stores a security-scoped bookmark so it can write again later (for example, on uninstall) without asking again. The Direct build has no sandbox restriction on the home directory and may write directly once the user consents in-app. In both builds, if the user declines to grant write access, NotchFlow still shows the exact snippet in a copyable text view so the user can add it by hand.

## Privacy

NotchFlow stores no prompt content, no code, and no transcript from any agent. Only the state enum, the short `detail` label, and the optional `toolName` cross the process boundary — never the arguments passed to a tool, the diff produced by an edit, or any excerpt of the agent's reasoning. This is deliberate: the notch is a status indicator, not a monitoring surface, and the IPC envelope's schema physically has no field wide enough to carry more than a one-line label.

## Agents not in V1

Claude Desktop, ChatGPT desktop, Cursor, Copilot, and Gemini CLI expose no public status hook as of V1 and are therefore not integrated. Each is revisited in `13-deferred-backlog.md` if and when a public extension point appears.
