import Foundation

/// One agent session's status, as the island's activity model sees it.
///
/// The state itself lives in `AIAgentState` and its legal transitions in
/// `AIAgentStateMachine`; this type is the activity wrapper around a single
/// reading of that state, carrying the four things `docs/07-ai-integration.md`
/// lets cross the process boundary — the state, the agent, the short detail
/// line, and the optional tool name and progress — and nothing else.
///
/// What it deliberately cannot carry is the rest of the envelope's world: no
/// prompt, no code, no diff, no transcript. The privacy rule in
/// `docs/07-ai-integration.md` is not a rendering convention here, it is the
/// shape of the type — a view cannot draw a transcript excerpt it was never
/// given, and nothing downstream has anywhere to fetch one from.
public struct AIAgentActivity: Activity, Equatable {
    /// How long a `completed` state stays on screen before the manager ends it.
    ///
    /// The same five seconds `AIAgentStateMachine` uses for its own expiry, so
    /// the machine's idea of when a finished task is over and the island's
    /// cannot drift apart.
    public static let completedAutoDismissAfter: Duration = .seconds(5)

    public let agent: IPCAgentID
    /// One running instance of an agent, per the `Session` definition in
    /// `docs/14-glossary-and-conventions.md`.
    public let sessionID: UUID
    public let state: AIAgentState
    /// The short, human-readable line the expanded view shows, straight from
    /// the envelope's `detail` field.
    public let detail: String
    /// The tool in flight. Meaningful only in `usingTool`, per the envelope
    /// spec, and normalised to `nil` in every other state so no view has to
    /// decide whether a stale tool name is worth drawing.
    public let toolName: String?
    /// Fractional completion, clamped to `0...1`. `nil` when the agent cannot
    /// report one — the envelope omits the field for indeterminate work, and an
    /// indeterminate task drawn as a zero-length bar would be a lie.
    public let progress: Double?

    public init(
        agent: IPCAgentID,
        sessionID: UUID,
        state: AIAgentState,
        detail: String,
        toolName: String? = nil,
        progress: Double? = nil
    ) {
        self.agent = agent
        self.sessionID = sessionID
        self.state = state
        self.detail = detail
        self.toolName = state == .usingTool ? toolName : nil
        self.progress = progress.map { $0.clamped(to: 0...1) }
    }

    /// The activity for a validated envelope. The message has already been
    /// through `IPCMessageValidator`, so this is a projection rather than a
    /// second validation pass.
    public init(message: IPCMessage) {
        self.init(
            agent: message.agentId,
            sessionID: message.sessionId,
            state: message.state,
            detail: message.detail,
            toolName: message.toolName,
            progress: message.progress
        )
    }

    /// One identity per session, not per agent: `docs/07-ai-integration.md`
    /// gives each concurrent session its own activity, so two Claude sessions
    /// remain independently tracked. Presentation may group them under one
    /// agent icon, while its disclosure still lists both sessions.
    ///
    /// It is stable across the whole state machine for that session, so
    /// `thinking` becoming `usingTool` updates the element already on screen —
    /// the same reason `ChargingActivity` keeps one identity across its three
    /// states.
    public static func identity(agent: IPCAgentID, sessionID: UUID) -> ActivityIdentity {
        ActivityIdentity("notchflow.ai.\(agent.rawValue).\(sessionID.uuidString)")
    }

    public var identity: ActivityIdentity {
        Self.identity(agent: agent, sessionID: sessionID)
    }

    public var compactGroupIdentity: ActivityIdentity {
        ActivityIdentity("notchflow.ai.group.\(agent.rawValue)")
    }

    public var compactRepresentationPriority: CompactRepresentationPriority {
        switch state {
        case .idle, .completed: .passive
        case .thinking, .working, .usingTool: .active
        case .waitingForUser: .attention
        case .error: .failure
        }
    }

    public var kind: ActivityKind { .aiAgent }

    /// Per the V1 priority table in `docs/05-activity-model.md`: the states the
    /// user has to act on — needs-input and the two terminal ones — are `high`
    /// and may force the panel visible, while the work loop is `normal` and
    /// waits its turn.
    ///
    /// `error` is `high` on the same footing as `waitingForUser`: both are
    /// states where the agent has stopped and cannot continue without the user,
    /// and a failure that sorted below background music would be a failure the
    /// user finds out about late.
    public var priority: ActivityPriority {
        switch state {
        case .waitingForUser, .completed, .error: .high
        case .idle, .thinking, .working, .usingTool: .normal
        }
    }

    /// Only `completed` dismisses itself.
    ///
    /// `error` deliberately does not, per `docs/07-ai-integration.md`: a failed
    /// task waits for dismissal, because an error that vanished on a timer is
    /// an error the user can miss entirely. `idle` needs no timer either — it
    /// is the state where the activity ends outright rather than lingering for
    /// a few seconds first, which is what `endsPresentation` says.
    public var autoDismiss: AutoDismissDescriptor? {
        state == .completed ? AutoDismissDescriptor(after: Self.completedAutoDismissAfter) : nil
    }

    /// Whether the session still has anything to show.
    ///
    /// `idle` is "registered, but no active task" — `docs/07-ai-integration.md`
    /// renders it as *not shown*, the activity ends. Exposing that as a property
    /// rather than refusing to construct an idle activity keeps the type able to
    /// represent every state the protocol can deliver, and leaves the removal to
    /// the one place that owns the active set.
    public var endsPresentation: Bool { state == .idle }

    /// Brings the application hosting the agent session forward, per the
    /// primary action in `docs/05-activity-model.md`.
    ///
    /// Absent in `idle` for the same reason the activity ends there: an
    /// affordance on an element that is about to disappear is an affordance
    /// nobody can hit.
    public var primaryAction: PrimaryAction? {
        guard endsPresentation == false else { return nil }
        return PrimaryAction(
            title: localized("Open \(agent.displayName)"),
            symbolName: "arrow.up.forward",
            intent: .openAgentApplication(agent)
        )
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
