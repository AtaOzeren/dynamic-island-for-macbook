import Foundation
import Testing

@testable import NotchFlowCore

@Suite("HookGeneration")
struct HookGenerationTests {
    @Test("generated agent hooks never launch NotchFlow")
    func generatedHooksUseLoopbackOnly() {
        let generator = HookSnippetGenerator()
        let generatedHooks = [
            generator.claudeCodeSettingsFragment(),
            generator.codexNotifyFragment(),
            generator.codexLifecycleHooksFragment(),
            generator.openCodePluginFile(),
        ]

        for hook in generatedHooks {
            #expect(!hook.contains(#"["open", "-g""#))
            #expect(!hook.contains(#"spawn("open""#))
            #expect(!hook.contains(#"spawnSync("open""#))
            #expect(!hook.contains("notchflow://ai-status"))
        }
    }

    @Test("generated hook markers identify loopback-only generations")
    func generatedHookMarkersAreCurrent() {
        #expect(HookSnippetGenerator.managedHookMarker == "notchflow_hook_v4")
        #expect(
            HookSnippetGenerator.previousManagedHookMarkers == [
                "notchflow_hook_v2",
                "notchflow_hook_v3",
            ]
        )
        #expect(HookSnippetGenerator.codexNotifyMarker == "notchflow_codex_notify_v4")
        #expect(HookSnippetGenerator.codexLifecycleHookMarker == "notchflow_codex_hook_v3")
    }

    @Test("generates Claude Code lifecycle hooks using stdin event fields")
    func claudeCodeSettingsFragment() throws {
        let fragment = HookSnippetGenerator().claudeCodeSettingsFragment()
        let settings = try #require(
            JSONSerialization.jsonObject(with: Data(fragment.utf8)) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        #expect(
            Set(hooks.keys) == [
                "UserPromptSubmit",
                "PreToolUse",
                "PostToolUse",
                "Notification",
                "Stop",
                "StopFailure",
                "SessionEnd",
                "SubagentStart",
                "SubagentStop",
            ]
        )
        let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        let hookGroup = try #require(preToolUse.first)
        let commands = try #require(hookGroup["hooks"] as? [[String: String]])
        let command = try #require(commands.first)

        #expect(command["type"] == "command")
        #expect(command["command"]?.contains("EVENT=$(cat)") == true)
        #expect(command["command"]?.contains("session_id") == true)
        #expect(command["command"]?.contains("uuid.uuid5") == true)
        #expect(command["command"]?.contains("CLAUDE_SESSION_ID") == false)

        #expect(try hookCommand(for: "Stop", in: hooks).contains(#""completed""#))
        #expect(try hookCommand(for: "SessionEnd", in: hooks).contains(#""idle""#))
    }

    @Test("Claude Code subagent hooks derive child hierarchy from documented fields")
    func claudeCodeSubagentHierarchy() throws {
        for (eventName, expectedState) in [
            ("SubagentStart", "working"),
            ("SubagentStop", "completed"),
        ] {
            let hooks = try Self.claudeCodeHooks()
            let command = try hookCommand(for: eventName, in: hooks)
            let payload = try Self.runHook(
                command: command,
                input: [
                    "session_id": "abc123",
                    "transcript_path": "/tmp/abc123.jsonl",
                    "cwd": "/tmp/project",
                    "hook_event_name": eventName,
                    "agent_id": "agent-def456",
                    "agent_type": "Explore",
                ]
            )

            #expect(payload["agentId"] as? String == "claude-code")
            #expect(payload["sessionId"] as? String == "90e7a3ad-2eb1-58c6-a687-ed845e8a8cfb")
            #expect(payload["rootSessionId"] as? String == "2eb063bd-b9ac-5e7a-aaae-e7c220a61388")
            #expect(payload["sessionName"] as? String == "Explore")
            #expect(payload["state"] as? String == expectedState)
        }
    }

    @Test("generates a direct Codex Python notify fragment")
    func codexNotifyFragment() throws {
        let fragment = HookSnippetGenerator().codexNotifyFragment()
        let assignmentPrefix = "notify = "

        #expect(fragment.hasPrefix(assignmentPrefix))

        let encodedArguments = fragment.dropFirst(assignmentPrefix.count)
        let arguments = try #require(
            JSONSerialization.jsonObject(with: Data(encodedArguments.utf8)) as? [String]
        )

        #expect(arguments.count == 3)
        #expect(arguments[0] == "/usr/bin/python3")
        #expect(arguments[1] == "-c")
        #expect(arguments[2].contains("sys.argv[1:]"))
        #expect(arguments[2].contains("thread-id"))
        #expect(arguments[2].contains("uuid.uuid5"))
        #expect(arguments[2].contains("http://127.0.0.1:"))
    }

    @Test("Codex notify forwards events to an existing notifier")
    func codexNotifyForwardsExistingNotifier() throws {
        let existing = ["/Applications/Notifier.app/Contents/MacOS/Notifier", "turn-ended"]
        let fragment = HookSnippetGenerator().codexNotifyFragment(forwarding: existing)
        let arguments = try #require(
            JSONSerialization.jsonObject(
                with: Data(fragment.dropFirst("notify = ".count).utf8)
            ) as? [String]
        )

        #expect(arguments[2].contains(existing[0]))
        #expect(arguments[2].contains(existing[1]))
        #expect(arguments[2].contains("forward + event_args"))
    }

    @Test("generates Codex lifecycle hooks for visible task states")
    func codexLifecycleHooksFragment() throws {
        let fragment = HookSnippetGenerator().codexLifecycleHooksFragment()
        let document = try #require(
            JSONSerialization.jsonObject(with: Data(fragment.utf8)) as? [String: Any]
        )
        let hooks = try #require(document["hooks"] as? [String: Any])

        #expect(
            Set(hooks.keys) == [
                "UserPromptSubmit",
                "PreToolUse",
                "PostToolUse",
                "PermissionRequest",
                "Stop",
                "SessionEnd",
            ]
        )

        for event in hooks.keys {
            let groups = try #require(hooks[event] as? [[String: Any]])
            let group = try #require(groups.first)
            let handlers = try #require(group["hooks"] as? [[String: Any]])
            let handler = try #require(handlers.first)
            let command = try #require(handler["command"] as? String)

            #expect(handler["type"] as? String == "command")
            #expect(handler["async"] as? Bool == true)
            #expect(command.contains(HookSnippetGenerator.codexLifecycleHookMarker))
            #expect(command.contains("hook_event_name"))
            #expect(command.contains("session_id"))
            #expect(command.contains("uuid.uuid5"))
        #expect(command.contains("http://127.0.0.1:"))
        }

        let promptCommand = try hookCommand(for: "UserPromptSubmit", in: hooks)
        #expect(promptCommand.contains(#""UserPromptSubmit": ("thinking", "Task started""#))
        #expect(promptCommand.contains(#""PermissionRequest": ("waitingForUser", "Needs attention""#))
        #expect(promptCommand.contains(#""Stop": ("completed", "Task completed""#))
        #expect(promptCommand.contains(#""SessionEnd": ("idle", "Session ended""#))
    }

    @Test("generates an OpenCode plugin that posts to loopback")
    func openCodePluginFile() {
        let plugin = HookSnippetGenerator().openCodePluginFile()

        #expect(plugin.contains(#"import type { Plugin } from "@opencode-ai/plugin""#))
        #expect(plugin.contains(#"fetch(`http://127.0.0.1:${port}/ai-status`"#))
        #expect(plugin.contains(#"agentId: "opencode""#))
        #expect(!plugin.contains(#"encodeURIComponent(body)"#))
        #expect(plugin.contains("/ai-status"))
        #expect(plugin.contains(#"createHash("sha256")"#))
        #expect(plugin.contains(#""tool.execute.before": async"#))
        #expect(plugin.contains(#""tool.execute.after": async"#))
        #expect(plugin.contains(#""session.idle""#))
        // Deliberately absent: opencode fires `session.error` after perfectly
        // normal completions too, so mapping it straight to red painted
        // finished work as failed. The failure now comes from the last
        // message's own error, which is the only source that distinguishes them.
        #expect(!plugin.contains(#"case "session.error""#))
        #expect(plugin.contains(#""chat.message": async"#))
        #expect(plugin.contains(#""permission.asked""#))
    }

    /// `session.idle` means the session stopped, not that it succeeded. A turn
    /// that died on a rate limit goes idle exactly like one that finished, and
    /// opencode emits no event for the failure itself, so the only way to tell
    /// them apart is to ask what the last message says.
    @Test("the OpenCode plugin verifies the outcome before claiming success")
    func openCodePluginVerifiesItsOutcome() {
        let plugin = HookSnippetGenerator().openCodePluginFile()

        #expect(plugin.contains("const lastAssistantError"))
        #expect(plugin.contains("client.session.messages("))
        #expect(plugin.contains(#"await notify("error", sessionId, "Task failed""#))
    }

    /// An aborted turn is neither a success nor a failure: something stopped it
    /// on purpose. It is also by far the most common stored error — painting
    /// those red would turn a cancel loop into a wall of alarm.
    @Test("the OpenCode plugin does not treat an abort as a failure")
    func openCodePluginIgnoresAborts() {
        let plugin = HookSnippetGenerator().openCodePluginFile()

        #expect(plugin.contains("MessageAbortedError"))
        #expect(plugin.contains(#"if (error.name === "MessageAbortedError") return null"#))
    }

    /// The cause is classified into the island's own closed vocabulary rather
    /// than passed through: the validator rejects the punctuation provider
    /// errors are full of, so a raw message would drop the whole envelope.
    @Test("the OpenCode plugin names causes from a closed vocabulary")
    func openCodePluginClassifiesCauses() {
        let plugin = HookSnippetGenerator().openCodePluginFile()

        for status in ["401", "402", "403", "429", "529"] {
            #expect(plugin.contains(status), "status \(status) is unclassified")
        }
        for reason in AIAgentFailureReason.allCases where reason != .unknown {
            #expect(plugin.contains(reason.rawValue), "\(reason.rawValue) is never sent")
        }
    }

    /// Claude Code names the cause in a closed set of its own, and every one of
    /// its members has to land somewhere in ours — an unmapped name would reach
    /// the island as an unexplained failure.
    @Test("every Claude Code failure name maps to a reason")
    func claudeCodeFailureNamesAreMapped() throws {
        let hooks = try Self.claudeCodeHooks()
        let command = try hookCommand(for: "StopFailure", in: hooks)

        for name in [
            "rate_limit", "account_on_hold", "billing_error",
            "authentication_failed", "oauth_org_not_allowed",
            "overloaded", "server_error",
            "invalid_request", "model_not_found", "max_output_tokens",
        ] {
            #expect(command.contains(name), "\(name) is unmapped")
        }
        #expect(command.contains(#""error""#))
        #expect(command.contains("notchflow_reason(event)"))
    }

    /// Quitting opencode is neither the end of a turn nor the deletion of a
    /// session, so nothing else reports it: the last state sat on the island for
    /// its whole silence timeout while the process behind it was gone. Saying so
    /// on the way out is the only message that can.
    @Test("the OpenCode plugin delivers exit notifications over loopback")
    func openCodePluginDeliversGoodbyeOverLoopback() {
        let plugin = HookSnippetGenerator().openCodePluginFile()

        #expect(plugin.contains(#"process.on("exit", sayGoodbye)"#))
        #expect(plugin.contains(#"spawnSync("/usr/bin/curl""#), "an exit handler cannot await a fetch")
        #expect(plugin.contains("deliverBeforeExit(envelope("))
        #expect(plugin.contains(#"envelope("idle""#))
    }

    /// Registering a SIGINT or SIGTERM listener suppresses Node's default
    /// termination. An agent that no longer quits on Ctrl-C is a far worse
    /// defect than a card that lingers, and the silence timeout already covers
    /// the signals this handler skips.
    @Test("the OpenCode plugin never intercepts termination signals")
    func openCodePluginLeavesSignalsAlone() {
        let plugin = HookSnippetGenerator().openCodePluginFile()

        // Matched as a registration rather than as a word: the plugin's own
        // comment names the signals to explain why it leaves them alone.
        for registration in [#"process.on("SIG"#, #"process.once("SIG"#, #"process.addListener("SIG"#] {
            #expect(
                !plugin.contains(registration),
                "\(registration) would break quitting opencode"
            )
        }
        #expect(!plugin.contains("process.exit("))
    }

    /// The farewell is bounded: a synchronous loopback POST per session is a cost the
    /// user feels on the way out, and the island ends an instance's sub-agents
    /// with it, so only the roots need saying.
    @Test("the OpenCode plugin bounds how many farewells it sends")
    func openCodePluginBoundsItsFarewells() {
        let plugin = HookSnippetGenerator().openCodePluginFile()

        #expect(plugin.contains("MAX_FAREWELLS"))
        #expect(plugin.contains("liveRoots"))
    }

    /// The event JSON reaches Python on stdin, never as a shell word.
    ///
    /// An earlier form interpolated it unquoted into the command line. Under
    /// `sh` and `bash` that word-split every event carrying a space — a
    /// submitted prompt, a path with a space — so the hook silently delivered
    /// nothing, which on screen is indistinguishable from a broken agent.
    @Test("Claude Code hooks read the event from stdin, never from an unquoted word")
    func claudeCodeHooksNeverWordSplitTheEvent() throws {
        let hooks = try Self.claudeCodeHooks()

        for event in hooks.keys {
            let command = try hookCommand(for: event, in: hooks)

            #expect(command.contains(#"printf %s "$EVENT""#), "\(event) lost its quoting")
            #expect(!command.contains("-c ' $EVENT"), "\(event) passes the event as a word")
            #expect(command.contains("json.load(sys.stdin)"), "\(event) does not read stdin")
        }
    }

    /// A CLI that OpenCode launched reports as OpenCode. Without this the user
    /// starts one agent and the island shows two.
    @Test("Claude Code and Codex hooks stand down under OpenCode")
    func hooksSuppressThemselvesUnderOpenCode() throws {
        let hooks = try Self.claudeCodeHooks()
        let claudeCommand = try hookCommand(for: "Stop", in: hooks)

        #expect(claudeCommand.contains(#"os.environ.get("OPENCODE")"#))
        #expect(claudeCommand.contains(#"os.environ.get("OPENCODE_PID")"#))

        let codexDocument = try #require(
            JSONSerialization.jsonObject(
                with: Data(HookSnippetGenerator().codexLifecycleHooksFragment().utf8)
            ) as? [String: Any]
        )
        let codexHooks = try #require(codexDocument["hooks"] as? [String: Any])
        let codexCommand = try hookCommand(for: "Stop", in: codexHooks)

        #expect(codexCommand.contains(#"os.environ.get("OPENCODE")"#))
    }

    /// Hooks may report only to an already-running island. A URL fallback would
    /// launch NotchFlow after the user quit it, so its absence is part of the
    /// delivery contract rather than an implementation detail.
    @Test("hooks use loopback only and silently drop unavailable deliveries")
    func hooksUseLoopbackWithoutALaunchFallback() throws {
        let hooks = try Self.claudeCodeHooks()
        let command = try hookCommand(for: "Stop", in: hooks)

        #expect(command.contains("127.0.0.1"))
        #expect(command.contains("/ai-status"))
        #expect(command.contains("ipc-port"))
        #expect(command.contains("urllib.request.urlopen"))
        #expect(!command.contains("notchflow://ai-status"))
        #expect(!command.contains(#"["open", "-g""#))
    }

    /// Every hook is backgrounded, so no agent waits on the island.
    @Test("Claude Code hooks never block the agent")
    func claudeCodeHooksAreBackgrounded() throws {
        let hooks = try Self.claudeCodeHooks()

        for event in hooks.keys {
            #expect(try hookCommand(for: event, in: hooks).hasSuffix("&"))
        }
    }

    /// `StopFailure` is not an event Claude Code emits. Subscribing to it is a
    /// hook that never fires, which reads on screen exactly like a broken one.
    @Test("Claude Code hooks name only events Claude Code emits")
    func claudeCodeHooksNameRealEventsOnly() throws {
        let hooks = try Self.claudeCodeHooks()

        // `StopFailure` is the one failure signal Claude Code gives: the turn
        // ended on an API error rather than on Claude finishing. Without it a
        // rate-limited turn reported nothing at all.
        #expect(hooks["StopFailure"] != nil)
    }

    /// The tool in flight is only meaningful in `usingTool`, and only
    /// `PreToolUse` knows it.
    @Test("only the tool-use hook carries a tool name")
    func onlyPreToolUseCarriesAToolName() throws {
        let hooks = try Self.claudeCodeHooks()

        // The helper is defined in every script; what differs is whether the
        // payload call passes it or passes `None`.
        #expect(try hookCommand(for: "PreToolUse", in: hooks).contains("        notchflow_tool_name(event),"))
        #expect(try hookCommand(for: "Stop", in: hooks).contains("        None,"))
        #expect(try !hookCommand(for: "Stop", in: hooks).contains("        notchflow_tool_name(event),"))
    }

    /// The whole script sits inside a single-quoted shell word, so an
    /// apostrophe anywhere in it would end the quoting early.
    @Test("generated shell scripts contain no apostrophe")
    func generatedScriptsAreSingleQuoteSafe() throws {
        let hooks = try Self.claudeCodeHooks()

        for event in hooks.keys {
            let command = try hookCommand(for: event, in: hooks)
            let script = try #require(command.split(separator: "'").dropFirst().first)

            #expect(!script.contains("'"))
        }
    }

    /// Opening a session is not work.
    ///
    /// Subscribing to `SessionStart` put the agent on screen as "Thinking…" the
    /// moment a window opened, and `thinking` has no expiry — so an idle
    /// terminal held the island for as long as it stayed open.
    @Test("no hook fires merely because a session opened")
    func sessionOpeningIsNotAnActivity() throws {
        let hooks = try Self.claudeCodeHooks()

        #expect(hooks["SessionStart"] == nil)
        #expect(hooks["UserPromptSubmit"] != nil, "the real start must still be covered")
        #expect(hooks["SessionEnd"] != nil, "a session ending must still clear a stale card")

        // The OpenCode plugin does watch `session.created`, but only to learn
        // which session is a sub-agent of which — the branch records parentage
        // and sends nothing. A `notify` call there would be the same defect in
        // the other agent's clothing.
        let plugin = HookSnippetGenerator().openCodePluginFile()
        let sessionCreated = try #require(
            plugin.range(of: #"case "session.created":"#).map { plugin[$0.upperBound...] }
        )
        let branch = sessionCreated.prefix(while: { $0 != ";" })
            .prefix(while: { _ in true })
        let untilBreak = branch.range(of: "break").map { branch[..<$0.lowerBound] } ?? branch
        #expect(!untilBreak.contains("notify("), "opening a session must send no state")
        #expect(untilBreak.contains("remember("), "opening a session must record its parent")
        #expect(plugin.contains(#""chat.message": async"#))
    }

    /// `/usr/bin/python3` is a stub that forwards into Xcode.
    ///
    /// On a Mac with no developer tools it opens the "install command line
    /// developer tools" panel instead of running, so a hook that reached for it
    /// unconditionally would put a system dialog in front of the user on every
    /// tool call. It is tried last, and only behind an `xcode-select` check.
    @Test("hooks resolve an interpreter instead of assuming the Xcode stub")
    func hooksResolveTheirInterpreter() throws {
        let hooks = try Self.claudeCodeHooks()

        for event in hooks.keys {
            let command = try hookCommand(for: event, in: hooks)

            #expect(command.contains("NOTCHFLOW_PY"), "\(event) does not resolve an interpreter")
            #expect(command.contains("xcode-select -p"), "\(event) does not gate the stub")
            #expect(
                command.contains("| /usr/bin/python3 -c") == false,
                "\(event) still invokes the stub directly"
            )
        }

        let codexDocument = try #require(
            JSONSerialization.jsonObject(
                with: Data(HookSnippetGenerator().codexLifecycleHooksFragment().utf8)
            ) as? [String: Any]
        )
        let codexHooks = try #require(codexDocument["hooks"] as? [String: Any])
        let codexCommand = try hookCommand(for: "Stop", in: codexHooks)

        #expect(codexCommand.contains("NOTCHFLOW_PY"))
        #expect(codexCommand.hasPrefix("/usr/bin/python3") == false)
    }

    /// Finding no interpreter has to be silent. A hook that failed loudly would
    /// print on every event of every turn.
    @Test("a machine with no interpreter exits quietly")
    func missingInterpreterExitsQuietly() throws {
        let command = try hookCommand(for: "Stop", in: Self.claudeCodeHooks())

        #expect(command.contains(#"[ -n "$NOTCHFLOW_PY" ] || exit 0"#))
    }

    @Test("generation is idempotent")
    func idempotentGeneration() throws {
        let generator = HookSnippetGenerator()

        let firstClaudeFragment = generator.claudeCodeSettingsFragment()
        let firstCodexFragment = generator.codexNotifyFragment()
        let firstCodexLifecycleFragment = generator.codexLifecycleHooksFragment()
        let firstOpenCodePlugin = generator.openCodePluginFile()

        #expect(generator.claudeCodeSettingsFragment() == firstClaudeFragment)
        #expect(generator.codexNotifyFragment() == firstCodexFragment)
        #expect(generator.codexLifecycleHooksFragment() == firstCodexLifecycleFragment)
        #expect(generator.openCodePluginFile() == firstOpenCodePlugin)
    }

    private static func claudeCodeHooks() throws -> [String: Any] {
        let fragment = HookSnippetGenerator().claudeCodeSettingsFragment()
        let settings = try #require(
            JSONSerialization.jsonObject(with: Data(fragment.utf8)) as? [String: Any]
        )
        return try #require(settings["hooks"] as? [String: Any])
    }

    private static func runHook(command: String, input: [String: Any]) throws -> [String: Any] {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appending(
            path: "notchflow-claude-subagent-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let binDirectory = temporaryDirectory.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let pythonURL = binDirectory.appending(path: "python3")
        try FileManager.default.createSymbolicLink(
            at: pythonURL,
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/python3")
        )
        let payloadURL = temporaryDirectory.appending(path: "payload.json")
        let listenerURL = temporaryDirectory.appending(path: "listener.py")
        let listenerScript = """
            import http.server, pathlib, sys

            class Handler(http.server.BaseHTTPRequestHandler):
                def do_POST(self):
                    length = int(self.headers.get("Content-Length", "0"))
                    pathlib.Path(sys.argv[1]).write_bytes(self.rfile.read(length))
                    self.send_response(204)
                    self.end_headers()

                def log_message(self, format, *args):
                    pass

            server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
            print(server.server_port, flush=True)
            server.handle_request()
            """
        try Data(listenerScript.utf8).write(to: listenerURL)

        let listener = Process()
        listener.executableURL = pythonURL
        listener.arguments = [listenerURL.path, payloadURL.path]
        let listenerOutput = Pipe()
        listener.standardOutput = listenerOutput
        try listener.run()
        defer {
            if listener.isRunning { listener.terminate() }
        }

        let port = String(
            decoding: listenerOutput.fileHandleForReading.availableData,
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !port.isEmpty else {
            throw NSError(
                domain: "HookGenerationTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Stub listener did not publish a port"]
            )
        }
        let discoveryURL = temporaryDirectory.appending(
            path: "Library/Application Support/NotchFlow/ipc-port"
        )
        try FileManager.default.createDirectory(
            at: discoveryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(port.utf8).write(to: discoveryURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", String(command.dropLast())]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        let stderr = Pipe()
        process.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binDirectory.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "/bin:/usr/bin")"
        environment["HOME"] = temporaryDirectory.path
        environment.removeValue(forKey: "OPENCODE")
        environment.removeValue(forKey: "OPENCODE_PID")
        process.environment = environment

        try process.run()
        stdin.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: input))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        for _ in 0..<500 where !FileManager.default.fileExists(atPath: payloadURL.path) {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let errorOutput = String(
            decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        #expect(process.terminationStatus == 0, Comment(rawValue: errorOutput))
        guard FileManager.default.fileExists(atPath: payloadURL.path) else {
            throw NSError(
                domain: "HookGenerationTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Hook produced no payload: \(errorOutput)"]
            )
        }

        return try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: payloadURL)) as? [String: Any]
        )
    }

    private func hookCommand(
        for event: String,
        in hooks: [String: Any]
    ) throws -> String {
        let groups = try #require(hooks[event] as? [[String: Any]])
        let group = try #require(groups.first)
        let commands = try #require(group["hooks"] as? [[String: Any]])
        return try #require(commands.first?["command"] as? String)
    }
}
