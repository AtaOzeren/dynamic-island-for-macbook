import Foundation
import IOKit.ps

/// Reduces one IOKit power-source description to the state the island reports.
///
/// This is the boundary where the battery percentage is dropped, and it is the
/// only place in NotchFlow with access to one. `docs/06-activity-providers.md`
/// forbids displaying a persistent battery percentage, so rather than carrying
/// `kIOPSCurrentCapacityKey` inward and trusting every future view not to draw
/// it, this reads the three keys that answer "what is happening to the power"
/// and never looks the capacity up at all. Nothing downstream can render a
/// number that was never fetched.
///
/// Split from the observer because it is pure: a dictionary in, a state out,
/// with no run loop and no hardware, so the classification that decides what the
/// island says is checkable in CI even though the notification that delivers the
/// dictionary is not.
enum PowerSourceDescription {
    static func state(from description: [String: Any]) -> PowerSourceState {
        let isConnectedToPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue

        guard isConnectedToPower else { return .onBattery }

        // Charged is checked before charging: a machine holding at full reports
        // charged while briefly topping up, and "full" is the more useful of the
        // two answers when both are true.
        if description[kIOPSIsChargedKey] as? Bool == true { return .fullyCharged }
        if description[kIOPSIsChargingKey] as? Bool == true { return .charging }

        return .pluggedIn
    }
}

/// The system's own account of the power situation, per row 9 of
/// `docs/12-api-feasibility-matrix.md` — public API, no entitlement, no prompt,
/// and the same mechanism the menu bar battery indicator is built on.
///
/// Nothing here polls. `IOPSNotificationCreateRunLoopSource` delivers a callback
/// on every power-source change, and the blob is read only in response to one;
/// the single unprompted read is at start, because a machine already plugged in
/// when NotchFlow launches is a real state rather than an edge that was missed.
///
/// The run loop source is created when observation starts and invalidated when
/// it stops, rather than registered for the life of the process as
/// `docs/06-activity-providers.md` describes: todo 49 makes every provider
/// startable and stoppable from settings, and a source left running after the
/// user disabled the provider would keep waking the process to compute a state
/// nobody is listening for.
@MainActor
public final class SystemPowerSourceObserver: PowerSourceObserving {
    private let readState: @MainActor () -> PowerSourceState
    private var observer: PowerSourceStateObserver?
    private var runLoopSource: CFRunLoopSource?

    public convenience init() {
        self.init(readState: { SystemPowerSourceObserver.currentState() })
    }

    init(readState: @escaping @MainActor () -> PowerSourceState) {
        self.readState = readState
    }

    public func startObserving(_ observer: @escaping PowerSourceStateObserver) {
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
                    MainActor.assumeIsolated { observer.emitCurrentState() }
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

        emitCurrentState()
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

    private func emitCurrentState() {
        guard let observer else { return }

        observer(readState())
    }

    /// The internal power source is the only one the island speaks for: a
    /// connected UPS is a real power source to IOKit but not the battery the
    /// user is watching fill.
    private static func currentState() -> PowerSourceState {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return .onBattery
        }

        let internalBattery = sources
            .compactMap { IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }

        guard let internalBattery else { return .onBattery }

        return PowerSourceDescription.state(from: internalBattery)
    }
}
