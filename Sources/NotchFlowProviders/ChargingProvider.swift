import Foundation
import NotchFlowCore

/// The machine's power situation as the island cares about it.
///
/// This is deliberately narrower than what IOKit reports: the power-source
/// description carries a current capacity, a maximum capacity, a time-to-empty
/// and more, and none of it appears here. `docs/06-activity-providers.md`
/// forbids displaying a persistent battery percentage, and the cheapest way to
/// keep a number off the island is to never carry it past the boundary that
/// reads it — an absent field cannot leak into a view, and the reduction
/// happens at the one place with access to the raw description.
///
/// `onBattery` exists here but has no counterpart in `ChargingState` for the
/// same reason the recording providers have no not-recording activity: running
/// on battery is the absence of the activity, so this case is what teardown
/// looks like on the way in.
public enum PowerSourceState: Hashable, Sendable {
    case onBattery
    case pluggedIn
    case charging
    case fullyCharged
}

/// Called with the power state each time the system reports a change.
public typealias PowerSourceStateObserver = @MainActor (PowerSourceState) -> Void

/// The seam between "however the system reports power state" and "how that
/// becomes a `ChargingActivity`".
///
/// Split out for the reason `docs/06-activity-providers.md` gives:
/// `IOPSNotificationCreateRunLoopSource` and real plug transitions can only be
/// exercised on hardware with a battery, while the state machine over the
/// resulting sequence is fully testable in CI against a fake source.
/// Conformances are event-driven; one that polls the battery violates the
/// update-cadence rule and `docs/02-performance-contract.md` with it.
@MainActor
public protocol PowerSourceObserving: AnyObject {
    func startObserving(_ observer: @escaping PowerSourceStateObserver)
    func stopObserving()
}

/// Called with the charging activity, or `nil` once power is disconnected —
/// teardown is the absence of an activity rather than an activity describing
/// absence, per the teardown rule in `docs/06-activity-providers.md`.
public typealias ChargingActivityObserver = @MainActor (ChargingActivity?) -> Void

/// Turns the system's power-source notifications into the charging transition
/// the manager registers, per `docs/06-activity-providers.md`.
///
/// The provider owns no timer of any kind. It never counts, so it never needs a
/// wakeup to redraw; and it never dismisses, because `ActivityManager` owns the
/// auto-dismiss window for any activity that declares one. Every emission here
/// is an edge delivered by the underlying observer.
///
/// Its one piece of judgement is refusing to speak when nothing changed. The
/// IOKit source fires on every power-source change, which includes each capacity
/// tick during a charge; since the manager restarts the dismiss window on each
/// `update()`, a provider that forwarded every callback would pin the island
/// open for the whole charge — the persistent power display the design forbids,
/// arrived at sideways. Deduping on the reduced state is what makes the
/// documented auto-dismiss actually reachable.
@MainActor
public final class ChargingProvider {
    private let source: any PowerSourceObserving
    private var observer: ChargingActivityObserver?
    private var activity: ChargingActivity?

    public init(source: any PowerSourceObserving) {
        self.source = source
    }

    public var currentActivity: ChargingActivity? { activity }

    public func startObserving(_ observer: @escaping ChargingActivityObserver) {
        self.observer = observer
        source.startObserving { [weak self] state in
            self?.apply(state)
        }
    }

    /// Forgetting the last activity is part of stopping: a provider restarted
    /// into the power state it was stopped in must report it rather than dedupe
    /// against a reading from before anyone was listening.
    public func stopObserving() {
        observer = nil
        activity = nil
        source.stopObserving()
    }

    /// Deduping on the derived activity rather than on the raw power state is
    /// what keeps a machine that launches on battery — or that reports the same
    /// discharged state twice — from emitting a teardown for an activity that
    /// was never registered. Absence and continued absence are the same
    /// emission, so they must compare equal.
    private func apply(_ state: PowerSourceState) {
        let activity = Self.activity(for: state)
        guard self.activity != activity else { return }

        self.activity = activity
        observer?(activity)
    }

    /// Running on battery has no activity, which is what makes teardown the
    /// absence of one rather than a fourth state describing absence.
    private static func activity(for state: PowerSourceState) -> ChargingActivity? {
        switch state {
        case .onBattery: nil
        case .pluggedIn: ChargingActivity(state: .pluggedIn)
        case .charging: ChargingActivity(state: .charging)
        case .fullyCharged: ChargingActivity(state: .fullyCharged)
        }
    }
}
