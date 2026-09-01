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
