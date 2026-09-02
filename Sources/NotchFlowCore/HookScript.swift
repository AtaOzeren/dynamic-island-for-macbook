import Foundation

/// The Python the generated hooks run, and the shell wrappers that invoke it.
///
/// Split from `HookSnippetGenerator` because the two answer different
/// questions: this is *what the hook does*, the generator is *what file the
/// hook lives in*. Keeping the script text here also stops one long embedded
/// program from dominating the type that assembles JSON and TOML around it.
enum HookScript {

    /// Where the running island publishes its loopback port.
    ///
    /// Expressed here rather than imported from `LoopbackHTTPListenerConfiguration`
    /// because the hook is a text artefact that outlives any one build: the path
    /// has to be literal inside the generated script.
    static let discoveryFilePath = "~/Library/Application Support/NotchFlow/ipc-port"

    /// The functions every generated hook shares.
    ///
    /// Written as real multi-line Python rather than a `;`-joined one-liner
    /// because `try`/`except` is a compound statement and cannot appear in a
    /// simple-statement list. JSON and TOML both carry the newlines, and a shell
    /// single-quoted string preserves them — so the script stays one `-c`
    /// argument with no quoting of its own to get wrong.
    ///
    /// Contains no apostrophe anywhere, which is what lets the whole body sit
    /// inside `'…'` in a shell command without escaping.
    /// The agent's own identifier, substituted into `preambleTemplate`.
    private static let agentPlaceholder = "__NOTCHFLOW_AGENT_ID__"

    static func pythonPreamble(agentID: String) -> String {
        preambleTemplate.replacingOccurrences(of: agentPlaceholder, with: agentID)
    }

    /// Stored rather than built inside the function so the embedded program is
    /// a constant, not a hundred-line function body.
    private static let preambleTemplate = """
        import datetime, json, os, subprocess, sys, urllib.parse, urllib.request, uuid

        NOTCHFLOW_AGENT = "\(agentPlaceholder)"
        \(HookSnippetGenerator.managedHookMarker) = True

        # A CLI launched by OpenCode reports as OpenCode, not as itself: the user
        # started one agent and expects one icon. OpenCode marks every child it
        # spawns, so the check is on the environment rather than on a process walk.
        if os.environ.get("OPENCODE") or os.environ.get("OPENCODE_PID"):
            sys.exit(0)


        def notchflow_load(raw):
            try:
                return json.loads(raw) if raw else json.load(sys.stdin)
            except Exception:
                sys.exit(0)


        def notchflow_session(raw_session):
            if not raw_session:
                sys.exit(0)
            return str(
                uuid.uuid5(uuid.NAMESPACE_URL, NOTCHFLOW_AGENT + ":" + str(raw_session))
            )


        def notchflow_payload(
            session,
            state,
            detail,
            tool_name=None,
            root_session=None,
            session_name=None,
            workspace=None,
        ):
            payload = {
                "schemaVersion": "1.0",
                "agentId": NOTCHFLOW_AGENT,
                "sessionId": session,
                "state": state,
                "detail": detail,
                "timestamp": datetime.datetime.now(datetime.timezone.utc)
                .isoformat(timespec="milliseconds")
                .replace("+00:00", "Z"),
            }
            if state == "usingTool" and tool_name:
                payload["toolName"] = tool_name
            if root_session:
                payload["rootSessionId"] = root_session
            if session_name:
                payload["sessionName"] = session_name
            if workspace:
                payload["workspace"] = workspace
            return json.dumps(payload, separators=(",", ":"))


        def notchflow_tool_name(event):
            raw = str(event.get("tool_name") or "")
            cleaned = "".join(c for c in raw if c.isalnum() or c in " ._-")[:80]
            return cleaned or None


        # The loopback socket first: it reaches a running island in a few
        # milliseconds. `open` is the fallback rather than the default because it
        # is an order of magnitude slower per event -- but it is also the only one
        # that can launch NotchFlow when it is not running.
        def notchflow_send(body):
            try:
                port = open(os.path.expanduser("\(discoveryFilePath)")).read().strip()
                if port:
                    urllib.request.urlopen(
                        urllib.request.Request(
                            "http://127.0.0.1:" + port + "/ai-status",
                            data=body.encode("utf-8"),
                            headers={"Content-Type": "application/json"},
                        ),
                        timeout=2,
                    )
                    return
            except Exception:
                pass
            subprocess.Popen(
                [
                    "open",
                    "-g",
                    "notchflow://ai-status?payload=" + urllib.parse.quote(body, safe=""),
                ],
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )


        """

