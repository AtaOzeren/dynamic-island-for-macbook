import CoreGraphics

public typealias MouseLocationObserver = @MainActor (CGPoint) -> Void

/// The seam between hover detection and the system's mouse events. Production
/// wraps a passive `NSEvent` global monitor; tests substitute a fake that emits
/// pointer positions on the test's own schedule.
///
/// The contract is push-only by design: `docs/02-performance-contract.md` forbids
/// polling the pointer on a timer, so an implementation may only emit when the
/// system reports movement, and must emit nothing at all between `stopObserving`
/// and the next `startObserving`.
@MainActor
public protocol MouseLocationObserving: AnyObject {
    func startObserving(_ observer: @escaping MouseLocationObserver)
    func stopObserving()
}
