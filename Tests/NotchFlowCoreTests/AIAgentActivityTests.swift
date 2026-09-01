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

    /// `docs/05-activity-model.md` marks AI completed auto-dismissing and AI
    /// needs-input not; `docs/07-ai-integration.md` adds that `error` waits for
    /// dismissal. An error on a timer is an error the user can miss.
    @Test("auto-dismisses only from the completed state")
    func autoDismissesOnlyWhenCompleted() {
        for state in AIAgentState.allCases {
            let descriptor = Self.activity(state: state).autoDismiss

            if state == .completed {
                #expect(descriptor == AutoDismissDescriptor(after: AIAgentActivity.completedAutoDismissAfter))
            } else {
                #expect(descriptor == nil)
            }
        }
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
