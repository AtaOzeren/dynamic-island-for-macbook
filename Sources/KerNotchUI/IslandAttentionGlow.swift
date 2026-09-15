import Foundation
import KerNotchCore

/// How the attention glow moves: one soft light crossing the island from left
/// to right, a rest once it has gone, then the next crossing — a fixed number
/// of times.
///
/// The whole sequence lasts exactly as long as a completed agent stays on the
/// island, so a finished task's glow and its green tick leave together.
public enum IslandAttentionGlowTiming {
    /// One crossing, slow enough to follow with the eye.
    public static let passDuration: TimeInterval = 2
    /// The pause after a crossing, counted from the moment the light leaves.
    public static let restAfterPass: TimeInterval = 3
    public static let passCount = 5
    /// How quickly the glow fades in when it starts and out when it stops early.
    public static let fadeDuration: TimeInterval = 0.2

    /// One crossing and the rest that follows it.
    public static var passInterval: TimeInterval {
        passDuration + restAfterPass
    }

    /// An agent's full sequence: every crossing with the rests between them.
    public static var totalDuration: TimeInterval {
        duration(ofPasses: passCount)
    }

    /// Nothing follows the last crossing, so a sequence ends as its final light
    /// leaves the island.
    public static func duration(ofPasses passes: Int) -> TimeInterval {
        passInterval * TimeInterval(passes) - restAfterPass
    }
}

/// A light around the compact island saying an agent has news: it finished,
/// it is asking something, or it failed.
///
/// The pill's status badge already says this, but a badge a few points wide
/// beside the notch is easy to miss while working in another window. The glow
/// is the part that catches the eye; the badge is what remains afterwards.
public struct IslandAttentionGlow: Equatable, Sendable {
    /// Why the island glows, in rising urgency — the order a newer glow has to
    /// meet or beat to take over from one already running.
    public enum Reason: Int, Comparable, Sendable {
        case completed
        case needsInput
        case failed

        public static func < (lhs: Reason, rhs: Reason) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// What the session has to say, if anything worth a glow.
        ///
        /// A sub-agent finishing is not news — its instance is still working,
        /// and a green light for every delegated step would drown the one for
        /// the task itself. A sub-agent that asks or fails blocks the instance,
        /// so those still count.
        init?(session: AIAgentActivity) {
            switch session.state {
            case .completed where session.isSubagent == false:
                self = .completed
            case .waitingForUser:
                self = .needsInput
            case .error:
                self = .failed
            case .idle, .thinking, .working, .usingTool, .completed:
                return nil
            }
        }

        /// The tone the pill's status badge uses for the same state.
        var badgeTone: AIAgentCompactBadgeTone {
            switch self {
            case .completed: .green
            case .needsInput: .yellow
            case .failed: .red
            }
        }
    }

    public let sessionIdentity: ActivityIdentity
    public let reason: Reason
    public let startedAt: Date
    /// How many crossings the sequence runs: an agent's full five, or the one
    /// the Settings test button shows.
    public private(set) var passCount = IslandAttentionGlowTiming.passCount

    public init(sessionIdentity: ActivityIdentity, reason: Reason, startedAt: Date) {
        self.sessionIdentity = sessionIdentity
        self.reason = reason
        self.startedAt = startedAt
    }

    /// The Settings test button's glow: a single crossing in the
    /// question-and-approval colour — enough to show what the switch controls
    /// without making the user sit through a whole sequence.
    public static func preview(startedAt: Date) -> IslandAttentionGlow {
        var glow = IslandAttentionGlow(sessionIdentity: previewIdentity, reason: .needsInput, startedAt: startedAt)
        glow.passCount = 1
        return glow
    }

    private static let previewIdentity = ActivityIdentity("kernotch.attentionGlow.preview")

    public var endsAt: Date {
        startedAt.addingTimeInterval(IslandAttentionGlowTiming.duration(ofPasses: passCount))
    }
}

