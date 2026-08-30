import Foundation

/// The four screens `docs/08-settings-and-localization.md` specifies for first
/// run, in order.
public enum OnboardingStep: Int, CaseIterable, Comparable, Equatable, Hashable, Sendable {
    case welcome
    case permissions
    case agents
    case done

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The first-run sequence's state: where the user is, and which hook offers they
/// have explicitly accepted.
///
/// The flow holds the accepted set rather than installing as it goes because the
/// acceptance criterion is that onboarding never requests a permission the user
/// has not opted into. `acceptedHookOffers` starts empty and only an explicit
/// `setHookOffer(_:accepted:)` puts an agent in it, so a user who clicks through
/// or skips reaches `done` with nothing to install — there is no path where the
/// composition root can be handed work the user did not ask for.
///
/// Detection is supplied, not performed here: `NotchFlowCore` has no file
/// system seam, and the same list drives both this model and the screen.
public struct OnboardingFlow: Equatable, Sendable {
    /// The agents whose configuration files were found, and so the only ones
    /// worth offering a hook for.
    public let detectedAgents: [IPCAgentID]

    public private(set) var step: OnboardingStep
    public private(set) var isComplete: Bool
    private var acceptedAgents: Set<IPCAgentID>

    public init(detectedAgents: [IPCAgentID] = []) {
        self.detectedAgents = detectedAgents
        step = .welcome
        isComplete = false
        acceptedAgents = []
    }

    /// The hook installations the composition root should run once the flow
    /// finishes — exactly the offers the user accepted, in detection order.
    public var acceptedHookOffers: [IPCAgentID] {
        detectedAgents.filter(acceptedAgents.contains)
    }

    public var canGoBack: Bool {
        !isComplete && step != .welcome
    }

    /// True on the closing screen, where the button reads "Done" rather than
    /// "Continue" — the one place `advance()` ends the flow instead of moving.
    public var isOnFinalStep: Bool {
        step == .done
    }

    public func isAccepted(_ agentID: IPCAgentID) -> Bool {
        acceptedAgents.contains(agentID)
    }

    /// Records a hook offer decision. Declining is a real, recorded answer
    /// rather than a no-op, so a user who accepts and then changes their mind
    /// before finishing is not silently installed for.
    public mutating func setHookOffer(_ agentID: IPCAgentID, accepted: Bool) {
        guard detectedAgents.contains(agentID) else { return }
        if accepted {
            acceptedAgents.insert(agentID)
        } else {
            acceptedAgents.remove(agentID)
        }
    }

    /// Moves to the next step, or completes the flow when already on the last
    /// one. Declining a step does not block this — every screen advances.
    public mutating func advance() {
        guard !isComplete else { return }
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            isComplete = true
            return
        }
        step = next
    }

    public mutating func goBack() {
        guard canGoBack, let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Abandons the sequence from any step. Skipping completes onboarding — the
    /// flag is set either way, because the documented rule is that onboarding
    /// never runs a second time, not that it runs until finished.
    ///
    /// It clears accepted offers on the way out: a user who accepted a hook and
    /// then skipped out of the flow did not confirm that decision, and the
    /// safe reading of an abandoned flow is that nothing was agreed to.
    public mutating func skip() {
        acceptedAgents.removeAll()
        step = .done
        isComplete = true
    }
}
