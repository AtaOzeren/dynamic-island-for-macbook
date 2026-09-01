import Foundation

public struct HookSnippetGenerator: Sendable {
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
        let lifecycle: [(event: String, state: String, detail: String)] = [
            ("SessionStart", "thinking", "Session started"),
            ("UserPromptSubmit", "working", "Working"),
            ("PreToolUse", "usingTool", "Using tool"),
            ("PostToolUse", "working", "Tool completed"),
            ("Notification", "waitingForUser", "Needs attention"),
            ("Stop", "completed", "Task completed"),
            ("StopFailure", "error", "Task failed"),
            ("SessionEnd", "idle", "Session ended"),
        ]
        let hooks = Dictionary(uniqueKeysWithValues: lifecycle.map { event in
            let command = Self.shellCommand(
                eventExpression: #"event=json.loads(sys.argv[1]); raw_session=event["session_id"]"#,
                agentID: "claude-code",
                state: event.state,
                detail: event.detail
            )
            return (
                event.event,
                [
                    [
                        "hooks": [
                            [
                                "type": "command",
                                "command": "EVENT=$(cat); \(command) &",
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
        let forwardedJSON = Self.jsonLiteral(existingArguments)
        let forwardedBase64 = Data(forwardedJSON.utf8).base64EncodedString()
        let script =
            #"import datetime,json,subprocess,sys,urllib.parse,uuid; "#
            + #"notchflow_codex_notify_v2=True; "#
            + #"notchflow_forward_b64='"# + forwardedBase64 + #"'; "#
            + #"forward="# + forwardedJSON + #"; event_args=sys.argv[1:]; "#
            + #"event_json=event_args[0]; event=json.loads(event_json); "#
            + #"raw_session=event["thread-id"]; "#
            + #"session=str(uuid.uuid5(uuid.NAMESPACE_URL,"codex:"+raw_session)); "#
            + #"payload={"schemaVersion":"1.0","agentId":"codex","sessionId":session,"#
            + #""state":"completed","detail":"Turn completed","timestamp":"#
            + #"datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds")"#
            + #".replace("+00:00","Z")}; "#
            + #"url="notchflow://ai-status?payload="+urllib.parse.quote("#
            + #"json.dumps(payload,separators=(",",":")),safe=""); "#
            + #"forward and subprocess.Popen(forward+event_args,start_new_session=True,"#
            + #"stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); "#
            + #"subprocess.Popen(["open","-g",url],start_new_session=True,"#
            + #"stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"#
        return "notify = \(Self.jsonLiteral(["python3", "-c", script]))\n"
    }

    public func codexLifecycleHooksFragment() -> String {
        let events = [
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "PermissionRequest",
            "Stop",
        ]
        let handler: [String: Any] = [
            "type": "command",
            "command": Self.codexLifecycleHookCommand(),
            "async": true,
            "timeout": 5,
        ]
        let hooks = Dictionary(uniqueKeysWithValues: events.map { event in
            (event, [["hooks": [handler]]])
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
        """
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

        """
    }

    private static func shellCommand(
        eventExpression: String,
        agentID: String,
        state: String,
        detail: String,
        inputExpression: String = #"$EVENT"#
    ) -> String {
        let python =
            #"import json,sys,urllib.parse,uuid; "#
            + eventExpression
            + "; session=str(uuid.uuid5(uuid.NAMESPACE_URL,\"\(agentID):\"+raw_session))"
            + #"; payload={"schemaVersion":"1.0","agentId":""# + agentID
            + #"","sessionId":session,"state":""# + state
            + #"","detail":""# + detail
            + #"","timestamp":__import__("datetime").datetime.now("#
            + #"__import__("datetime").timezone.utc).isoformat(timespec="milliseconds")"#
            + #".replace("+00:00","Z")}; print("notchflow://ai-status?payload=""#
            + #"+urllib.parse.quote(json.dumps(payload,separators=(",",":")),"#
            + #"safe=""))"#
        return #"URL=$(python3 -c '"# + python + #"' "# + inputExpression + #"); [ -n "$URL" ] && open -g "$URL""#
    }

    private static func codexLifecycleHookCommand() -> String {
        let script =
            #"import datetime,json,subprocess,sys,urllib.parse,uuid; "#
            + #"notchflow_codex_hook_v1=True; "#
            + #"event=json.load(sys.stdin); raw_session=str(event["session_id"]); "#
            + #"session=str(uuid.uuid5(uuid.NAMESPACE_URL,"codex:"+raw_session)); "#
            + #"states={"UserPromptSubmit":("thinking","Task started"),"#
            + #""PreToolUse":("usingTool","Using tool"),"#
            + #""PostToolUse":("working","Working"),"#
            + #""PermissionRequest":("waitingForUser","Needs attention"),"#
            + #""Stop":("completed","Task completed")}; "#
            + #"state,detail=states[event["hook_event_name"]]; "#
            + #"payload={"schemaVersion":"1.0","agentId":"codex","sessionId":session,"#
            + #""state":state,"detail":detail,"timestamp":"#
            + #"datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds")"#
            + #".replace("+00:00","Z")}; "#
            + #"tool="".join(c for c in str(event.get("tool_name","Tool")) "#
            + #"if c.isalnum() or c in " ._-")[:80] or "Tool"; "#
            + #"event["hook_event_name"]=="PreToolUse" and payload.update({"toolName":tool}); "#
            + #"url="notchflow://ai-status?payload="+urllib.parse.quote("#
            + #"json.dumps(payload,separators=(",",":")),safe=""); "#
            + #"subprocess.Popen(["open","-g",url],start_new_session=True,"#
            + #"stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)"#
        return "/usr/bin/python3 -c \(shellSingleQuoted(script))"
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
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
