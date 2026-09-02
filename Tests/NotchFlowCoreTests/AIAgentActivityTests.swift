import Foundation
import Testing

@testable import NotchFlowCore

/// The AI activity's value semantics: the priority and auto-dismiss rows of the
/// V1 table in `docs/05-activity-model.md`, the per-session identity from
/// `docs/07-ai-integration.md`, and the fields the privacy rule keeps out. All
/// of it is pure logic over injected state, so none of it needs a running agent.
@Suite("AIAgentActivity")
struct AIAgentActivityTests {
    private static let session = UUID(
        uuid: (0x6F, 0x96, 0x19, 0xFF, 0x8B, 0x86, 0xD0, 0x11, 0xB4, 0x2D, 0x00, 0xC0, 0x4F, 0xC9, 0x64, 0xFF)
    )

    private static func activity(
        agent: IPCAgentID = .claudeCode,
        sessionID: UUID = session,
        state: AIAgentState = .working,
        detail: String = "Editing src/App.swift",
        toolName: String? = nil,
        progress: Double? = nil
    ) -> AIAgentActivity {
        AIAgentActivity(
            agent: agent,
            sessionID: sessionID,
            state: state,
            detail: detail,
            toolName: toolName,
            progress: progress
        )
    }

    @Test("reports the AI kind in every state")
    func kind() {
        for state in AIAgentState.allCases {
            #expect(Self.activity(state: state).kind == .aiAgent)
        }
    }

    /// The two `high` rows of the V1 priority table — needs-input and completed
    /// — plus `error`, which sits with them because it is equally a state the
    /// agent cannot leave without the user.
    @Test("raises the priority for the states the user must act on")
    func attentionStatesArePrioritised() {
        for state in [AIAgentState.waitingForUser, .completed, .error] {
            #expect(Self.activity(state: state).priority == .high)
        }
    }

    /// The work loop must not outrank a recording indicator or an expiring
    /// timer: an agent thinking in the background is not news.
    @Test("leaves the work loop at the normal priority")
    func workLoopIsNormalPriority() {
        for state in [AIAgentState.idle, .thinking, .working, .usingTool] {
            #expect(Self.activity(state: state).priority == .normal)
        }
    }

