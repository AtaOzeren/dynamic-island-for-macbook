import Foundation

/// The power situation the island announces, per the state machine in
/// `docs/06-activity-providers.md`.
public enum ChargingState: Hashable, CaseIterable, Sendable {
    /// The charger came out and the machine runs on its battery.
    case onBattery
    /// Power is connected but the battery is not filling: the instant after the
    /// cable goes in, and a machine holding at its charge limit.
    case pluggedIn
    /// The system reports the battery is filling.
    case charging
    /// The system reports the battery is full.
    case fullyCharged

    public var isConnectedToPower: Bool { self != .onBattery }
}

/// How full the battery is, as a fraction of its capacity.
public struct BatteryLevel: Hashable, Sendable {
    public let fraction: Double

    /// Clamped to `0...1`, and a reading that is not a number reads as empty
    /// rather than as a battery drawn past its own outline.
    public init(fraction: Double) {
        self.fraction = fraction.isNaN ? 0 : min(max(fraction, 0), 1)
    }
}

/// The charger going in or coming out, as a notification rather than a readout.
///
/// The level travels with it so the glyph can show how full the battery is, the
/// way the menu bar's battery does — drawn, never written as a number, and only
/// for the few seconds the notification lasts. A level the island kept on
/// screen, or spelled out in digits, would be the persistent power display
/// `docs/06-activity-providers.md` forbids.
///
/// Every state auto-dismisses. The state machine's whole shape is transition →
/// notification → gone.
public struct ChargingActivity: Activity, Equatable {
    /// How long a charging transition stays on screen before the manager ends
    /// it. Long enough to read at a glance, short enough that the island is
    /// empty again before it becomes furniture.
    public static let autoDismissAfter: Duration = .seconds(4)

    public let state: ChargingState
    public let level: BatteryLevel

    public init(state: ChargingState, level: BatteryLevel) {
        self.state = state
        self.level = level
    }

    /// One identity for the whole state machine, so unplugging while the
    /// plug-in notification is still up replaces it instead of adding a second
    /// one beside it. The states are readings of one fact, and two of them are
    /// never true at once.
    public var identity: ActivityIdentity {
        ActivityIdentity("kernotch.charging")
    }

    public var kind: ActivityKind { .charging }

    /// `normal`, per the V1 priority table in `docs/05-activity-model.md`.
    public var priority: ActivityPriority { .normal }

    public var compactRank: CompactRank { .transition }

    /// The manager owns the dismiss timer — per the auto-dismiss row of that
    /// same table, an `update()` restarts the window, so a charge that starts a
    /// moment after the cable goes in is read in full rather than cut short by
    /// the plug-in's countdown.
    public var autoDismiss: AutoDismissDescriptor? {
        AutoDismissDescriptor(after: Self.autoDismissAfter)
    }
}
