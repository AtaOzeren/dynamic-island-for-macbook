/// A system event that invalidates the current display selection or notch geometry.
public enum ScreenChangeEvent: Equatable, Sendable {
    /// A display was connected, disconnected, rearranged, or changed resolution.
    /// Clamshell open and close surface here too, because the built-in display
    /// leaves and re-enters the screen set.
    case screenParametersChanged
    /// The system is about to sleep; the panel is ordered out before the transition.
    case systemWillSleep
    /// The system woke; the selected display must be re-validated before showing anything.
    case systemDidWake
}

/// A snapshot of the screen set at the moment a `ScreenChangeEvent` was delivered,
/// shaped for `selectDisplay(from:preference:)`.
public struct ScreenChange: Equatable, Sendable {
    public let event: ScreenChangeEvent
    public let displays: [DisplayDescription]

    public init(event: ScreenChangeEvent, displays: [DisplayDescription]) {
        self.event = event
        self.displays = displays
    }
}

public typealias ScreenChangeObserver = @MainActor (ScreenChange) -> Void

/// The seam between the display-selection policy and the system notifications that
/// drive it. Production wraps `NotificationCenter`; tests substitute a fake that
/// emits on the test's own schedule.
@MainActor
public protocol ScreenChangeObserving: AnyObject {
    func startObserving(_ observer: @escaping ScreenChangeObserver)
    func stopObserving()
}
