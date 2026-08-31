import Foundation

/// The user's AI Integrations choices, as one value the receivers can consult.
///
/// Both transports — the URL scheme and the loopback listener — must apply the
/// same rule, and `docs/07-ai-integration.md` requires the drop happen before an
/// activity exists rather than at render time. Keeping the rule in one `allows`
/// method is what makes "disabled events are dropped at the receiver" a single
/// invariant instead of two implementations that can drift apart.
public struct AIIntegrationPreferences: Equatable, Sendable {
    /// Every agent off and `toolActivity` off, the two deliberately conservative
    /// defaults called out in `docs/08-settings-and-localization.md`.
    public static let `default` = AIIntegrationPreferences()

    public var enabledAgentIDs: Set<IPCAgentID>
    public var enabledEventClasses: Set<AIEventClass>

    public init(
        enabledAgentIDs: Set<IPCAgentID> = [],
        enabledEventClasses: Set<AIEventClass> = [
            .taskStarted, .taskCompleted, .taskError, .needsInput,
        ]
    ) {
        self.enabledAgentIDs = enabledAgentIDs
        self.enabledEventClasses = enabledEventClasses
    }

    public func isEnabled(_ agentID: IPCAgentID) -> Bool {
        enabledAgentIDs.contains(agentID)
    }

    public func isEnabled(_ eventClass: AIEventClass) -> Bool {
        enabledEventClasses.contains(eventClass)
    }

    /// Whether this message may become an activity.
    ///
    /// A state with no event class — `working`, `idle` — passes the event gate
    /// unconditionally: `idle` ends an activity, and silencing the end of one
    /// would leave a stale agent card on screen forever.
    public func allows(_ message: IPCMessage) -> Bool {
        guard isEnabled(message.agentId) else {
            return false
        }
        guard let eventClass = message.state.eventClass else {
            return true
        }
        return isEnabled(eventClass)
    }

    public mutating func setAgent(_ agentID: IPCAgentID, enabled: Bool) {
        if enabled {
            enabledAgentIDs.insert(agentID)
        } else {
            enabledAgentIDs.remove(agentID)
        }
    }

    public mutating func setEventClass(_ eventClass: AIEventClass, enabled: Bool) {
        if enabled {
            enabledEventClasses.insert(eventClass)
        } else {
            enabledEventClasses.remove(eventClass)
        }
    }
}
