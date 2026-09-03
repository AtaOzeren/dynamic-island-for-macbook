import Foundation

/// One agent session's status, as the island's activity model sees it.
///
/// The state itself lives in `AIAgentState` and the ordering of the messages
/// that carry it in `AIAgentSessionLedger`; this type is the activity wrapper
/// around a single reading of that state, carrying the four things `docs/07-ai-integration.md`
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
    /// Long enough to actually catch the green tick after looking away, which
    /// is the whole point of showing it. Cut short the moment the next turn
    /// starts: `ActivityManager` cancels this timer on every update, so a new
    /// prompt inside the window replaces the tick with the work immediately
    /// rather than waiting it out.
    public static let completedAutoDismissAfter: Duration = .seconds(15)

    public let agent: IPCAgentID
    /// One running instance of an agent, per the `Session` definition in
    /// `docs/14-glossary-and-conventions.md`.
    public let sessionID: UUID
    /// The top-level session this one belongs to.
    ///
    /// Equal to `sessionID` for a session the user started themselves, and the
    /// parent's identifier for a sub-agent the agent spawned to delegate work.
    /// This is what the island counts as "one running agent": a terminal that
    /// fans out to four sub-agents is one agent working, not five.
    public let rootSessionID: UUID
    /// The sub-agent's own name, for the list under its instance. `nil` for a
    /// top-level session, which is named after its agent instead.
    public let sessionName: String?
    public let workspace: String?
    public let state: AIAgentState
    /// Why the turn failed, when the agent could say. Meaningful only in
    /// `error`.
    public let reason: AIAgentFailureReason?
    /// When the failure named by `reason` lifts on its own.
    public let retryAt: Date?
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
        rootSessionID: UUID? = nil,
        sessionName: String? = nil,
        workspace: String? = nil,
        state: AIAgentState,
        reason: AIAgentFailureReason? = nil,
        retryAt: Date? = nil,
        detail: String,
        toolName: String? = nil,
        progress: Double? = nil
    ) {
        self.agent = agent
        self.sessionID = sessionID
        self.rootSessionID = rootSessionID ?? sessionID
        self.sessionName = sessionName
        self.workspace = workspace
        self.state = state
        self.reason = state == .error ? reason : nil
        self.retryAt = state == .error ? retryAt : nil
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
            rootSessionID: message.rootSessionId,
            sessionName: message.sessionName,
            workspace: message.workspace,
            state: message.state,
            reason: message.reason,
            retryAt: message.retryAt,
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

    /// The instance this session belongs to: one terminal, one editor window,
    /// one conversation the user started.
    ///
    /// What the compact badge tallies and what the expanded panel draws a card
    /// for. Sub-agents share their parent's, so delegating work never changes
    /// how many agents the island says are running.
    public static func instanceIdentity(
        agent: IPCAgentID,
        rootSessionID: UUID
    ) -> ActivityIdentity {
        ActivityIdentity("notchflow.ai.instance.\(agent.rawValue).\(rootSessionID.uuidString)")
    }

    public var compactInstanceIdentity: ActivityIdentity {
        Self.instanceIdentity(agent: agent, rootSessionID: rootSessionID)
    }

    /// Whether the agent is stopped by a condition outside the task itself —
    /// no quota, no credentials, no provider.
    ///
    /// These read differently from an ordinary failure. A task that errored is
    /// news: it happened once, the user reads it and moves on. A blocked agent
    /// is a *standing condition* that will keep failing every retry until
    /// something outside the island changes, and an agent retrying every forty
    /// seconds would otherwise announce the same news forever.
    ///
    /// The island therefore says it once in the pill and then keeps it as a
    /// footnote, per `docs/04-overlay-window.md`.
    public var isBlocked: Bool {
        guard state == .error, let reason else { return false }
        switch reason {
        case .quotaExhausted, .authFailed, .providerUnavailable: return true
        case .requestRejected, .unknown: return false
        }
    }

    /// How long a blocked agent stays in the pill: long enough to be seen, not
    /// long enough to become wallpaper.
    public static let blockedAnnouncementWindow: TimeInterval = 60

    public var compactAnnouncementWindow: TimeInterval? {
        isBlocked ? Self.blockedAnnouncementWindow : nil
    }

    /// Whether this session was spawned by another rather than by the user.
    public var isSubagent: Bool { rootSessionID != sessionID }

    public var compactRepresentationPriority: CompactRepresentationPriority {
        switch state {
        case .idle, .completed: .passive
        case .thinking, .working, .usingTool: .active
        case .waitingForUser: .attention
        case .error: .failure
        }
    }

    public var compactRegion: CompactActivityRegion { .agentTrailing }

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

    /// How long a session may say nothing at all before the island gives up on
    /// it.
    ///
    /// Not a display timeout — every message for a session restarts it. It exists
    /// because a hook only fires while its agent is alive: force-quit a terminal
    /// mid-task, or lose the process to a crash, and no `Stop` and no
    /// `SessionEnd` ever arrive. Without a bound the card that was on screen at
    /// that moment stays there for the rest of the session, and the only way to
    /// clear it is to quit NotchFlow.
    ///
    /// Long enough that a genuinely slow tool call is never mistaken for a dead
    /// agent — the states this governs are the ones that legitimately sit still,
    /// `waitingForUser` most of all.
    public static let silenceTimeout: Duration = .seconds(30 * 60)

    /// The same bound for the states that claim to be *doing* something.
    ///
    /// Sitting still is what `waitingForUser` and `error` mean, so silence tells
    /// nothing new about them. `thinking`, `working` and `usingTool` assert the
    /// opposite — work in flight, more events coming — and prolonged silence
    /// contradicts the state rather than confirming it.
    ///
    /// Observed as a card left behind by an OpenCode window that was simply
    /// closed: quitting the TUI is neither the end of a turn nor the deletion of
    /// a session, so no event is sent and the last `working` sat on screen for
    /// the full half hour while the process behind it no longer existed.
    ///
    /// Still generous, because a single long tool call is silent from start to
    /// finish: a test suite or a build that runs for minutes emits nothing
    /// between `usingTool` and the `working` that follows it, and dropping the
    /// card mid-run would make the island flicker exactly when it is most
    /// useful.
    public static let workingSilenceTimeout: Duration = .seconds(10 * 60)

    /// When this activity ends on its own.
    ///
    /// `completed` is a display timeout: the task is over and the card is a
    /// receipt. Everything else is the silence bound above, which the manager
    /// restarts on every message — so it only ever fires for a session that has
    /// stopped talking altogether.
    ///
    /// `error` still does not vanish on a short timer, per
    /// `docs/07-ai-integration.md`: a failure the user could miss is worse than
    /// one that lingers. It is simply no longer unbounded. `idle` needs no timer
    /// — it is the state where the activity ends outright, which is what
    /// `endsPresentation` says.
    public var autoDismiss: AutoDismissDescriptor? {
        switch state {
        case .completed:
            AutoDismissDescriptor(after: Self.completedAutoDismissAfter)
        case .idle:
            nil
        case .thinking, .working, .usingTool:
            AutoDismissDescriptor(after: Self.workingSilenceTimeout)
        case .waitingForUser, .error:
            AutoDismissDescriptor(after: Self.silenceTimeout)
        }
    }

    /// The activities that must end alongside this one.
    ///
    /// A sub-agent is a session its instance spawned, and nothing will ever
    /// report its end once the process behind it is gone: the agent that would
    /// have sent the message is the thing that exited. Ending a root therefore
    /// ends the sub-agents under it, or the panel keeps a list of orphans whose
    /// parent card has already disappeared.
    ///
    /// A sub-agent ending takes nothing with it — its siblings and its instance
    /// are still running, and one delegated task finishing says nothing about
    /// the rest.
    public static func dependents(
        endingWith session: AIAgentActivity,
        in activities: [any Activity]
    ) -> [AIAgentActivity] {
        guard session.isSubagent == false else { return [] }
        return activities.compactMap { candidate in
            guard let other = candidate as? AIAgentActivity,
                other.isSubagent,
                other.agent == session.agent,
                other.rootSessionID == session.rootSessionID
            else {
                return nil
            }
            return other
        }
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
