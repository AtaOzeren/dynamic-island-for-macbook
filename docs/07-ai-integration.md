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
| `reason` | string enum: `"quotaExhausted"` \| `"authFailed"` \| `"providerUnavailable"` \| `"requestRejected"` \| `"unknown"` | no | Why the turn failed. Meaningful only when `state` is `"error"`, and dropped otherwise. A closed vocabulary rather than the provider's own message: the island localises what it draws, the validator rejects the punctuation provider errors are full of (`[glm/glm-5.2] [429]` carries brackets from the forbidden set), and a fixed set of causes cannot smuggle a prompt onto the screen. An unrecognised value degrades to `unknown` rather than rejecting the envelope — a failure reported without a name still has to reach the user. |
| `retryAt` | string (ISO 8601) | no | When the condition named by `reason` lifts on its own. Only `quotaExhausted` ever does, so only it carries one. An unparseable value is dropped, never allowed to suppress the failure it describes. |
| `rootSessionId` | string (UUID) | no | The top-level session this one belongs to, when it is a sub-agent the agent spawned. Omitted for a session the user started; a value equal to `sessionId` is treated as omitted. Added after 1.0 and deliberately not a version bump — an optional field an older island ignores and an older hook never sends is compatible in both directions, while raising the version would reject every hook already installed. |
| `sessionName` | string | no | What to call a sub-agent in its parent card's list (e.g. `"explore"`). Same length and character rules as `detail`. |
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
    "rootSessionId": { "type": "string", "format": "uuid" },
    "sessionName": { "type": "string", "maxLength": 280 },
    "reason": {
      "type": "string",
      "enum": ["quotaExhausted", "authFailed", "providerUnavailable", "requestRejected", "unknown"]
    },
    "retryAt": { "type": "string", "format": "date-time" },
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

Generated agent hooks use only the **HTTP listener** and silently drop events when NotchFlow is not running, so agent activity can never launch an app the user quit. The custom URL scheme remains available to callers that explicitly choose it.

Multiple sessions remain separate activities in the manager, grouped for presentation at two levels.

An **instance** is one thing the user started: a terminal, an editor window, a conversation. A **sub-agent** is a session the agent itself spawned to delegate work, identified by `rootSessionId` naming its parent. The distinction matters because only instances are counted: one OpenCode terminal fanning out to four sub-agents is one agent running, and badging it `5` would report how busy the agent is rather than how many of it there are.

The compact pill groups by `agentId` — one icon per agent, drawn in the most important state across every session of that agent (`error`, then needs-input, then active work, then completed), with the number of *instances* behind it badged on the icon's top-right corner once there is more than one. The expanded panel draws one card per instance, numbered per agent in registration order where an agent has more than one. A card with sub-agents carries a control saying how many (`4 agents`) that discloses them, each row named after the delegated agent. Each card's navigation action traces a live CLI process to its parent app when possible, then uses deterministic running-app fallbacks; it never chooses randomly between multiple hosts.

Only OpenCode reports sub-agents today: its `task` tool creates real child sessions with their own identifiers, so the plugin tracks parentage from `session.created` and `session.updated` and sends the root alongside each message. Claude Code and Codex run their sub-agents inside the session that spawned them and report one `session_id` throughout, so nothing to resolve and nothing changes for them.

An instance ending ends the sub-agents under it. Nothing else can report them: the agent that would have sent the message is the process that exited. A sub-agent ending takes nothing with it — one delegated task finishing says nothing about its siblings or about the instance that spawned it.

## When an agent cannot run at all

`session.idle` means a session stopped, not that it succeeded. A turn that died on a rate limit goes idle exactly as one that finished does, and the island used to read the difference as success — a green tick on work that never ran, every forty seconds, for as long as the agent kept retrying.

Each agent surfaces the difference differently, and the island claims success only where it has actually seen it:

