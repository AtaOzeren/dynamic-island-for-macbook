import Foundation

/// The five event classes `docs/08-settings-and-localization.md` gives the user
/// a switch for, named after the switch rather than after the state it gates.
///
/// The settings table speaks in events ("task started") while the wire protocol
/// speaks in states (`thinking`); this enum is the one place that translation
/// lives, so the settings pane never has to name a state and the state machine
/// never has to name a setting.
public enum AIEventClass: String, CaseIterable, Equatable, Hashable, Sendable {
    case taskStarted
    case taskCompleted
    case taskError
    case needsInput
    case toolActivity

    /// The persistence key from the settings table, so the store landing in
    /// todo 59 can read it from the case rather than from a second list that has
    /// to be kept in step with this one.
    public var settingsKeyPath: String {
        "ai.events.\(rawValue)"
    }

    /// What the settings pane calls the switch, kept beside `IPCAgentID`'s own
    /// `displayName` so both halves of the AI Integrations pane get their labels
    /// from the same layer.
    public var displayName: String {
        switch self {
        case .taskStarted: localized("Task started")
        case .taskCompleted: localized("Task completed")
        case .taskError: localized("Task error")
        case .needsInput: localized("Needs input")
        case .toolActivity: localized("Tool activity")
        }
    }
}

public extension AIAgentState {
    /// The event class a user switch can silence this state through, or `nil`
    /// when no documented switch names it.
    ///
    /// `working` and `idle` return `nil` deliberately: the settings table gives
    /// neither a toggle, and inventing one here would let a user silence the
    /// state that *ends* an activity, stranding a stale agent card in the notch.
    var eventClass: AIEventClass? {
        switch self {
        case .thinking: .taskStarted
        case .completed: .taskCompleted
        case .error: .taskError
        case .waitingForUser: .needsInput
        case .usingTool: .toolActivity
        case .working, .idle: nil
        }
    }
}
