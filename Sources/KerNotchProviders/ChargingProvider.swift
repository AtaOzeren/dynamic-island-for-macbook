import Foundation
import KerNotchCore

/// One reading of the internal battery: what is happening to the power, and how
/// full the battery is.
public struct PowerSourceReading: Equatable, Sendable {
    public let state: ChargingState
    public let level: BatteryLevel

    public init(state: ChargingState, level: BatteryLevel) {
        self.state = state
        self.level = level
    }
}

/// Called with the battery's reading each time the system reports a change.
public typealias PowerSourceReadingObserver = @MainActor (PowerSourceReading) -> Void

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
    func startObserving(_ observer: @escaping PowerSourceReadingObserver)
    func stopObserving()
}

/// Called with each charging notification to announce. There is no teardown
/// emission: every notification is ended by its own auto-dismiss window.
public typealias ChargingActivityObserver = @MainActor (ChargingActivity) -> Void

/// Turns the system's power-source notifications into the plug-in and unplug
/// notifications the manager registers, per `docs/06-activity-providers.md`.
///
/// Only the cable announces. The IOKit source fires on every power-source
/// change, and while a Mac is connected those changes never stop: a charge
/// limit or optimised charging pauses and resumes the charge again and again,
/// and the battery reports full and not-full as it tops up. Announcing each of
/// those reopened the island all through a charge, alternating a charging
/// battery with a plugged-in one for no reason the user could see.
///
/// The one exception is the notification already on screen. The charge usually
/// starts a moment after the cable goes in, so a change inside the announcement
/// window refines the notification rather than leaving it without its bolt.
///
/// The first reading after observation starts is only a baseline. A Mac already
/// plugged in when KerNotch launches, or when the user switches the provider
/// back on, did not just have its cable plugged in.
///
/// The provider owns no timer. `ActivityManager` dismisses the notification, and
/// the announcement window is measured against the clock only when a reading
/// arrives.
@MainActor
public final class ChargingProvider {
    private let source: any PowerSourceObserving
    private let now: () -> Date
    private var observer: ChargingActivityObserver?
    private var lastReading: PowerSourceReading?
    private var announcementStart: Date?

    public init(
        source: any PowerSourceObserving,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.now = now
    }

    public func startObserving(_ observer: @escaping ChargingActivityObserver) {
        self.observer = observer
        source.startObserving { [weak self] reading in
            self?.apply(reading)
        }
    }

    /// Forgetting the last reading is part of stopping: a provider restarted
    /// into the power state it was stopped in must treat it as a new baseline
    /// rather than compare it with a reading from before anyone was listening.
    public func stopObserving() {
        observer = nil
        lastReading = nil
        announcementStart = nil
        source.stopObserving()
    }

    private func apply(_ reading: PowerSourceReading) {
        let previous = lastReading
        lastReading = reading
        guard let previous else { return }

        if reading.state.isConnectedToPower != previous.state.isConnectedToPower {
            announcementStart = now()
            announce(reading)
        } else if reading.state != previous.state, isAnnouncing {
            announce(reading)
        }
    }

    /// Whether the last plug-in or unplug is still on screen. Measured from the
    /// cable's edge, not from the last refinement, so a charge flickering in its
    /// first seconds cannot hold the notification open.
    private var isAnnouncing: Bool {
        guard let announcementStart else { return false }
        return now().timeIntervalSince(announcementStart) < Self.announcementWindow
    }

    private static let announcementWindow: TimeInterval = {
        let parts = ChargingActivity.autoDismissAfter.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }()

    private func announce(_ reading: PowerSourceReading) {
        observer?(ChargingActivity(state: reading.state, level: reading.level))
    }
}