| Agent | Failure signal | What NotchFlow does |
|---|---|---|
| Claude Code | `StopFailure`, which fires when a turn ends on an API error rather than on Claude finishing, carrying a closed `error` enum (`rate_limit`, `account_on_hold`, `billing_error`, `authentication_failed`, `oauth_org_not_allowed`, `overloaded`, `server_error`, `invalid_request`, `model_not_found`, `max_output_tokens`) | Subscribes to it and maps that enum onto `reason`. `Stop` keeps meaning success, because the two are mutually exclusive. |
| OpenCode | None. Plugins cannot observe a 429 at all ([anomalyco/opencode#10432](https://github.com/anomalyco/opencode/issues/10432)), and `session.error` fires after perfectly normal completions too — mapping it to red painted finished work as failed. | On `session.idle` the plugin asks the server what the last assistant message says. `error.data.statusCode` classifies the cause without parsing prose: 402 and 429 are quota, 401 and 403 are credentials, 529 and an `overloaded_error` body are the provider, other 4xx are the request. `MessageAbortedError` — by far the most common stored error — is neither success nor failure and reports nothing. |
| Codex | Not established. Its documented events cover the work loop and the turn boundary, not failures. | Nothing yet. Guessing at an event name would install a hook that never fires while claiming the problem was solved. |

A failure the user cannot clear by waiting for the agent — no quota, no credentials, no provider — is a *standing condition* rather than news, and the island says it twice in two different ways. See `docs/04-overlay-window.md` for where each lands.

## When a card outlives its agent

Every state carries a silence bound, restarted by each message for that session, because a hook only fires while its agent is alive. The bound differs by what the state claims:

| States | Bound | Why |
|---|---|---|
| `thinking`, `working`, `usingTool` | 10 minutes | They assert work in flight and more events coming, so prolonged silence contradicts the state. Still long enough that a single silent tool call — a test suite, a build — is never cut off mid-run. |
| `waitingForUser`, `error` | 30 minutes | Sitting still is what they mean, so silence tells nothing new. A failure the user could miss is worse than one that lingers. |
| `completed` | 15 seconds | A display timeout, not a silence one: the task is over and the card is a receipt. |

The bound is a safety net, not the mechanism. Closing an OpenCode window is neither the end of a turn nor the deletion of a session, so OpenCode emits nothing and the last `working` used to sit on screen for the full half hour after the process was gone. The plugin now says so on the way out: a `process.on("exit")` handler sends `idle` synchronously for each top-level session it reported, bounded to a handful so quitting stays fast. It deliberately registers no signal handler — doing so suppresses Node's default termination, and an agent that no longer quits on Ctrl-C is a far worse defect than a card that lingers. A session lost to `SIGKILL` is what the silence bound is for.

Concurrency is not confined to terminals. Both the Claude Code desktop app and the Codex app run several sessions in parallel, and each session carries its own `session_id`, so the island tracks them exactly as it tracks two terminal windows. Two limits are worth stating because neither is fixable here:

- **Codex desktop app.** Its sessions run in app-server mode, where `notify` and lifecycle hooks are not delivered ([openai/codex#13019](https://github.com/openai/codex/issues/13019), [openai/codex#21639](https://github.com/openai/codex/issues/21639)). NotchFlow shows nothing for those sessions until Codex delivers the events; Codex CLI sessions are unaffected.
- **Claude Desktop (the chat app)** is not a coding agent and has no hook mechanism at all. Per the design principle above there is nothing to infer from, so it is out of scope rather than unimplemented. Claude Code *inside* the desktop app is a different thing and does fire the hooks from `~/.claude/settings.json`.

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
| `UserPromptSubmit` | `thinking` (detail "Task started") |
| `PreToolUse` | `usingTool` (detail "Using tool"; the session id is derived from the event JSON's `session_id` field) |
| `PostToolUse` | `working` (detail "Tool completed") |
| `Notification` | `waitingForUser` (detail "Needs attention") |
| `Stop` | `completed` (detail "Task completed") |
| `SessionEnd` | `idle` (ends presentation immediately) |
| `SubagentStart` | `working` (detail "Sub-agent started"; carries sub-agent identity) |
| `SubagentStop` | `completed` (detail "Sub-agent completed"; carries sub-agent identity) |

Claude Code hooks receive the event as JSON on stdin. The generated hook command is **asynchronous** — it fires the IPC call and returns immediately — so NotchFlow's presence never adds latency to the agent's own execution. The snippet uses the URL-scheme transport with `open -g` precisely because it backgrounds trivially from a shell hook.

<!-- notchflow-snippet: claude-code -->
```json
{
  "hooks" : {
    "Notification" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, sys, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v4 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(\n    session,\n    state,\n    detail,\n    tool_name=None,\n    root_session=None,\n    session_name=None,\n    workspace=None,\n    reason=None,\n):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    if root_session:\n        payload[\"rootSessionId\"] = root_session\n    if session_name:\n        payload[\"sessionName\"] = session_name\n    if workspace:\n        payload[\"workspace\"] = workspace\n    if state == \"error\" and reason:\n        payload[\"reason\"] = reason\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\n# Claude Code names the cause in a closed set of its own. Mapped here\n# rather than passed through, because the island localises what it draws\n# and the validator refuses the punctuation a raw provider message is\n# full of.\nNOTCHFLOW_REASONS = {\n    \"rate_limit\": \"quotaExhausted\",\n    \"account_on_hold\": \"quotaExhausted\",\n    \"billing_error\": \"quotaExhausted\",\n    \"authentication_failed\": \"authFailed\",\n    \"oauth_org_not_allowed\": \"authFailed\",\n    \"overloaded\": \"providerUnavailable\",\n    \"server_error\": \"providerUnavailable\",\n    \"invalid_request\": \"requestRejected\",\n    \"model_not_found\": \"requestRejected\",\n    \"max_output_tokens\": \"requestRejected\",\n}\n\n\ndef notchflow_reason(event):\n    return NOTCHFLOW_REASONS.get(str(event.get(\"error\") or \"\"), \"unknown\")\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# Deliver only to a running island. Missing or stale discovery data is\n# expected when NotchFlow is not running, so failed events are dropped.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n    except Exception:\n        pass\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"waitingForUser\",\n        \"Needs attention\",\n        None,\n        None,\n        None,\n        event.get(\"cwd\"),\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "PostToolUse" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, sys, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v4 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(\n    session,\n    state,\n    detail,\n    tool_name=None,\n    root_session=None,\n    session_name=None,\n    workspace=None,\n    reason=None,\n):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    if root_session:\n        payload[\"rootSessionId\"] = root_session\n    if session_name:\n        payload[\"sessionName\"] = session_name\n    if workspace:\n        payload[\"workspace\"] = workspace\n    if state == \"error\" and reason:\n        payload[\"reason\"] = reason\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\n# Claude Code names the cause in a closed set of its own. Mapped here\n# rather than passed through, because the island localises what it draws\n# and the validator refuses the punctuation a raw provider message is\n# full of.\nNOTCHFLOW_REASONS = {\n    \"rate_limit\": \"quotaExhausted\",\n    \"account_on_hold\": \"quotaExhausted\",\n    \"billing_error\": \"quotaExhausted\",\n    \"authentication_failed\": \"authFailed\",\n    \"oauth_org_not_allowed\": \"authFailed\",\n    \"overloaded\": \"providerUnavailable\",\n    \"server_error\": \"providerUnavailable\",\n    \"invalid_request\": \"requestRejected\",\n    \"model_not_found\": \"requestRejected\",\n    \"max_output_tokens\": \"requestRejected\",\n}\n\n\ndef notchflow_reason(event):\n    return NOTCHFLOW_REASONS.get(str(event.get(\"error\") or \"\"), \"unknown\")\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# Deliver only to a running island. Missing or stale discovery data is\n# expected when NotchFlow is not running, so failed events are dropped.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n    except Exception:\n        pass\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"working\",\n        \"Tool completed\",\n        None,\n        None,\n        None,\n        event.get(\"cwd\"),\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "PreToolUse" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, sys, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v4 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(\n    session,\n    state,\n    detail,\n    tool_name=None,\n    root_session=None,\n    session_name=None,\n    workspace=None,\n    reason=None,\n):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    if root_session:\n        payload[\"rootSessionId\"] = root_session\n    if session_name:\n        payload[\"sessionName\"] = session_name\n    if workspace:\n        payload[\"workspace\"] = workspace\n    if state == \"error\" and reason:\n        payload[\"reason\"] = reason\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\n# Claude Code names the cause in a closed set of its own. Mapped here\n# rather than passed through, because the island localises what it draws\n# and the validator refuses the punctuation a raw provider message is\n# full of.\nNOTCHFLOW_REASONS = {\n    \"rate_limit\": \"quotaExhausted\",\n    \"account_on_hold\": \"quotaExhausted\",\n    \"billing_error\": \"quotaExhausted\",\n    \"authentication_failed\": \"authFailed\",\n    \"oauth_org_not_allowed\": \"authFailed\",\n    \"overloaded\": \"providerUnavailable\",\n    \"server_error\": \"providerUnavailable\",\n    \"invalid_request\": \"requestRejected\",\n    \"model_not_found\": \"requestRejected\",\n    \"max_output_tokens\": \"requestRejected\",\n}\n\n\ndef notchflow_reason(event):\n    return NOTCHFLOW_REASONS.get(str(event.get(\"error\") or \"\"), \"unknown\")\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# Deliver only to a running island. Missing or stale discovery data is\n# expected when NotchFlow is not running, so failed events are dropped.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n    except Exception:\n        pass\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"usingTool\",\n        \"Using tool\",\n        notchflow_tool_name(event),\n        None,\n        None,\n        event.get(\"cwd\"),\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "SessionEnd" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, sys, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v4 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(\n    session,\n    state,\n    detail,\n    tool_name=None,\n    root_session=None,\n    session_name=None,\n    workspace=None,\n    reason=None,\n):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    if root_session:\n        payload[\"rootSessionId\"] = root_session\n    if session_name:\n        payload[\"sessionName\"] = session_name\n    if workspace:\n        payload[\"workspace\"] = workspace\n    if state == \"error\" and reason:\n        payload[\"reason\"] = reason\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\n# Claude Code names the cause in a closed set of its own. Mapped here\n# rather than passed through, because the island localises what it draws\n# and the validator refuses the punctuation a raw provider message is\n# full of.\nNOTCHFLOW_REASONS = {\n    \"rate_limit\": \"quotaExhausted\",\n    \"account_on_hold\": \"quotaExhausted\",\n    \"billing_error\": \"quotaExhausted\",\n    \"authentication_failed\": \"authFailed\",\n    \"oauth_org_not_allowed\": \"authFailed\",\n    \"overloaded\": \"providerUnavailable\",\n    \"server_error\": \"providerUnavailable\",\n    \"invalid_request\": \"requestRejected\",\n    \"model_not_found\": \"requestRejected\",\n    \"max_output_tokens\": \"requestRejected\",\n}\n\n\ndef notchflow_reason(event):\n    return NOTCHFLOW_REASONS.get(str(event.get(\"error\") or \"\"), \"unknown\")\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# Deliver only to a running island. Missing or stale discovery data is\n# expected when NotchFlow is not running, so failed events are dropped.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n    except Exception:\n        pass\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"idle\",\n        \"Session ended\",\n        None,\n        None,\n        None,\n        event.get(\"cwd\"),\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "Stop" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, sys, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v4 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(\n    session,\n    state,\n    detail,\n    tool_name=None,\n    root_session=None,\n    session_name=None,\n    workspace=None,\n    reason=None,\n):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    if root_session:\n        payload[\"rootSessionId\"] = root_session\n    if session_name:\n        payload[\"sessionName\"] = session_name\n    if workspace:\n        payload[\"workspace\"] = workspace\n    if state == \"error\" and reason:\n        payload[\"reason\"] = reason\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\n# Claude Code names the cause in a closed set of its own. Mapped here\n# rather than passed through, because the island localises what it draws\n# and the validator refuses the punctuation a raw provider message is\n# full of.\nNOTCHFLOW_REASONS = {\n    \"rate_limit\": \"quotaExhausted\",\n    \"account_on_hold\": \"quotaExhausted\",\n    \"billing_error\": \"quotaExhausted\",\n    \"authentication_failed\": \"authFailed\",\n    \"oauth_org_not_allowed\": \"authFailed\",\n    \"overloaded\": \"providerUnavailable\",\n    \"server_error\": \"providerUnavailable\",\n    \"invalid_request\": \"requestRejected\",\n    \"model_not_found\": \"requestRejected\",\n    \"max_output_tokens\": \"requestRejected\",\n}\n\n\ndef notchflow_reason(event):\n    return NOTCHFLOW_REASONS.get(str(event.get(\"error\") or \"\"), \"unknown\")\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# Deliver only to a running island. Missing or stale discovery data is\n# expected when NotchFlow is not running, so failed events are dropped.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n    except Exception:\n        pass\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"completed\",\n        \"Task completed\",\n        None,\n        None,\n        None,\n        event.get(\"cwd\"),\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "StopFailure" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, sys, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v4 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(\n    session,\n    state,\n    detail,\n    tool_name=None,\n    root_session=None,\n    session_name=None,\n    workspace=None,\n    reason=None,\n):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    if root_session:\n        payload[\"rootSessionId\"] = root_session\n    if session_name:\n        payload[\"sessionName\"] = session_name\n    if workspace:\n        payload[\"workspace\"] = workspace\n    if state == \"error\" and reason:\n        payload[\"reason\"] = reason\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\n# Claude Code names the cause in a closed set of its own. Mapped here\n# rather than passed through, because the island localises what it draws\n# and the validator refuses the punctuation a raw provider message is\n# full of.\nNOTCHFLOW_REASONS = {\n    \"rate_limit\": \"quotaExhausted\",\n    \"account_on_hold\": \"quotaExhausted\",\n    \"billing_error\": \"quotaExhausted\",\n    \"authentication_failed\": \"authFailed\",\n    \"oauth_org_not_allowed\": \"authFailed\",\n    \"overloaded\": \"providerUnavailable\",\n    \"server_error\": \"providerUnavailable\",\n    \"invalid_request\": \"requestRejected\",\n    \"model_not_found\": \"requestRejected\",\n    \"max_output_tokens\": \"requestRejected\",\n}\n\n\ndef notchflow_reason(event):\n    return NOTCHFLOW_REASONS.get(str(event.get(\"error\") or \"\"), \"unknown\")\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# Deliver only to a running island. Missing or stale discovery data is\n# expected when NotchFlow is not running, so failed events are dropped.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n    except Exception:\n        pass\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"error\",\n        \"Task failed\",\n        None,\n        None,\n        None,\n        event.get(\"cwd\"),\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "SubagentStart" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, sys, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v4 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(\n    session,\n    state,\n    detail,\n    tool_name=None,\n    root_session=None,\n    session_name=None,\n    workspace=None,\n    reason=None,\n):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    if root_session:\n        payload[\"rootSessionId\"] = root_session\n    if session_name:\n        payload[\"sessionName\"] = session_name\n    if workspace:\n        payload[\"workspace\"] = workspace\n    if state == \"error\" and reason:\n        payload[\"reason\"] = reason\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\n# Claude Code names the cause in a closed set of its own. Mapped here\n# rather than passed through, because the island localises what it draws\n# and the validator refuses the punctuation a raw provider message is\n# full of.\nNOTCHFLOW_REASONS = {\n    \"rate_limit\": \"quotaExhausted\",\n    \"account_on_hold\": \"quotaExhausted\",\n    \"billing_error\": \"quotaExhausted\",\n    \"authentication_failed\": \"authFailed\",\n    \"oauth_org_not_allowed\": \"authFailed\",\n    \"overloaded\": \"providerUnavailable\",\n    \"server_error\": \"providerUnavailable\",\n    \"invalid_request\": \"requestRejected\",\n    \"model_not_found\": \"requestRejected\",\n    \"max_output_tokens\": \"requestRejected\",\n}\n\n\ndef notchflow_reason(event):\n    return NOTCHFLOW_REASONS.get(str(event.get(\"error\") or \"\"), \"unknown\")\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# Deliver only to a running island. Missing or stale discovery data is\n# expected when NotchFlow is not running, so failed events are dropped.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n    except Exception:\n        pass\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"agent_id\")),\n        \"working\",\n        \"Sub-agent started\",\n        None,\n        notchflow_session(event.get(\"session_id\")),\n        event.get(\"agent_type\"),\n        event.get(\"cwd\"),\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "SubagentStop" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, sys, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v4 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(\n    session,\n    state,\n    detail,\n    tool_name=None,\n    root_session=None,\n    session_name=None,\n    workspace=None,\n    reason=None,\n):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    if root_session:\n        payload[\"rootSessionId\"] = root_session\n    if session_name:\n        payload[\"sessionName\"] = session_name\n    if workspace:\n        payload[\"workspace\"] = workspace\n    if state == \"error\" and reason:\n        payload[\"reason\"] = reason\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\n# Claude Code names the cause in a closed set of its own. Mapped here\n# rather than passed through, because the island localises what it draws\n# and the validator refuses the punctuation a raw provider message is\n# full of.\nNOTCHFLOW_REASONS = {\n    \"rate_limit\": \"quotaExhausted\",\n    \"account_on_hold\": \"quotaExhausted\",\n    \"billing_error\": \"quotaExhausted\",\n    \"authentication_failed\": \"authFailed\",\n    \"oauth_org_not_allowed\": \"authFailed\",\n    \"overloaded\": \"providerUnavailable\",\n    \"server_error\": \"providerUnavailable\",\n    \"invalid_request\": \"requestRejected\",\n    \"model_not_found\": \"requestRejected\",\n    \"max_output_tokens\": \"requestRejected\",\n}\n\n\ndef notchflow_reason(event):\n    return NOTCHFLOW_REASONS.get(str(event.get(\"error\") or \"\"), \"unknown\")\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# Deliver only to a running island. Missing or stale discovery data is\n# expected when NotchFlow is not running, so failed events are dropped.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n    except Exception:\n        pass\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"agent_id\")),\n        \"completed\",\n        \"Sub-agent completed\",\n        None,\n        notchflow_session(event.get(\"session_id\")),\n        event.get(\"agent_type\"),\n        event.get(\"cwd\"),\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "UserPromptSubmit" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, sys, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v4 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(\n    session,\n    state,\n    detail,\n    tool_name=None,\n    root_session=None,\n    session_name=None,\n    workspace=None,\n    reason=None,\n):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    if root_session:\n        payload[\"rootSessionId\"] = root_session\n    if session_name:\n        payload[\"sessionName\"] = session_name\n    if workspace:\n        payload[\"workspace\"] = workspace\n    if state == \"error\" and reason:\n        payload[\"reason\"] = reason\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\n# Claude Code names the cause in a closed set of its own. Mapped here\n# rather than passed through, because the island localises what it draws\n# and the validator refuses the punctuation a raw provider message is\n# full of.\nNOTCHFLOW_REASONS = {\n    \"rate_limit\": \"quotaExhausted\",\n    \"account_on_hold\": \"quotaExhausted\",\n    \"billing_error\": \"quotaExhausted\",\n    \"authentication_failed\": \"authFailed\",\n    \"oauth_org_not_allowed\": \"authFailed\",\n    \"overloaded\": \"providerUnavailable\",\n    \"server_error\": \"providerUnavailable\",\n    \"invalid_request\": \"requestRejected\",\n    \"model_not_found\": \"requestRejected\",\n    \"max_output_tokens\": \"requestRejected\",\n}\n\n\ndef notchflow_reason(event):\n    return NOTCHFLOW_REASONS.get(str(event.get(\"error\") or \"\"), \"unknown\")\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# Deliver only to a running island. Missing or stale discovery data is\n# expected when NotchFlow is not running, so failed events are dropped.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n    except Exception:\n        pass\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"thinking\",\n        \"Task started\",\n        None,\n        None,\n        None,\n        event.get(\"cwd\"),\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
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

Beyond `notify`, the installer registers lifecycle hooks in `~/.codex/hooks.json`, mapping the same semantic milestones Claude Code reports onto the same states:

| Codex hook event | NotchFlow state sent |
|---|---|
| `UserPromptSubmit` | `thinking` (detail "Task started") |
| `PreToolUse` | `usingTool` (detail "Using tool"; carries the tool name) |
| `PostToolUse` | `working` (detail "Working…") |
| `PermissionRequest` | `waitingForUser` (detail "Needs attention") |
| `Stop` | `completed` (detail "Task completed") |
| `SessionEnd` | `idle` (ends presentation immediately) |

`SessionEnd` fires when Codex closes normally, when the conversation is archived or deleted while open, or after it has been idle and unopened for thirty minutes — so a Codex session tears down through the same immediate `idle` path as Claude Code's `SessionEnd` and OpenCode's `session.deleted`, rather than waiting out a silence bound. Codex has no `Notification` event; `PermissionRequest` alone covers "needs the user". An abrupt kill (`SIGKILL`, crash) is not observable from a per-invocation hook script for any agent — that case is what the silence bound is for.

<!-- notchflow-snippet: codex -->
```toml
notify = ["/usr/bin/python3","-c","import datetime, json, os, sys, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"codex\"\nnotchflow_hook_v4 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(\n    session,\n    state,\n    detail,\n    tool_name=None,\n    root_session=None,\n    session_name=None,\n    workspace=None,\n    reason=None,\n):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    if root_session:\n        payload[\"rootSessionId\"] = root_session\n    if session_name:\n        payload[\"sessionName\"] = session_name\n    if workspace:\n        payload[\"workspace\"] = workspace\n    if state == \"error\" and reason:\n        payload[\"reason\"] = reason\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\n# Claude Code names the cause in a closed set of its own. Mapped here\n# rather than passed through, because the island localises what it draws\n# and the validator refuses the punctuation a raw provider message is\n# full of.\nNOTCHFLOW_REASONS = {\n    \"rate_limit\": \"quotaExhausted\",\n    \"account_on_hold\": \"quotaExhausted\",\n    \"billing_error\": \"quotaExhausted\",\n    \"authentication_failed\": \"authFailed\",\n    \"oauth_org_not_allowed\": \"authFailed\",\n    \"overloaded\": \"providerUnavailable\",\n    \"server_error\": \"providerUnavailable\",\n    \"invalid_request\": \"requestRejected\",\n    \"model_not_found\": \"requestRejected\",\n    \"max_output_tokens\": \"requestRejected\",\n}\n\n\ndef notchflow_reason(event):\n    return NOTCHFLOW_REASONS.get(str(event.get(\"error\") or \"\"), \"unknown\")\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# Deliver only to a running island. Missing or stale discovery data is\n# expected when NotchFlow is not running, so failed events are dropped.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n    except Exception:\n        pass\n\nnotchflow_codex_notify_v4 = True\nforward = json.loads(\"[]\")\nevent_args = sys.argv[1:]\nforward and subprocess.Popen(\n    forward + event_args,\n    start_new_session=True,\n    stdin=subprocess.DEVNULL,\n    stdout=subprocess.DEVNULL,\n    stderr=subprocess.DEVNULL,\n)\nif not event_args:\n    sys.exit(0)\nevent = notchflow_load(event_args[0])\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"thread-id\") or event.get(\"thread_id\")),\n        \"completed\",\n        \"Turn completed\",\n    )\n)"]
```

### OpenCode

OpenCode uses a plugin file convention: a plugin file placed in OpenCode's plugin directory observes session lifecycle events and can act on them directly. NotchFlow's installer writes a small TypeScript plugin that maps those events onto the same IPC envelope: `chat.message` becomes `thinking`, `session.idle` becomes `completed`, `session.error` becomes `error`, `permission.asked` becomes `waitingForUser`, `tool.execute.before` becomes `usingTool`, `tool.execute.after` becomes `working`, and `session.deleted` becomes `idle` (ending the presentation immediately, like the other agents' session-end events). The plugin derives a stable session UUID from the session id, prefers the loopback socket and falls back to a detached `open -g` call, so it never blocks OpenCode's own execution.\n\nIt also watches `session.created` and `session.updated` — sending nothing for either — purely to record which session is a child of which. OpenCode's `task` tool gives every sub-agent a real child session carrying `parentID`, so the plugin walks that chain to the root and sends it as `rootSessionId`, with the delegated agent's name as `sessionName`. A session created before the plugin loaded is backfilled once through `client.session.get`; if that lookup fails the session is treated as a root, which is exactly how the plugin behaved before sub-agents were resolved at all.

The literal plugin file the installer writes, exactly as `HookSnippetGenerator` emits it:

<!-- notchflow-snippet: opencode -->
```ts
import type { Plugin } from "@opencode-ai/plugin"
// Node does not await promises in exit handlers, so spawnSync is reserved
// for the bounded loopback farewell while live events keep using fetch.
import { spawnSync } from "node:child_process"
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

The measured extent of these restrictions, and the routes that would remove the manual step, are in `docs/15-build-configuration-parity.md`. That document also records a second sandbox limit this section does not cover: the App Store build cannot see the process table at all, so it cannot link a running agent to the application hosting it.

The App Store build's App Sandbox does not permit writing to `~/.claude` or `~/.codex`, and it has no user-selected-file entitlement or file-picker flow. It therefore shows each hook or plugin as a copyable snippet for manual installation. The Direct build has no sandbox restriction on the home directory and may write directly once the user consents in-app; if the user declines, it also leaves the snippet available for manual installation.

## Privacy

NotchFlow stores no prompt content, no code, and no transcript from any agent. Only the state enum, the short `detail` label, and the optional `toolName` cross the process boundary — never the arguments passed to a tool, the diff produced by an edit, or any excerpt of the agent's reasoning. This is deliberate: the notch is a status indicator, not a monitoring surface, and the IPC envelope's schema physically has no field wide enough to carry more than a one-line label.

## Agents not in V1

Claude Desktop, ChatGPT desktop, Cursor, Copilot, and Gemini CLI expose no public status hook as of V1 and are therefore not integrated. Each is revisited in `13-deferred-backlog.md` if and when a public extension point appears.
