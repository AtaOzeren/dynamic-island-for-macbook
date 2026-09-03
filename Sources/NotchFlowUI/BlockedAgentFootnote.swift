import Foundation
import NotchFlowCore
import SwiftUI

/// What the expanded panel says at its foot about agents that cannot run.
///
/// A standing condition, not an event. The pill announces a block once and then
/// goes quiet, per `docs/04-overlay-window.md`; this is where the fact keeps
/// living, so opening the island still answers "why is nothing happening?"
/// hours later.
///
/// One line for the lot, not one per session. Several sessions of one agent all
/// stop for the same reason at the same moment — that is what an exhausted quota
/// does — and repeating it per session would be the same noise the announcement
/// window exists to remove, moved somewhere else.
public struct BlockedAgentFootnote: Equatable, Sendable {
    /// The agents that cannot run, in the order the panel lists them.
    public let agents: [IPCAgentID]
    public let reason: AIAgentFailureReason
    /// The earliest moment any of them expects to recover.
    public let retryAt: Date?

    public init(agents: [IPCAgentID], reason: AIAgentFailureReason, retryAt: Date? = nil) {
        self.agents = agents
        self.reason = reason
        self.retryAt = retryAt
    }

    /// What the line reads.
    ///
    /// Names the agents while there are few enough for a name to help, and
    /// counts them once there are not — "3 agents" is easier to take in than
    /// three names run together, and the panel above already lists them.
    public var title: String {
        let subject =
            agents.count > 2
            ? localized("\(agents.count) agents")
            : agents.map(\.displayName).joined(separator: ", ")
        return localized(
            "activity.ai.blockedFootnote",
            default: "\(subject) · \(reasonText)"
        )
    }

    private var reasonText: String {
        switch reason {
        case .quotaExhausted: localized("Out of quota")
        case .authFailed: localized("Sign-in required")
        case .providerUnavailable: localized("Provider unavailable")
        case .requestRejected: localized("Request refused")
        case .unknown: localized("Stopped on an error")
        }
    }

    /// Whether there is a recovery time worth drawing, without formatting one.
    ///
    /// The panel's height model asks this on every layout pass — several times
    /// per animation frame — and building a `DateFormatter` to answer it would
    /// put a measurable cost inside the expand animation, against the idle
    /// budget in `docs/02-performance-contract.md`.
    public func hasRecoveryText(now: Date = Date()) -> Bool {
        guard reason.resolvesWithTime, let retryAt else { return false }
        // A reset time that has already passed is not a promise, it is a stale
        // one: the agent said it would recover and has not. Saying nothing beats
        // pointing at a moment that has been and gone.
        return retryAt > now
    }

    /// When the block lifts, for the conditions that lift on their own.
    ///
    /// Only quota does, and only when the agent said so and the moment is still
    /// ahead. Everything else waits on the user, and a time next to it would be
    /// a promise nothing keeps.
    public func recoveryText(now: Date = Date()) -> String? {
        guard hasRecoveryText(now: now), let retryAt else { return nil }
        return localized(
            "activity.ai.blockedRecovery",
            default: "Resets at \(Self.recoveryFormatter.string(from: retryAt))"
        )
    }

    /// Built once. `DateFormatter` is expensive to create and this is read on a
    /// drawing path.
    private static let recoveryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter
    }()

    public var accessibilityLabel: String {
        guard let recoveryText = recoveryText() else { return title }
        return localized(
            "activity.accessibility.headlineAndDetail",
            default: "\(title), \(recoveryText)"
        )
    }
}

/// The footnote for a set of activities, or `nil` when nothing is blocked.
///
/// Collapses to the single most pressing reason. Two agents down for different
/// causes is rare and a footnote is not a report — the panel above still shows
/// each card, and one clear line beats a compound sentence nobody finishes.
public func blockedAgentFootnote(for activities: [any Activity]) -> BlockedAgentFootnote? {
    let blocked = activities.compactMap { activity -> AIAgentActivity? in
        guard let session = activity as? AIAgentActivity, session.isBlocked else { return nil }
        return session
    }
    guard let reason = blocked.compactMap(\.reason).min(by: { $0.severity < $1.severity })
    else {
        return nil
    }

    let matching = blocked.filter { $0.reason == reason }
    var agents: [IPCAgentID] = []
    for session in matching where agents.contains(session.agent) == false {
        agents.append(session.agent)
    }

    return BlockedAgentFootnote(
        agents: agents,
        reason: reason,
        retryAt: matching.compactMap(\.retryAt).min()
    )
}

extension AIAgentFailureReason {
    /// Which cause wins when several are in play at once.
    ///
    /// Ordered by what the user can do about it: credentials and quota are
    /// theirs to fix or wait out, a provider outage is nobody's, and an
    /// unclassified failure says least of all.
    fileprivate var severity: Int {
        switch self {
        case .authFailed: 0
        case .quotaExhausted: 1
        case .providerUnavailable: 2
        case .requestRejected: 3
        case .unknown: 4
        }
    }
}

/// The footnote's drawn height, including the hairline above it.
public func blockedFootnoteHeight(
    hasRecoveryText: Bool,
    metrics: ExpandedPanelMetrics = .default,
    scale: IslandTypeScale = .default
) -> CGFloat {
    let lines = hasRecoveryText ? 2 : 1
    return metrics.rowSpacing + CGFloat(lines) * (scale.footnote + 4)
}

/// The panel's foot: a hairline, then the smallest text the island draws.
struct BlockedAgentFootnoteView: View {
    let footnote: BlockedAgentFootnote
    let metrics: ExpandedPanelMetrics
    let scale: IslandTypeScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IslandItemSeparator(height: metrics.rowSpacing)

            HStack(alignment: .top, spacing: 5) {
                Circle()
                    .fill(.red)
                    .frame(width: 4, height: 4)
                    .padding(.top, scale.footnote * 0.4)

                VStack(alignment: .leading, spacing: 1) {
                    Text(footnote.title)
                        .font(.system(size: scale.footnote, weight: .medium))
                        .lineLimit(1)

                    if let recoveryText = footnote.recoveryText() {
                        Text(recoveryText)
                            .font(.system(size: scale.footnote))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(footnote.accessibilityLabel)
    }
}
