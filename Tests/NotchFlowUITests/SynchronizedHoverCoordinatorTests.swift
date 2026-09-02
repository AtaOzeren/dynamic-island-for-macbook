import Foundation
import Testing

@testable import NotchFlowUI

@Suite("SynchronizedHoverCoordinator")
@MainActor
struct SynchronizedHoverCoordinatorTests {
    @Test("expands every island only after the shared hover delay")
    func expandsAfterSharedDelay() {
        let scheduler = FakeHoverExpansionDelayScheduler()
        let coordinator = SynchronizedHoverCoordinator(scheduler: scheduler)
        var changes: [Bool] = []
        coordinator.onExpansionChange = { changes.append($0) }
        coordinator.updateExpansionAvailability(true)

        coordinator.setHovered(true, sourceID: "primary")

        #expect(changes.isEmpty)
        scheduler.fire()
        #expect(changes == [true])
        #expect(coordinator.isExpanded)
    }

    @Test("activity refreshes do not restart an in-flight hover delay")
    func activityRefreshDoesNotRestartHoverDelay() {
        let scheduler = FakeHoverExpansionDelayScheduler()
        let coordinator = SynchronizedHoverCoordinator(scheduler: scheduler)
        coordinator.updateExpansionAvailability(true)
        coordinator.setHovered(true, sourceID: "primary")

        coordinator.updateExpansionAvailability(true)
        coordinator.updateExpansionAvailability(true)

        #expect(scheduler.scheduleCount == 1)
    }

    @Test("one remote island cannot collapse the island under the pointer")
    func unhoveredFollowerDoesNotCollapseTheGroup() {
        let scheduler = FakeHoverExpansionDelayScheduler()
        let coordinator = SynchronizedHoverCoordinator(scheduler: scheduler)
        var changes: [Bool] = []
        coordinator.onExpansionChange = { changes.append($0) }
        coordinator.updateExpansionAvailability(true)
        coordinator.setHovered(true, sourceID: "primary")
        coordinator.setHovered(false, sourceID: "secondary")
        scheduler.fire()

        coordinator.resolvePendingCollapse()

        #expect(changes == [true])
        #expect(coordinator.isExpanded)
    }

    @Test("moving between displays keeps both islands expanded")
    func displayHandoffDoesNotFlickerClosed() {
        let scheduler = FakeHoverExpansionDelayScheduler()
        let coordinator = SynchronizedHoverCoordinator(scheduler: scheduler)
        var changes: [Bool] = []
        coordinator.onExpansionChange = { changes.append($0) }
        coordinator.updateExpansionAvailability(true)
        coordinator.setHovered(true, sourceID: "primary")
        scheduler.fire()

        coordinator.setHovered(false, sourceID: "primary")
        coordinator.setHovered(true, sourceID: "secondary")
        coordinator.resolvePendingCollapse()

        #expect(changes == [true])
        #expect(coordinator.isExpanded)
    }

    @Test("leaving every display collapses the shared island")
    func leavingEveryDisplayCollapsesTheGroup() {
        let scheduler = FakeHoverExpansionDelayScheduler()
        let coordinator = SynchronizedHoverCoordinator(scheduler: scheduler)
        var changes: [Bool] = []
        coordinator.onExpansionChange = { changes.append($0) }
        coordinator.updateExpansionAvailability(true)
        coordinator.setHovered(true, sourceID: "primary")
        scheduler.fire()

        coordinator.setHovered(false, sourceID: "primary")
        coordinator.resolvePendingCollapse()

        #expect(changes == [true, false])
        #expect(coordinator.isExpanded == false)
    }

    @Test("an empty island never expands")
    func emptyIslandNeverExpands() {
        let scheduler = FakeHoverExpansionDelayScheduler()
        let coordinator = SynchronizedHoverCoordinator(scheduler: scheduler)
        var changes: [Bool] = []
        coordinator.onExpansionChange = { changes.append($0) }

        coordinator.setHovered(true, sourceID: "primary")
        scheduler.fire()

        #expect(changes.isEmpty)
        #expect(coordinator.isExpanded == false)
    }

    // MARK: - The grace period after the pointer leaves

    /// The panel is a target the pointer travels to, and the path from the notch
    /// to a row crosses the island's own edge. Collapsing the instant the
    /// pointer slipped off meant a hand that overshot had to start over.
    @Test("leaving does not collapse the island until the grace period elapses")
    func leavingHoldsTheIslandOpenBriefly() {
        let scheduler = FakeHoverExpansionDelayScheduler()
        let coordinator = SynchronizedHoverCoordinator(scheduler: scheduler)
        coordinator.updateExpansionAvailability(true)
        coordinator.setHovered(true, sourceID: "primary")
        scheduler.fire()

        coordinator.setHovered(false, sourceID: "primary")

        #expect(coordinator.isExpanded, "the island collapsed before its grace period")
    }

    /// Coming back inside the grace period must be a no-op, not a collapse
    /// followed by a fresh expansion — that flicker is the thing the delay
    /// exists to prevent, and reintroducing it here would be worse than having
    /// no delay at all.
    @Test("returning within the grace period never closes and reopens the island")
    func returningWithinTheGracePeriodDoesNotFlicker() {
        let scheduler = FakeHoverExpansionDelayScheduler()
        let coordinator = SynchronizedHoverCoordinator(scheduler: scheduler)
        var changes: [Bool] = []
        coordinator.onExpansionChange = { changes.append($0) }
        coordinator.updateExpansionAvailability(true)
        coordinator.setHovered(true, sourceID: "primary")
        scheduler.fire()

        coordinator.setHovered(false, sourceID: "primary")
        coordinator.setHovered(true, sourceID: "primary")
        // Whatever the pending collapse would have done, it must find the
        // pointer back inside and leave the island alone.
        coordinator.resolvePendingCollapse()

        #expect(coordinator.isExpanded)
        #expect(changes == [true], "the island closed and reopened instead of staying put")
    }

    /// The grace period is a delay, not a reprieve: a pointer that stays away
    /// still collapses the island.
    @Test("staying away collapses the island once the grace period resolves")
    func stayingAwayStillCollapses() {
        let scheduler = FakeHoverExpansionDelayScheduler()
        let coordinator = SynchronizedHoverCoordinator(scheduler: scheduler)
        coordinator.updateExpansionAvailability(true)
        coordinator.setHovered(true, sourceID: "primary")
        scheduler.fire()

        coordinator.setHovered(false, sourceID: "primary")
        coordinator.resolvePendingCollapse()

        #expect(coordinator.isExpanded == false)
    }

    /// Losing the last activity is not an overshoot — there is nothing left to
    /// come back to, so the island closes at once rather than holding an empty
    /// surface open for half a second.
    @Test("an emptied island collapses without waiting")
    func anEmptiedIslandCollapsesAtOnce() {
        let scheduler = FakeHoverExpansionDelayScheduler()
        let coordinator = SynchronizedHoverCoordinator(scheduler: scheduler)
        coordinator.updateExpansionAvailability(true)
        coordinator.setHovered(true, sourceID: "primary")
        scheduler.fire()

        coordinator.updateExpansionAvailability(false)

        #expect(coordinator.isExpanded == false)
    }
}

@MainActor
private final class FakeHoverExpansionDelayScheduler: HoverExpansionDelayScheduling {
    private var action: (@MainActor () -> Void)?
    private(set) var scheduleCount = 0

    func schedule(after _: TimeInterval, action: @escaping @MainActor () -> Void) {
        scheduleCount += 1
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func fire() {
        let action = action
        self.action = nil
        action?()
    }
}
