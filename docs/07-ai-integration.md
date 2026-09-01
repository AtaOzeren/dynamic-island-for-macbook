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
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, subprocess, sys, urllib.parse, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v2 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(session, state, detail, tool_name=None):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# The loopback socket first: it reaches a running island in a few\n# milliseconds. `open` is the fallback rather than the default because it\n# is an order of magnitude slower per event -- but it is also the only one\n# that can launch NotchFlow when it is not running.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n            return\n    except Exception:\n        pass\n    subprocess.Popen(\n        [\n            \"open\",\n            \"-g\",\n            \"notchflow://ai-status?payload=\" + urllib.parse.quote(body, safe=\"\"),\n        ],\n        start_new_session=True,\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n    )\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"waitingForUser\",\n        \"Needs attention\",\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "PostToolUse" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, subprocess, sys, urllib.parse, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v2 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(session, state, detail, tool_name=None):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# The loopback socket first: it reaches a running island in a few\n# milliseconds. `open` is the fallback rather than the default because it\n# is an order of magnitude slower per event -- but it is also the only one\n# that can launch NotchFlow when it is not running.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n            return\n    except Exception:\n        pass\n    subprocess.Popen(\n        [\n            \"open\",\n            \"-g\",\n            \"notchflow://ai-status?payload=\" + urllib.parse.quote(body, safe=\"\"),\n        ],\n        start_new_session=True,\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n    )\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"working\",\n        \"Tool completed\",\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "PreToolUse" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, subprocess, sys, urllib.parse, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v2 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(session, state, detail, tool_name=None):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# The loopback socket first: it reaches a running island in a few\n# milliseconds. `open` is the fallback rather than the default because it\n# is an order of magnitude slower per event -- but it is also the only one\n# that can launch NotchFlow when it is not running.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n            return\n    except Exception:\n        pass\n    subprocess.Popen(\n        [\n            \"open\",\n            \"-g\",\n            \"notchflow://ai-status?payload=\" + urllib.parse.quote(body, safe=\"\"),\n        ],\n        start_new_session=True,\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n    )\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"usingTool\",\n        \"Using tool\",\n        notchflow_tool_name(event),\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "SessionEnd" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, subprocess, sys, urllib.parse, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v2 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(session, state, detail, tool_name=None):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# The loopback socket first: it reaches a running island in a few\n# milliseconds. `open` is the fallback rather than the default because it\n# is an order of magnitude slower per event -- but it is also the only one\n# that can launch NotchFlow when it is not running.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n            return\n    except Exception:\n        pass\n    subprocess.Popen(\n        [\n            \"open\",\n            \"-g\",\n            \"notchflow://ai-status?payload=\" + urllib.parse.quote(body, safe=\"\"),\n        ],\n        start_new_session=True,\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n    )\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"idle\",\n        \"Session ended\",\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "Stop" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, subprocess, sys, urllib.parse, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v2 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(session, state, detail, tool_name=None):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# The loopback socket first: it reaches a running island in a few\n# milliseconds. `open` is the fallback rather than the default because it\n# is an order of magnitude slower per event -- but it is also the only one\n# that can launch NotchFlow when it is not running.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n            return\n    except Exception:\n        pass\n    subprocess.Popen(\n        [\n            \"open\",\n            \"-g\",\n            \"notchflow://ai-status?payload=\" + urllib.parse.quote(body, safe=\"\"),\n        ],\n        start_new_session=True,\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n    )\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"completed\",\n        \"Task completed\",\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
            "type" : "command"
          }
        ]
      }
    ],
    "UserPromptSubmit" : [
      {
        "hooks" : [
          {
            "command" : "NOTCHFLOW_PY=\"\"\nfor c in /opt/homebrew/bin/python3 /usr/local/bin/python3 \"$(command -v python3 2>/dev/null)\"; do\ncase \"$c\" in \"\"|/usr/bin/python3) continue;; esac\n[ -x \"$c\" ] && NOTCHFLOW_PY=\"$c\" && break\ndone\n[ -n \"$NOTCHFLOW_PY\" ] || { [ -d \"$(xcode-select -p 2>/dev/null)\" ] && NOTCHFLOW_PY=/usr/bin/python3; }\n[ -n \"$NOTCHFLOW_PY\" ] || exit 0\nEVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c 'import datetime, json, os, subprocess, sys, urllib.parse, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"claude-code\"\nnotchflow_hook_v2 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(session, state, detail, tool_name=None):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# The loopback socket first: it reaches a running island in a few\n# milliseconds. `open` is the fallback rather than the default because it\n# is an order of magnitude slower per event -- but it is also the only one\n# that can launch NotchFlow when it is not running.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n            return\n    except Exception:\n        pass\n    subprocess.Popen(\n        [\n            \"open\",\n            \"-g\",\n            \"notchflow://ai-status?payload=\" + urllib.parse.quote(body, safe=\"\"),\n        ],\n        start_new_session=True,\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n    )\n\nevent = notchflow_load(\"\")\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"session_id\")),\n        \"thinking\",\n        \"Task started\",\n        None,\n    )\n)'; } >/dev/null 2>&1 &",
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
notify = ["/usr/bin/python3","-c","import datetime, json, os, subprocess, sys, urllib.parse, urllib.request, uuid\n\nNOTCHFLOW_AGENT = \"codex\"\nnotchflow_hook_v2 = True\n\n# A CLI launched by OpenCode reports as OpenCode, not as itself: the user\n# started one agent and expects one icon. OpenCode marks every child it\n# spawns, so the check is on the environment rather than on a process walk.\nif os.environ.get(\"OPENCODE\") or os.environ.get(\"OPENCODE_PID\"):\n    sys.exit(0)\n\n\ndef notchflow_load(raw):\n    try:\n        return json.loads(raw) if raw else json.load(sys.stdin)\n    except Exception:\n        sys.exit(0)\n\n\ndef notchflow_session(raw_session):\n    if not raw_session:\n        sys.exit(0)\n    return str(\n        uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + \":\" + str(raw_session))\n    )\n\n\ndef notchflow_payload(session, state, detail, tool_name=None):\n    payload = {\n        \"schemaVersion\": \"1.0\",\n        \"agentId\": NOTCHFLOW_AGENT,\n        \"sessionId\": session,\n        \"state\": state,\n        \"detail\": detail,\n        \"timestamp\": datetime.datetime.now(datetime.timezone.utc)\n        .isoformat(timespec=\"milliseconds\")\n        .replace(\"+00:00\", \"Z\"),\n    }\n    if state == \"usingTool\" and tool_name:\n        payload[\"toolName\"] = tool_name\n    return json.dumps(payload, separators=(\",\", \":\"))\n\n\ndef notchflow_tool_name(event):\n    raw = str(event.get(\"tool_name\") or \"\")\n    cleaned = \"\".join(c for c in raw if c.isalnum() or c in \" ._-\")[:80]\n    return cleaned or None\n\n\n# The loopback socket first: it reaches a running island in a few\n# milliseconds. `open` is the fallback rather than the default because it\n# is an order of magnitude slower per event -- but it is also the only one\n# that can launch NotchFlow when it is not running.\ndef notchflow_send(body):\n    try:\n        port = open(os.path.expanduser(\"~/Library/Application Support/NotchFlow/ipc-port\")).read().strip()\n        if port:\n            urllib.request.urlopen(\n                urllib.request.Request(\n                    \"http://127.0.0.1:\" + port + \"/ai-status\",\n                    data=body.encode(\"utf-8\"),\n                    headers={\"Content-Type\": \"application/json\"},\n                ),\n                timeout=2,\n            )\n            return\n    except Exception:\n        pass\n    subprocess.Popen(\n        [\n            \"open\",\n            \"-g\",\n            \"notchflow://ai-status?payload=\" + urllib.parse.quote(body, safe=\"\"),\n        ],\n        start_new_session=True,\n        stdin=subprocess.DEVNULL,\n        stdout=subprocess.DEVNULL,\n        stderr=subprocess.DEVNULL,\n    )\n\nnotchflow_codex_notify_v3 = True\nforward = json.loads(\"[]\")\nevent_args = sys.argv[1:]\nforward and subprocess.Popen(\n    forward + event_args,\n    start_new_session=True,\n    stdin=subprocess.DEVNULL,\n    stdout=subprocess.DEVNULL,\n    stderr=subprocess.DEVNULL,\n)\nif not event_args:\n    sys.exit(0)\nevent = notchflow_load(event_args[0])\nnotchflow_send(\n    notchflow_payload(\n        notchflow_session(event.get(\"thread-id\") or event.get(\"thread_id\")),\n        \"completed\",\n        \"Turn completed\",\n    )\n)"]
```

### OpenCode

OpenCode uses a plugin file convention: a plugin file placed in OpenCode's plugin directory observes session lifecycle events and can act on them directly. NotchFlow's installer writes a small TypeScript plugin that maps those events onto the same IPC envelope and sends it via the URL scheme, the same way the Claude Code and Codex snippets do: `session.created` becomes `thinking`, `session.idle` becomes `completed`, `session.error` becomes `error`, `tool.execute.before` becomes `usingTool`, and `tool.execute.after` becomes `working`. The plugin derives a stable session UUID from the session id and dispatches each message as a detached `open -g` call, so it never blocks OpenCode's own execution.

The literal plugin file the installer writes, exactly as `HookSnippetGenerator` emits it:

<!-- notchflow-snippet: opencode -->
```ts
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
