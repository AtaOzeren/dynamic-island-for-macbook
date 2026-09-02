import Foundation
import Testing
@testable import NotchFlowCore

/// Parity across the three agent integrations, per the stabilization plan's
/// normalization phase: a semantic milestone — the user started a task, a tool
/// ran, the turn ended, the session ended — must reach the island as the same
/// `AIAgentActivity` state whichever agent reported it.
///
/// Two layers, because parity can break in two places:
///
/// 1. **Trigger layer** — each agent's generated integration artifact (the
///    Claude Code settings fragment, the Codex lifecycle table, the OpenCode
///    plugin source) maps its own trigger for a milestone to the agreed state.
///    Assertions read the artifacts `HookSnippetGenerator` actually emits, not
///    a copy of the tables.
/// 2. **Envelope layer** — equivalent per-agent envelopes project through
///    `AIAgentSessionLedger` and `AIAgentActivity` to identical state
///    sequences, identical admission decisions, and identical teardown
///    timing. This layer is what makes the NotchFlow side unified: whatever
///    each agent's API can or cannot express, the receiver treats it alike.
///
/// Known, accepted asymmetries are documented at their assertions rather than
/// papered over: UUID derivation differs per agent (both forms deterministic
/// and stable per session, which is the property the protocol needs) and
/// Codex does not yet wire sub-agent events its API now offers — the receiver
/// below already accepts sub-agent envelopes from any agent, so that wiring
/// later requires no NotchFlow-side change.
@Suite("Agent parity")
struct AgentParityTests {
    /// One row per semantic milestone, carrying each agent's own trigger for
    /// it and the one state (and, where the agents agree, detail) every agent
    /// must produce.
    ///
    /// `unifiedDetail` is `nil` where the agents legitimately differ in
    /// wording — the post-tool detail reads "Tool completed" for Claude Code
    /// and "Working…" for the other two — because the plan's parity target is
    /// the state sequence, not the display string.
    private struct SemanticEvent {
        let name: String
        let claudeCodeTrigger: String
        let codexTrigger: String
        let openCodeTriggerPattern: String
        let state: AIAgentState
        let unifiedDetail: String?
    }

    private static let parityTable: [SemanticEvent] = [
        SemanticEvent(
            name: "session start",
            claudeCodeTrigger: "UserPromptSubmit",
            codexTrigger: "UserPromptSubmit",
            openCodeTriggerPattern: #""chat\.message": async \(input, output\) => \{\s*await notify\(\s*"thinking""#,
            state: .thinking,
            unifiedDetail: "Task started"
        ),
        SemanticEvent(
            name: "tool call",
            claudeCodeTrigger: "PreToolUse",
            codexTrigger: "PreToolUse",
            openCodeTriggerPattern: #""tool\.execute\.before": async \(input\) => \{\s*await notify\(\s*"usingTool""#,
            state: .usingTool,
            unifiedDetail: "Using tool"
        ),
        SemanticEvent(
            name: "tool result",
            claudeCodeTrigger: "PostToolUse",
            codexTrigger: "PostToolUse",
            openCodeTriggerPattern: #""tool\.execute\.after": async \(input\) => \{\s*await notify\(\s*"working""#,
            state: .working,
            unifiedDetail: nil
        ),
        SemanticEvent(
            name: "turn end",
            claudeCodeTrigger: "Stop",
            codexTrigger: "Stop",
            openCodeTriggerPattern: #"case "session\.idle":\s*await notify\("completed""#,
            state: .completed,
            unifiedDetail: "Task completed"
        ),
        SemanticEvent(
            name: "needs attention",
            claudeCodeTrigger: "Notification",
            codexTrigger: "PermissionRequest",
            openCodeTriggerPattern: #"case "permission\.asked":\s*await notify\("waitingForUser""#,
            state: .waitingForUser,
            unifiedDetail: "Needs attention"
        ),
        SemanticEvent(
            name: "session end",
            claudeCodeTrigger: "SessionEnd",
            codexTrigger: "SessionEnd",
            openCodeTriggerPattern: #"case "session\.deleted":\s*await notify\("idle""#,
            state: .idle,
            unifiedDetail: "Session ended"
        ),
    ]

    private static let sessionByAgent: [IPCAgentID: UUID] = Dictionary(
        uniqueKeysWithValues: IPCAgentID.allCases.enumerated().map { index, agent in
            (agent, UUID(uuid: (UInt8(index), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)))
        }
    )

