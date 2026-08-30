import AppKit
import CoreGraphics
import NotchFlowCore

/// Reports pointer movement from passive `NSEvent` monitors — the push-based
/// alternative `docs/02-performance-contract.md` demands in place of polling
/// `NSEvent.mouseLocation` on a timer.
///
/// Two monitors are needed because a global monitor is deliberately blind to the
/// observing app's own events: once the pill accepts the mouse, movement over it
/// is delivered locally and nowhere else, so watching only globally would strand
/// the pointer inside the pill and never let hover end.
///
/// A global monitor for mouse-moved events needs no Accessibility grant, unlike
/// one for keyboard events — see `docs/09-security-privacy-permissions.md`.
@MainActor
public final class SystemMouseLocationObserver: MouseLocationObserving {
    private static let movement: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
    ]

    private let install: (NSEvent.EventTypeMask, @escaping @MainActor (CGPoint) -> Void) -> [Any]
    private let monitors: MonitorBag

    public convenience init() {
        self.init(
            install: { mask, report in
                var monitors: [Any] = []

                if let global = NSEvent.addGlobalMonitorForEvents(
                    matching: mask,
                    handler: { event in
                        MainActor.assumeIsolated { report(event.locationOnScreen) }
                    })
                {
                    monitors.append(global)
                }

                if let local = NSEvent.addLocalMonitorForEvents(
                    matching: mask,
                    handler: { event in
                        MainActor.assumeIsolated { report(event.locationOnScreen) }
                        return event
                    })
                {
                    monitors.append(local)
                }

                return monitors
            },
            uninstall: NSEvent.removeMonitor
        )
    }

    init(
        install: @escaping (NSEvent.EventTypeMask, @escaping @MainActor (CGPoint) -> Void) -> [Any],
        uninstall: @escaping (Any) -> Void
    ) {
        self.install = install
        self.monitors = MonitorBag(uninstall: uninstall)
    }

    public func startObserving(_ observer: @escaping MouseLocationObserver) {
        stopObserving()
        monitors.add(install(Self.movement) { observer($0) })
    }

    public func stopObserving() {
        monitors.removeAll()
    }
}

/// Owns the monitor tokens so they are released both on `stopObserving` and when
/// the observer itself is deallocated, without a main-actor-isolated `deinit`. A
/// stranded mouse monitor would wake the process on every pointer move, which is
/// exactly the idle cost `docs/02-performance-contract.md` budgets against.
private final class MonitorBag: @unchecked Sendable {
    private let uninstall: (Any) -> Void
    private var monitors: [Any] = []

    init(uninstall: @escaping (Any) -> Void) {
        self.uninstall = uninstall
    }

    func add(_ tokens: [Any]) {
        monitors.append(contentsOf: tokens)
    }

    func removeAll() {
        monitors.forEach(uninstall)
        monitors.removeAll()
    }

    deinit {
        removeAll()
    }
}

extension NSEvent {
    /// Normalizes `NSEvent.locationInWindow` onto global screen coordinates. Local
    /// mouse-moved events are expressed relative to the target window; the
    /// global event carries no window and its location is already global.
    @MainActor
    fileprivate var locationOnScreen: CGPoint {
        window?.convertPoint(toScreen: locationInWindow) ?? locationInWindow
    }
}
