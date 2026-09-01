import Foundation

public enum AIAgentState: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case idle
    case thinking
    case working
    case usingTool
    case waitingForUser
    case completed
    case error
}

/// What the receivers do with one envelope, once ordering has been considered.
public enum AIAgentMessageAdmission: Equatable, Sendable {
    /// The message is the newest thing this session has said. Apply it.
    case admit
    /// An older message overtaken by one already applied. Drop it.
    case stale
}

/// Keeps each agent session's timeline monotonic.
///
/// Both transports deliver asynchronously — the loopback socket per connection,
/// the URL scheme through Launch Services — and a hook that fires twice in quick
/// succession can arrive in either order. Without this, a late `usingTool`
/// overwrites the `completed` that already landed and the island shows an agent
/// that finished as still running, with nothing left to correct it.
///
/// Ordering is decided on the envelope's own `timestamp` rather than on arrival,
/// because arrival order is exactly the thing that cannot be trusted here.
///
/// This replaced a transition-table state machine that was never wired into the
/// delivery path. A table that says which state may follow which cannot be kept
/// true for three independently versioned agents — every new lifecycle event is
/// a rejected transition and a stuck icon — whereas "newest wins per session" is
/// a property of the transport, not of any one agent's lifecycle.
public struct AIAgentSessionLedger: Sendable {
    private var latestTimestampBySessionID: [UUID: Date] = [:]

    public init() {}

    /// Whether `message` should be applied, recording it when it should.
    ///
    /// Equal timestamps admit: two events inside one millisecond are ordinary at
    /// this resolution, and refusing the second would drop the state change the
    /// pair exists to report.
    public mutating func admit(_ message: IPCMessage) -> AIAgentMessageAdmission {
        if let latest = latestTimestampBySessionID[message.sessionId],
            message.timestamp < latest
        {
            return .stale
        }
        latestTimestampBySessionID[message.sessionId] = message.timestamp
        return .admit
    }

    /// Drops a finished session's bookmark.
    ///
    /// Called when a session ends so a long-lived process never accumulates one
    /// entry per session it has ever seen, and so an agent that reuses a session
    /// identifier is not judged against a timestamp from its previous life.
    public mutating func forget(_ sessionID: UUID) {
        latestTimestampBySessionID[sessionID] = nil
    }

    /// How many sessions are currently bookmarked. Exposed so a test can assert
    /// the table is actually pruned rather than merely appearing to work.
    public var trackedSessionCount: Int { latestTimestampBySessionID.count }
}