    /// Claude Code delivers the event as JSON on stdin.
    ///
    /// The JSON is read by the script itself rather than interpolated into the
    /// command line. An earlier form passed it as an unquoted shell word, which
    /// word-split every event carrying a space — a submitted prompt, a path with
    /// a space — and silently dropped it under `sh` and `bash`.
    static func claudeCodeHookCommand(
        state: String,
        detail: String,
        carriesToolName: Bool,
        carriesSubagentIdentity: Bool
    ) -> String {
        let toolExpression = carriesToolName ? "notchflow_tool_name(event)" : "None"
        let sessionExpression = carriesSubagentIdentity
            ? "notchflow_session(event.get(\"agent_id\"))"
            : "notchflow_session(event.get(\"session_id\"))"
        let rootSessionExpression = carriesSubagentIdentity
            ? "notchflow_session(event.get(\"session_id\"))"
            : "None"
        let sessionNameExpression = carriesSubagentIdentity
            ? "event.get(\"agent_type\")"
            : "None"
        let script =
            pythonPreamble(agentID: "claude-code")
            + """
            event = notchflow_load("")
            notchflow_send(
                notchflow_payload(
                    \(sessionExpression),
                    \(HookTextEncoding.pythonStringLiteral(state)),
                    \(HookTextEncoding.pythonStringLiteral(detail)),
                    \(toolExpression),
                    \(rootSessionExpression),
                    \(sessionNameExpression),
                    event.get("cwd"),
                )
            )
            """
        // Backgrounded as a whole so no hook ever adds its own latency to a tool
        // call. Reading stdin happens first, in the foreground, because the pipe
        // Claude Code opened is closed as soon as the hook process returns.
        return interpreterResolution
            + "EVENT=$(cat); { printf %s \"$EVENT\" | \"$NOTCHFLOW_PY\" -c "
            + HookTextEncoding.shellSingleQuoted(script)
            + "; } >/dev/null 2>&1 &"
    }

    /// Shell that picks a Python and leaves it in `$NOTCHFLOW_PY`, or exits.
    ///
    /// `/usr/bin/python3` is not an interpreter — it is a stub that forwards to
    /// the one inside Xcode. On a Mac with no developer tools installed, running
    /// it pops the "install command line developer tools" panel and the hook
    /// fails, so it is tried last and only once `xcode-select` confirms there is
    /// something behind it. Finding nothing at all exits quietly: a missing
    /// interpreter should cost the user a missing island, not a system dialog on
    /// every keystroke.
    private static let interpreterResolution = """
        NOTCHFLOW_PY=""
        for c in /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3 2>/dev/null)"; do
        case "$c" in ""|/usr/bin/python3) continue;; esac
        [ -x "$c" ] && NOTCHFLOW_PY="$c" && break
        done
        [ -n "$NOTCHFLOW_PY" ] || { [ -d "$(xcode-select -p 2>/dev/null)" ] && NOTCHFLOW_PY=/usr/bin/python3; }
        [ -n "$NOTCHFLOW_PY" ] || exit 0

        """

    static func codexLifecycleHookCommand() -> String {
        let states = HookSnippetGenerator.codexLifecycleEvents
            .map { event in
                "    \(HookTextEncoding.pythonStringLiteral(event.event)): ("
                    + "\(HookTextEncoding.pythonStringLiteral(event.state)), "
                    + "\(HookTextEncoding.pythonStringLiteral(event.detail)), "
                    + "\(event.carriesToolName ? "True" : "False"))"
            }
            .joined(separator: ",\n")
        let script =
            pythonPreamble(agentID: "codex")
            + """
            \(HookSnippetGenerator.codexLifecycleHookMarker) = True

            STATES = {
            \(states),
            }

            event = notchflow_load("")
            resolved = STATES.get(str(event.get("hook_event_name")))
            if resolved is None:
                sys.exit(0)
            state, detail, carries_tool_name = resolved
            notchflow_send(
                notchflow_payload(
                    notchflow_session(event.get("session_id")),
                    state,
                    detail,
                    notchflow_tool_name(event) if carries_tool_name else None,
                    workspace=event.get("cwd"),
                )
            )
            """
        return interpreterResolution
            + "\"$NOTCHFLOW_PY\" -c \(HookTextEncoding.shellSingleQuoted(script))"
    }
}