    @Test("every semantic milestone maps to the same state in all three agents")
    func triggersAgreeOnStates() throws {
        let generator = HookSnippetGenerator()
        let claudeCodeHooks = try Self.claudeCodeHooks(generator)
        let pluginSource = generator.openCodePluginFile()

        for row in Self.parityTable {
            let claudeCodeCommand = try Self.claudeCodeHookCommand(
                for: row.claudeCodeTrigger,
                in: claudeCodeHooks
            )
            #expect(
                claudeCodeCommand?.contains(#""\#(row.state.rawValue)""#) == true,
                "Claude Code \(row.claudeCodeTrigger) must send \(row.state.rawValue) (\(row.name))"
            )

            let codexEvent = HookSnippetGenerator.codexLifecycleEvents
                .first { $0.event == row.codexTrigger }
            #expect(
                codexEvent?.state == row.state.rawValue,
                "Codex \(row.codexTrigger) must send \(row.state.rawValue) (\(row.name))"
            )

            #expect(
                Self.pluginSource(pluginSource, matches: row.openCodeTriggerPattern),
                "OpenCode must send \(row.state.rawValue) for \(row.name)"
            )

            if let detail = row.unifiedDetail {
                #expect(claudeCodeCommand?.contains(detail) == true)
                #expect(codexEvent?.detail == detail)
            }
        }
    }

    @Test("Codex registers a session-end event alongside Claude Code's")
    func codexRegistersSessionEnd() {
        let events = HookSnippetGenerator.codexLifecycleEvents
        #expect(events.contains { $0.event == "SessionEnd" && $0.state == "idle" })
    }

    @Test("equivalent sequences project to identical state sequences")
    func equivalentSequencesProjectIdentically() {
        let sequence: [(state: AIAgentState, detail: String)] = [
            (.thinking, "Task started"),
            (.usingTool, "Using tool"),
            (.working, "Tool completed"),
            (.completed, "Task completed"),
            (.idle, "Session ended"),
        ]

        var statesByAgent: [IPCAgentID: [AIAgentState]] = [:]
        var admissionsByAgent: [IPCAgentID: [AIAgentMessageAdmission]] = [:]
        for agent in IPCAgentID.allCases {
            var ledger = AIAgentSessionLedger()
            var states: [AIAgentState] = []
            var admissions: [AIAgentMessageAdmission] = []
            for (index, step) in sequence.enumerated() {
                let message = Self.envelope(
                    agent: agent,
                    state: step.state,
                    detail: step.detail,
                    at: TimeInterval(1_000 + index)
                )
                admissions.append(ledger.admit(message))
                states.append(AIAgentActivity(message: message).state)
            }
            admissionsByAgent[agent] = admissions
            statesByAgent[agent] = states
        }

        let referenceStates = statesByAgent[.claudeCode]
        let referenceAdmissions = admissionsByAgent[.claudeCode]
        for agent in IPCAgentID.allCases {
            #expect(statesByAgent[agent] == referenceStates)
            #expect(admissionsByAgent[agent] == referenceAdmissions)
        }
        #expect(referenceStates == sequence.map(\.state))
        #expect(referenceAdmissions?.allSatisfy { $0 == .admit } == true)
    }

    @Test("session end tears down with the same timing for every agent")
    func sessionEndTeardownTimingIsUnified() {
        for agent in IPCAgentID.allCases {
            let ended = AIAgentActivity(
                message: Self.envelope(agent: agent, state: .idle, detail: "Session ended")
            )
            #expect(ended.endsPresentation)
            #expect(ended.autoDismiss == nil)

            let finishedTurn = AIAgentActivity(
                message: Self.envelope(agent: agent, state: .completed, detail: "Task completed")
            )
            #expect(finishedTurn.endsPresentation == false)
            #expect(
                finishedTurn.autoDismiss
                    == AutoDismissDescriptor(after: AIAgentActivity.completedAutoDismissAfter)
            )
        }
    }

    @Test("a late in-turn update is dropped for every agent")
    func lateTurnUpdatesAreStaleForEveryAgent() {
        for agent in IPCAgentID.allCases {
            var ledger = AIAgentSessionLedger()
            let turnEnd = Self.envelope(
                agent: agent,
                state: .completed,
                detail: "Task completed",
                at: 2_000
            )
            #expect(ledger.admit(turnEnd) == .admit)

            let lateToolResult = Self.envelope(
                agent: agent,
                state: .working,
                detail: "Tool completed",
                at: 1_999
            )
            #expect(ledger.admit(lateToolResult) == .stale)

            let lateSameTimestamp = Self.envelope(
                agent: agent,
                state: .working,
                detail: "Tool completed",
                at: 2_000
            )
            #expect(ledger.admit(lateSameTimestamp) == .stale)
        }
    }

    @Test("sub-agent envelopes normalize identically whatever the agent")
    func subAgentEnvelopesNormalizeForEveryAgent() {
        let rootSession = UUID(
            uuid: (0xAB, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
        )
        let childSession = UUID(
            uuid: (0xCD, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)
        )

        for agent in IPCAgentID.allCases {
            let child = AIAgentActivity(
                message: IPCMessage(
                    schemaVersion: IPCMessageValidator.supportedSchemaVersion,
                    agentId: agent,
                    sessionId: childSession,
                    rootSessionId: rootSession,
                    sessionName: "explore",
                    state: .working,
                    detail: "Sub-agent started",
                    timestamp: Date(timeIntervalSince1970: 3_000)
                )
            )
            #expect(child.isSubagent)
            #expect(child.rootSessionID == rootSession)
            #expect(child.sessionName == "explore")

            let root = AIAgentActivity(
                message: Self.envelope(
                    agent: agent,
                    session: rootSession,
                    state: .idle,
                    detail: "Session ended"
                )
            )
            let dependents = AIAgentActivity.dependents(
                endingWith: root,
                in: [root, child]
            )
            #expect(dependents.map(\.sessionID) == [childSession])
        }
    }

    /// The audit matrix's workspace row went all-or-nothing in Phase 3.3: the
    /// directory an agent ran in is a first-class envelope field for every
    /// agent. Dropping it from one artifact must fail here, not surface later
    /// as a panel affordance that works for two agents and not the third.
    @Test("every agent reports the directory it ran in")
    func workspaceRidesAlongForEveryAgent() throws {
        let generator = HookSnippetGenerator()
        let claudeCodeHooks = try Self.claudeCodeHooks(generator)
        let codexLifecycle = generator.codexLifecycleHooksFragment()
        let pluginSource = generator.openCodePluginFile()

        // Trigger layer. The two Python agents bake the hook event's `cwd`
        // into the shared payload call; the plugin guards on presence because
        // OpenCode hands it a bare directory string that can be undefined.
        for row in Self.parityTable {
            let command = try Self.claudeCodeHookCommand(
                for: row.claudeCodeTrigger,
                in: claudeCodeHooks
            )
            #expect(
                command?.contains(#"event.get("cwd")"#) == true,
                "Claude Code \(row.claudeCodeTrigger) must forward cwd (\(row.name))"
            )
        }
        // The Codex fragment is a `hooks.json` document, so the command text
        // is JSON-escaped in the artifact; decode before matching, the same
        // way the Claude Code fragment is read above.
        for row in Self.parityTable {
            let command = try Self.codexHookCommand(
                for: row.codexTrigger,
                in: codexLifecycle
            )
            #expect(
                command?.contains(#"workspace=event.get("cwd")"#) == true,
                "Codex \(row.codexTrigger) must forward cwd (\(row.name))"
            )
        }
        #expect(
            Self.pluginSource(
                pluginSource,
                matches: #"if \(directory\) payload\.workspace = directory"#
            )
        )

        // Envelope layer: whatever the agent, a workspace in the message is
        // the workspace on the activity, and absence stays absence.
        for agent in IPCAgentID.allCases {
            let rooted = AIAgentActivity(
                message: Self.envelope(
                    agent: agent,
                    state: .working,
                    detail: "Working…",
                    workspace: "/tmp/project"
                )
            )
            #expect(rooted.workspace == "/tmp/project")
            let bare = AIAgentActivity(
                message: Self.envelope(agent: agent, state: .working, detail: "Working…")
            )
            #expect(bare.workspace == nil)
        }
    }

    /// The audit matrix's tool-name row closed in Phase 3.1: every agent
    /// transmits the tool in flight on the tool-call milestone and only
    /// there. Claude Code's and Codex's halves are pinned behaviourally
    /// elsewhere (`HookGenerationTests.onlyPreToolUseCarriesAToolName`, the
    /// loopback tool-metadata test); this row adds the missing third column
    /// and holds all three side by side so the symmetry itself is the
    /// regression surface.
    @Test("the tool in flight is reported by every agent, only on the tool-call milestone")
    func toolInFlightIsReportedByEveryAgent() throws {
        let generator = HookSnippetGenerator()
        let claudeCodeHooks = try Self.claudeCodeHooks(generator)
        let pluginSource = generator.openCodePluginFile()

        // Trigger layer, Claude Code: the per-event command bakes the tool
        // expression in, so the tool-call trigger calls the helper and every
        // other milestone passes an explicit nothing. Matched at the call
        // site — the helper's own `def` line appears in every command.
        for row in Self.parityTable {
            let command = try Self.claudeCodeHookCommand(
                for: row.claudeCodeTrigger,
                in: claudeCodeHooks
            )
            if row.state == .usingTool {
                #expect(
                    command?.contains("notchflow_tool_name(event),") == true,
                    "Claude Code \(row.claudeCodeTrigger) must pass the tool in flight (\(row.name))"
                )
            } else {
                #expect(
                    command?.contains("notchflow_tool_name(event),") == false,
                    "Claude Code \(row.claudeCodeTrigger) must not claim a tool (\(row.name))"
                )
            }
        }

        // Trigger layer, Codex: the flag on the lifecycle table is what bakes
        // `True`/`False` into the generated STATES dict.
        for event in HookSnippetGenerator.codexLifecycleEvents {
            #expect(
                event.carriesToolName == (event.event == "PreToolUse"),
                "Codex \(event.event) tool-name wiring must match the tool-call milestone alone"
            )
        }

        // Trigger layer, OpenCode: the tool-call handler forwards `input.tool`
        // as the notify argument, and the payload guard keeps toolName off
        // every other state.
        #expect(
            Self.pluginSource(
                pluginSource,
                matches: #""tool\.execute\.before": async \(input\) => \{\s*await notify\("usingTool", input\.sessionID, "Using tool", input\.tool,"#
            )
        )
        #expect(
            Self.pluginSource(
                pluginSource,
                matches: #"if \(state === "usingTool" && toolName\) payload\.toolName = toolName"#
            )
        )

        // Envelope layer: the tool name projects identically whatever the
        // agent that reported it.
        for agent in IPCAgentID.allCases {
            let usingTool = AIAgentActivity(
                message: Self.envelope(
                    agent: agent,
                    state: .usingTool,
                    detail: "Using tool",
                    toolName: "Bash"
                )
            )
            #expect(usingTool.toolName == "Bash")
        }
    }

    private static func envelope(
        agent: IPCAgentID,
        session: UUID? = nil,
        state: AIAgentState,
        detail: String,
        workspace: String? = nil,
        toolName: String? = nil,
        at timestamp: TimeInterval = 0
    ) -> IPCMessage {
        IPCMessage(
            schemaVersion: IPCMessageValidator.supportedSchemaVersion,
            agentId: agent,
            sessionId: session ?? Self.sessionByAgent[agent]!,
            workspace: workspace,
            state: state,
            detail: detail,
            toolName: toolName,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }

    private static func claudeCodeHooks(
        _ generator: HookSnippetGenerator
    ) throws -> [String: Any] {
        let fragment = generator.claudeCodeSettingsFragment()
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(fragment.utf8)) as? [String: Any]
        )
        return try #require(root["hooks"] as? [String: Any])
    }

    private static func claudeCodeHookCommand(
        for event: String,
        in hooks: [String: Any]
    ) throws -> String? {
        let groups = try #require(hooks[event] as? [[String: Any]])
        let group = try #require(groups.first)
        let handlers = try #require(group["hooks"] as? [[String: Any]])
        let handler = try #require(handlers.first)
        return handler["command"] as? String
    }

    private static func codexHookCommand(
        for event: String,
        in fragment: String
    ) throws -> String? {
        let document = try #require(
            JSONSerialization.jsonObject(with: Data(fragment.utf8)) as? [String: Any]
        )
        let hooks = try #require(document["hooks"] as? [String: Any])
        return try claudeCodeHookCommand(for: event, in: hooks)
    }

    private static func pluginSource(
        _ source: String,
        matches pattern: String
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        return regex.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) != nil
    }
}
