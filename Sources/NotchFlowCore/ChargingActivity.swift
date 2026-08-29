import Foundation

/// Where the machine sits in the charging story the island tells, per the state
/// machine in `docs/06-activity-providers.md`.
///
/// Three states, and deliberately no fourth for "on battery": running on
/// battery is the *absence* of this activity, not a state of it, which is the
/// same teardown rule the recording indicators follow. A `.onBattery` case
/// would be an activity describing absence — and an island element that is
/// always present is exactly the persistent power display this provider exists
/// to avoid.
public enum ChargingState: Hashable, CaseIterable, Sendable {
    /// Power is connected but the system is not reporting a charge in progress —
    /// the instant after the cable goes in, and the state a machine sits in when
    /// it is plugged in but holding at its current level.
    case pluggedIn
    /// The system reports the battery is filling.
    case charging
    /// The system reports the battery is full.
    case fullyCharged
}

/// The charging transition, as a dismissible notification rather than a readout.
///
/// The type carries a state and nothing else, and that omission is the feature.
/// `docs/06-activity-providers.md` forbids displaying a persistent battery
/// percentage: an island element that continuously reports a number is precisely
/// the low-value permanent display the whole app is designed against. Enforcing
/// that as a rendering convention would leave the number one careless view away;
/// enforcing it structurally — by never carrying a capacity for a view to reach
/// for — means no view can render one, and the provider never has a reason to
/// read the capacity key at all.
///
/// Every state auto-dismisses, not just the terminal one. A `charging` state
/// that stayed until the battery filled would be a persistent power display in
/// all but digits, and the state machine's whole shape is transition →
/// notification → gone.
public struct ChargingActivity: Activity, Equatable {
    /// How long a charging transition stays on screen before the manager ends
    /// it. Long enough to read at a glance, short enough that the island is
    /// empty again before it becomes furniture.
    public static let autoDismissAfter: Duration = .seconds(4)

    public let state: ChargingState

    public init(state: ChargingState) {
        self.state = state
    }

    /// One identity for the whole state machine, so `charging` becoming
    /// `fullyCharged` updates the element already on screen instead of adding a
    /// second one beside it. The three states are three readings of one fact,
    /// and two of them are never true at once.
    public var identity: ActivityIdentity {
        ActivityIdentity("notchflow.charging")
    }

    public var kind: ActivityKind { .charging }

    /// `normal`, per the V1 priority table in `docs/05-activity-model.md`.
    public var priority: ActivityPriority { .normal }

    /// The manager owns the dismiss timer — per the auto-dismiss row of that
    /// same table, an `update()` restarts the window, so a `fullyCharged` update
    /// arriving during the `charging` window is read in full rather than cut
    /// short by the earlier state's countdown.
    public var autoDismiss: AutoDismissDescriptor? {
        AutoDismissDescriptor(after: Self.autoDismissAfter)
    }
}