/// Decides when the island glows, from the agent sessions it can see.
///
/// A glow starts when a session *enters* a state worth one, never while it
/// merely stays there: agents repeat their state freely, and a light that
/// restarted on every repetition would never end. It stops early the moment
/// the session that started it moves on — the question answered, the next
/// turn begun, the session gone — because a light still asking for the user
/// after they have answered is a wrong light.
///
/// A moment that arrives while a more urgent glow is running is held, not
/// forgotten: once that glow is over, the strongest held moment that still
/// stands gets its own light. Otherwise a question asked while another agent's
/// failure was glowing would never be announced at all.
public struct IslandAttentionGlowTracker: Equatable, Sendable {
    private struct Arrival {
        let identity: ActivityIdentity
        let reason: IslandAttentionGlow.Reason
        let registeredAt: Date
    }

    public private(set) var glow: IslandAttentionGlow?

    /// Each session's state as of the previous advance, which is what makes a
    /// state an arrival rather than a repetition.
    private var observedStates: [ActivityIdentity: AIAgentState] = [:]

    /// Moments that arrived behind a more urgent glow and have not had their own.
    private var heldReasons: [ActivityIdentity: IslandAttentionGlow.Reason] = [:]

    public init() {}

    public mutating func advance(
        activities: [any Activity],
        registrationTimes: [ActivityIdentity: Date],
        now: Date
    ) {
        let sessions = activities.compactMap { $0 as? AIAgentActivity }
        glow = glow.flatMap { stillLit($0, among: sessions, at: now) }
        heldReasons = heldReasons.filter { identity, reason in
            sessions.first { $0.identity == identity }.flatMap(IslandAttentionGlow.Reason.init(session:)) == reason
        }

        var waiting = arrivals(among: sessions, registrationTimes: registrationTimes)
        if let strongest = waiting.first, outranksCurrentGlow(strongest) {
            light(strongest, at: now)
            waiting.removeFirst()
        }
        for arrival in waiting {
            heldReasons[arrival.identity] = arrival.reason
        }

        if glow == nil, let held = strongestHeld(registrationTimes: registrationTimes) {
            light(held, at: now)
        }

        observedStates = Dictionary(
            sessions.map { ($0.identity, $0.state) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// The running glow, if its time is not up and its session still says what
    /// started it.
    private func stillLit(
        _ glow: IslandAttentionGlow,
        among sessions: [AIAgentActivity],
        at now: Date
    ) -> IslandAttentionGlow? {
        guard now < glow.endsAt else { return nil }
        let source = sessions.first { $0.identity == glow.sessionIdentity }
        return source.flatMap(IslandAttentionGlow.Reason.init(session:)) == glow.reason ? glow : nil
    }

    private mutating func light(_ arrival: Arrival, at now: Date) {
        glow = IslandAttentionGlow(sessionIdentity: arrival.identity, reason: arrival.reason, startedAt: now)
        heldReasons[arrival.identity] = nil
    }

    /// Sessions that have just entered a glowing state, strongest first: most
    /// urgent, then most recently registered, so the newest news shows.
    private func arrivals(
        among sessions: [AIAgentActivity],
        registrationTimes: [ActivityIdentity: Date]
    ) -> [Arrival] {
        sessions
            .filter { observedStates[$0.identity] != $0.state }
            .compactMap { session in
                IslandAttentionGlow.Reason(session: session).map { reason in
                    Arrival(
                        identity: session.identity,
                        reason: reason,
                        registeredAt: registrationTimes[session.identity] ?? .distantPast
                    )
                }
            }
            .sorted(by: Self.isStronger)
    }

    private func strongestHeld(registrationTimes: [ActivityIdentity: Date]) -> Arrival? {
        heldReasons
            .map { identity, reason in
                Arrival(
                    identity: identity,
                    reason: reason,
                    registeredAt: registrationTimes[identity] ?? .distantPast
                )
            }
            .min(by: Self.isStronger)
    }

    private static func isStronger(_ lhs: Arrival, _ rhs: Arrival) -> Bool {
        (lhs.reason, lhs.registeredAt, lhs.identity.rawValue)
            > (rhs.reason, rhs.registeredAt, rhs.identity.rawValue)
    }

    /// Equal urgency replaces, so the newest news restarts the light. Lower
    /// urgency waits for the more important glow to end rather than cutting it
    /// short.
    private func outranksCurrentGlow(_ arrival: Arrival) -> Bool {
        guard let glow else { return true }
        return arrival.reason >= glow.reason
    }
}
