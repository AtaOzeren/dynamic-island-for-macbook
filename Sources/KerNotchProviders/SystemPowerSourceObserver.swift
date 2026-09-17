import Foundation
import IOKit.ps
import KerNotchCore

/// Reduces one IOKit power-source description to the reading the island uses.
///
/// Split from the observer because it is pure: a dictionary in, a reading out,
/// with no run loop and no hardware, so the classification that decides what the
/// island says is checkable in CI even though the notification that delivers the
/// dictionary is not.
enum PowerSourceDescription {
    /// `nil` when the description carries no readable charge, rather than a
    /// guessed level drawn as though it were real.
    static func reading(from description: [String: Any]) -> PowerSourceReading? {
        guard let level = level(from: description) else { return nil }
        return PowerSourceReading(state: state(from: description), level: level)
    }

    private static func state(from description: [String: Any]) -> ChargingState {
        let isConnectedToPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue

        guard isConnectedToPower else { return .onBattery }

        // Charged is checked before charging: a machine holding at full reports
        // charged while briefly topping up, and "full" is the more useful of the
        // two answers when both are true.
        if description[kIOPSIsChargedKey] as? Bool == true { return .fullyCharged }
        if description[kIOPSIsChargingKey] as? Bool == true { return .charging }

        return .pluggedIn
    }

    /// The internal battery reports its capacity on a scale of 100, but the
    /// maximum is read rather than assumed.
    private static func level(from description: [String: Any]) -> BatteryLevel? {
        guard let current = description[kIOPSCurrentCapacityKey] as? Int,
            let maximum = description[kIOPSMaxCapacityKey] as? Int,
            maximum > 0
        else {
            return nil
        }
        return BatteryLevel(fraction: Double(current) / Double(maximum))
    }
}

/// The system's own account of the power situation, per row 9 of
/// `docs/12-api-feasibility-matrix.md` — public API, no entitlement, no prompt,
/// and the same mechanism the menu bar battery indicator is built on.
///
/// Nothing here polls. `IOPSNotificationCreateRunLoopSource` delivers a callback
/// on every power-source change, and the blob is read only in response to one;
/// the single unprompted read is at start, which gives the provider the baseline
/// the first real plug-in or unplug is measured against.
///
/// The run loop source is created when observation starts and invalidated when
/// it stops, rather than registered for the life of the process: every provider
/// is startable and stoppable from settings, and a source left running after the
/// user disabled the provider would keep waking the process to compute a state
/// nobody is listening for.
@MainActor
public final class SystemPowerSourceObserver: PowerSourceObserving {
    private let read: @MainActor () -> PowerSourceReading?
    private var observer: PowerSourceReadingObserver?
    private var runLoopSource: CFRunLoopSource?

    public convenience init() {
        self.init(read: { SystemPowerSourceObserver.currentReading() })
    }

    init(read: @escaping @MainActor () -> PowerSourceReading?) {
        self.read = read
    }

    public func startObserving(_ observer: @escaping PowerSourceReadingObserver) {
        stopObserving()
        self.observer = observer

        // The callback is C, so the instance travels as an opaque pointer. It is
        // unretained deliberately: the source is invalidated in `stopObserving`,
        // which `deinit` calls, so the callback cannot outlive the object and a
        // retain here would instead make the object outlive its owner.
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard
            let source = IOPSNotificationCreateRunLoopSource(
                { context in
                    guard let context else { return }
                    let observer = Unmanaged<SystemPowerSourceObserver>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                    MainActor.assumeIsolated { observer.emitCurrentReading() }
                },
                context
            )?.takeRetainedValue()
        else {
            // A machine that will not deliver power notifications gets no
            // charging indicator rather than a polled one, per the
            // no-polling rule in `docs/06-activity-providers.md`.
            return
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        emitCurrentReading()
    }

    public func stopObserving() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            CFRunLoopSourceInvalidate(runLoopSource)
        }

        runLoopSource = nil
        observer = nil
    }

    deinit {
        MainActor.assumeIsolated { stopObserving() }
    }

    /// A Mac without a battery, or a reading IOKit could not give, says nothing:
    /// there is no cable edge to announce on a machine that is always plugged in.
    private func emitCurrentReading() {
        guard let observer, let reading = read() else { return }

        observer(reading)
    }

    /// The internal power source is the only one the island speaks for: a
    /// connected UPS is a real power source to IOKit but not the battery the
    /// user is watching fill.
    private static func currentReading() -> PowerSourceReading? {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        let internalBattery =
            sources
            .compactMap { IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }

        return internalBattery.flatMap(PowerSourceDescription.reading(from:))
    }
}
