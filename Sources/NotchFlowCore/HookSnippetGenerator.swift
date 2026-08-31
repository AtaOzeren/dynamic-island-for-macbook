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
        let command = Self.shellCommand(
            eventExpression: #"event=json.loads(sys.argv[1]); raw_session=event["session_id"]"#,
            agentID: "claude-code",
            state: "usingTool",
            detail: "Using tool"
        )
        let fragment: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "hooks": [
                            [
                                "type": "command",
                                "command": "EVENT=$(cat); \(command) &",
                            ]
                        ]
                    ]
                ]
            ]
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

    public func codexNotifyFragment() -> String {
        let script = Self.shellCommand(
            eventExpression: #"event=json.loads(sys.argv[1]); raw_session=event["thread-id"]"#,
            agentID: "codex",
            state: "completed",
            detail: "Turn completed",
            inputExpression: #"$1"#
        )
        return "notify = \(Self.jsonLiteral(["sh", "-c", script, "sh"]))\n"
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

    private static func jsonLiteral<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            preconditionFailure("Hook snippets only encode strings and string arrays")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
