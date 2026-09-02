import Foundation

@MainActor
public protocol HoverExpansionDelayScheduling: AnyObject {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
public final class TimerHoverExpansionDelayScheduler: HoverExpansionDelayScheduling {
    private var timer: Timer?

    public init() {}

    public func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                action()
            }
        }
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

/// Combines local hover answers from every display into one expansion state.
/// One physical pointer can only be over one island at a time; followers must
/// therefore stay expanded while any source remains hovered.
@MainActor
public final class SynchronizedHoverCoordinator {
    private let delay: TimeInterval
    private let collapseGrace: TimeInterval
    private let scheduler: any HoverExpansionDelayScheduling
    private var hoverBySource: [String: Bool] = [:]
    private var canExpand = false
    private var isExpansionScheduled = false
    private var pendingCollapse: Task<Void, Never>?

    public private(set) var isExpanded = false
    public var onExpansionChange: ((Bool) -> Void)?

    public init(
        motion: IslandMotion = .default,
        scheduler: any HoverExpansionDelayScheduling = TimerHoverExpansionDelayScheduler()
    ) {
        delay = motion.hoverExpansionDelay
        collapseGrace = motion.hoverCollapseGrace
        self.scheduler = scheduler
    }

    public func updateExpansionAvailability(_ canExpand: Bool) {
        self.canExpand = canExpand
        guard canExpand else {
            cancelScheduledExpansion()
            setExpanded(false)
            return
        }
        scheduleExpansionIfNeeded()
    }

    public func setHovered(_ isHovered: Bool, sourceID: String) {
        hoverBySource[sourceID] = isHovered

        if hoverBySource.values.contains(true) {
            pendingCollapse?.cancel()
            pendingCollapse = nil
            scheduleExpansionIfNeeded()
        } else {
            cancelScheduledExpansion()
            scheduleCollapseReconciliation()
        }
    }

    public func removeSource(_ sourceID: String) {
        hoverBySource.removeValue(forKey: sourceID)
        guard hoverBySource.values.contains(true) == false else { return }
        cancelScheduledExpansion()
        scheduleCollapseReconciliation()
    }

    public func expandNow() {
        guard canExpand else { return }
        cancelScheduledExpansion()
        setExpanded(true)
    }

    public func collapseNow() {
        cancelScheduledExpansion()
        pendingCollapse?.cancel()
        pendingCollapse = nil
        setExpanded(false)
    }

    /// Internal seam for deterministic tests; production calls it once the grace
    /// period has elapsed, which also gives every display's observer time to
    /// finish reporting the same mouse event.
    func resolvePendingCollapse() {
        pendingCollapse = nil
        guard hoverBySource.values.contains(true) == false else { return }
        setExpanded(false)
    }

    private func scheduleExpansionIfNeeded() {
        guard
            canExpand,
            isExpanded == false,
            isExpansionScheduled == false,
            hoverBySource.values.contains(true)
        else { return }
        isExpansionScheduled = true
        scheduler.schedule(after: delay) { [weak self] in
            self?.isExpansionScheduled = false
            guard
                let self,
                self.canExpand,
                self.hoverBySource.values.contains(true)
            else { return }
            self.setExpanded(true)
        }
    }

    private func cancelScheduledExpansion() {
        scheduler.cancel()
        isExpansionScheduled = false
    }

    /// Holds the island open for a moment after the pointer leaves.
    ///
    /// Cancelled outright by `setHovered(true, …)`, and the island is still
    /// expanded at that point, so coming back inside the grace period is a
    /// no-op rather than a collapse followed by a fresh expansion — the flicker
    /// the delay exists to prevent, not one it introduces.
    private func scheduleCollapseReconciliation() {
        pendingCollapse?.cancel()
        pendingCollapse = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.collapseGrace))
            guard Task.isCancelled == false else { return }
            self.resolvePendingCollapse()
        }
    }

    private func setExpanded(_ isExpanded: Bool) {
        guard self.isExpanded != isExpanded else { return }
        self.isExpanded = isExpanded
        onExpansionChange?(isExpanded)
    }
}