    /// `docs/05-activity-model.md` marks AI completed auto-dismissing: the task
    /// is over and the card is a receipt.
    @Test("completed dismisses itself on the short display timer")
    func completedUsesTheDisplayTimer() {
        let descriptor = Self.activity(state: .completed).autoDismiss

        #expect(
            descriptor == AutoDismissDescriptor(after: AIAgentActivity.completedAutoDismissAfter)
        )
    }

    /// A hook only fires while its agent is alive. Force-quit a terminal
    /// mid-task and no `Stop` and no `SessionEnd` ever arrive, so without a
    /// bound the card on screen at that moment stays for the rest of the
    /// session. Every state that can be left behind carries one.
    @Test("every live state is bounded by a silence timeout")
    func liveStatesAreBoundedBySilence() {
        for state in AIAgentState.allCases where state != .completed && state != .idle {
            #expect(Self.activity(state: state).autoDismiss != nil, "\(state) is unbounded")
        }
    }

    /// A state that claims work is in flight is contradicted by silence, while
    /// sitting still is what the resting states mean. The bounds differ for that
    /// reason, and the working one has to be the shorter of the two.
    ///
    /// The defect: closing an OpenCode window is neither the end of a turn nor
    /// the deletion of a session, so nothing was sent and the last `working` sat
    /// on screen for the full half hour after the process was gone.
    @Test("a working state gives up on silence sooner than a resting one")
    func workingStatesExpireSoonerThanRestingOnes() {
        for state in [AIAgentState.thinking, .working, .usingTool] {
            #expect(
                Self.activity(state: state).autoDismiss
                    == AutoDismissDescriptor(after: AIAgentActivity.workingSilenceTimeout),
                "\(state) claims work in flight and must not wait out the resting bound"
            )
        }

        for state in [AIAgentState.waitingForUser, .error] {
            #expect(
                Self.activity(state: state).autoDismiss
                    == AutoDismissDescriptor(after: AIAgentActivity.silenceTimeout),
                "\(state) is a resting state and must not be cut short"
            )
        }

        #expect(AIAgentActivity.workingSilenceTimeout < AIAgentActivity.silenceTimeout)
    }

    /// A single tool call is silent from start to finish, so the working bound
    /// has to outlast a build or a test suite by a wide margin — cutting a card
    /// mid-run would make the island flicker exactly when it is most useful.
    @Test("the working bound still outlasts a long tool call")
    func workingBoundOutlastsALongToolCall() {
        #expect(AIAgentActivity.workingSilenceTimeout >= .seconds(5 * 60))
    }

    // MARK: - Ending an instance ends its sub-agents

    /// Nothing will ever report a sub-agent's end once its instance is gone: the
    /// agent that would have sent the message is the thing that exited.
    @Test("ending a root ends the sub-agents under it")
    func endingARootEndsItsSubagents() {
        let root = UUID()
        let instance = Self.activity(agent: .opencode, sessionID: root)
        let first = Self.subagent(root: root)
        let second = Self.subagent(root: root)
        let otherInstance = Self.activity(agent: .opencode, sessionID: UUID())
        let otherSubagent = Self.subagent(root: otherInstance.sessionID)

        let dependents = AIAgentActivity.dependents(
            endingWith: instance,
            in: [instance, first, second, otherInstance, otherSubagent]
        )

        #expect(Set(dependents.map(\.sessionID)) == [first.sessionID, second.sessionID])
    }

    /// One delegated task finishing says nothing about its siblings or about the
    /// instance that spawned it.
    @Test("a sub-agent ending takes nothing with it")
    func subagentEndingTakesNothingWithIt() {
        let root = UUID()
        let instance = Self.activity(agent: .opencode, sessionID: root)
        let first = Self.subagent(root: root)
        let second = Self.subagent(root: root)

        #expect(
            AIAgentActivity.dependents(
                endingWith: first,
                in: [instance, first, second]
            ).isEmpty
        )
    }

    /// Two agents can each have an instance whose root identifier collides only
    /// by coincidence; neither may reap the other's sessions.
    @Test("sub-agents of another agent are left alone")
    func subagentsOfAnotherAgentAreLeftAlone() {
        let root = UUID()
        let instance = Self.activity(agent: .opencode, sessionID: root)
        let foreign = AIAgentActivity(
            agent: .claudeCode,
            sessionID: UUID(),
            rootSessionID: root,
            sessionName: "explore",
            state: .working,
            detail: "Delegated"
        )

        #expect(AIAgentActivity.dependents(endingWith: instance, in: [instance, foreign]).isEmpty)
    }

    private static func subagent(
        root: UUID,
        state: AIAgentState = .working
    ) -> AIAgentActivity {
        AIAgentActivity(
            agent: .opencode,
            sessionID: UUID(),
            rootSessionID: root,
            sessionName: "explore",
            state: state,
            detail: "Delegated"
        )
    }

    /// `idle` ends the activity outright rather than lingering, which is what
    /// `endsPresentation` says.
    @Test("idle carries no timer")
    func idleHasNoTimer() {
        #expect(Self.activity(state: .idle).autoDismiss == nil)
    }

    /// `docs/07-ai-integration.md`: an error must not vanish on a timer the user
    /// could blink through. Bounded is not the same as brief — the silence
    /// timeout is orders of magnitude longer than the completed one.
    @Test("a failure outlives a completion by a wide margin")
    func failuresLingerFarLongerThanCompletions() {
        #expect(AIAgentActivity.silenceTimeout > AIAgentActivity.completedAutoDismissAfter * 100)
    }

    /// One identity for the whole state machine of one session, so `thinking`
    /// becoming `usingTool` updates the element already on screen rather than
    /// adding a second one claiming the same session is in two states at once.
    @Test("keeps one identity across every state of a session")
    func identityIsStableAcrossStates() {
        let identities = Set(AIAgentState.allCases.map { Self.activity(state: $0).identity })

        #expect(identities.count == 1)
    }

    /// Concurrent sessions are concurrent facts, so they may never collapse onto
    /// one identity — that would let one session silently replace another.
    @Test("gives each session and each agent its own identity")
    func identityIsPerSessionAndAgent() {
        let otherSession = UUID()
        let identities = Set(
            [
                Self.activity().identity,
                Self.activity(sessionID: otherSession).identity,
                Self.activity(agent: .codex).identity,
                Self.activity(agent: .opencode).identity,
            ]
        )

        #expect(identities.count == 4)
    }

    @Test("shares one compact group identity across sessions of the same agent")
    func compactIdentityIsPerAgent() {
        let first = Self.activity(sessionID: UUID())
        let second = Self.activity(sessionID: UUID())

        #expect(first.identity != second.identity)
        #expect(first.compactGroupIdentity == second.compactGroupIdentity)
        #expect(first.compactGroupIdentity != Self.activity(agent: .codex).compactGroupIdentity)
    }

    @Test("ranks actionable and active states above completed compact status")
    func compactRepresentationPreference() {
        #expect(
            Self.activity(state: .error).compactRepresentationPriority
                > Self.activity(state: .waitingForUser).compactRepresentationPriority
        )
        #expect(
            Self.activity(state: .waitingForUser).compactRepresentationPriority
                > Self.activity(state: .working).compactRepresentationPriority
        )
        #expect(
            Self.activity(state: .working).compactRepresentationPriority
                > Self.activity(state: .completed).compactRepresentationPriority
        )
    }

    @Test("offers an action that opens the originating agent")
    func primaryActionNamesTheAgent() {
        #expect(Self.activity(agent: .claudeCode).primaryAction?.title == "Open Claude")
        #expect(Self.activity(agent: .codex).primaryAction?.title == "Open Codex")
        #expect(Self.activity(agent: .opencode).primaryAction?.title == "Open OpenCode")
    }

    /// An affordance on an element that is about to be removed is one nobody can
    /// hit, so the state that ends the activity offers none.
    @Test("offers no action once the session is idle")
    func idleOffersNoPrimaryAction() {
        #expect(Self.activity(state: .idle).primaryAction == nil)
        #expect(Self.activity(state: .idle).endsPresentation)
    }

    @Test("keeps every non-idle state on screen")
    func nonIdleStatesPresent() {
        for state in AIAgentState.allCases where state != .idle {
            #expect(Self.activity(state: state).endsPresentation == false)
        }
    }

    /// The envelope marks `toolName` meaningful only in `usingTool`. Normalising
    /// it here means no view has to decide whether a stale tool name left over
    /// from an earlier state is worth drawing.
    @Test("keeps the tool name only while a tool is in flight")
    func toolNameIsScopedToUsingTool() {
        #expect(Self.activity(state: .usingTool, toolName: "Bash").toolName == "Bash")

        for state in AIAgentState.allCases where state != .usingTool {
            #expect(Self.activity(state: state, toolName: "Bash").toolName == nil)
        }
    }

    /// The schema bounds progress to `0.0...1.0`; a value outside it is clamped
    /// rather than propagated, so no bar can be drawn past either end.
    @Test("clamps progress into the schema's range")
    func progressIsClamped() {
        #expect(Self.activity(progress: 1.5).progress == 1)
        #expect(Self.activity(progress: -0.5).progress == 0)
        #expect(Self.activity(progress: 0.25).progress == 0.25)
    }

    @Test("omits progress when the agent reports none")
    func progressIsOptional() {
        #expect(Self.activity(progress: nil).progress == nil)
    }

    /// The activity is a projection of an already-validated envelope, so every
    /// field it carries must survive the trip intact.
    @Test("projects a validated envelope without losing a field")
    func buildsFromMessage() {
        let message = IPCMessage(
            schemaVersion: "1.0",
            agentId: .codex,
            sessionId: Self.session,
            state: .usingTool,
            detail: "Running test suite",
            toolName: "Bash",
            progress: 0.5,
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let activity = AIAgentActivity(message: message)

        #expect(activity.agent == .codex)
        #expect(activity.sessionID == Self.session)
        #expect(activity.state == .usingTool)
        #expect(activity.detail == "Running test suite")
        #expect(activity.toolName == "Bash")
        #expect(activity.progress == 0.5)
    }
}
