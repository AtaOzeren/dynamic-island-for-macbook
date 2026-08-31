import Foundation
import Testing

@testable import NotchFlowCore

@Suite("ActivityManager")
@MainActor
struct ActivityManagerTests {
    @Test("registers an activity into the active set")
    func registerActivity() {
        let manager = ActivityManager()
        let activity = StubManagerActivity(
            identity: ActivityIdentity("music.playing"),
            kind: .music,
            priority: .low
        )

        manager.register(activity, at: date(1))

        #expect(manager.activeActivities.count == 1)
        #expect(manager.activeActivities.first?.identity == ActivityIdentity("music.playing"))
    }

    @Test("deduplicates activities by identity upon registration")
    func deduplicateByIdentity() {
        let manager = ActivityManager()
        let olderPeer = StubManagerActivity(
            identity: ActivityIdentity("timer.break"),
            kind: .timer,
            priority: .normal
        )
        let initialActivity = StubManagerActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .normal
        )
        let updatedActivity = StubManagerActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .normal
        )

        manager.register(olderPeer, at: date(1))
        manager.register(initialActivity, at: date(2))
        manager.register(updatedActivity, at: date(3))

        #expect(manager.activeActivities.count == 2)
        #expect(manager.activeActivities.map(\.identity) == [olderPeer.identity, updatedActivity.identity])
    }

    @Test("updates an existing activity in place")
    func updateInPlace() {
        let manager = ActivityManager()
        let activity = StubManagerActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .high
        )

        manager.register(activity, at: date(1))

        let updatedActivity = StubManagerActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .critical
        )
        manager.update(updatedActivity, at: date(2))

        #expect(manager.activeActivities.count == 1)
        #expect(manager.activeActivities.first?.priority == .critical)
    }

    @Test("removes an activity when ended")
    func removeOnEnd() {
        let manager = ActivityManager()
        let activity = StubManagerActivity(
            identity: ActivityIdentity("file.transfer"),
            kind: .fileTransfer,
            priority: .normal
        )

        manager.register(activity, at: date(1))
        manager.end(activity.identity, at: date(2))

        #expect(manager.activeActivities.isEmpty)
    }

    @Test("orders active activities by priority and start time")
    func orderingByPriorityAndStartTime() {
        let manager = ActivityManager()
        let music = StubManagerActivity(
            identity: ActivityIdentity("music.track"),
            kind: .music,
            priority: .low
        )
        let transfer = StubManagerActivity(
            identity: ActivityIdentity("file.copy"),
            kind: .fileTransfer,
            priority: .normal
        )
        let timer = StubManagerActivity(
            identity: ActivityIdentity("timer.pomodoro"),
            kind: .timer,
            priority: .high
        )

        manager.register(music, at: date(1))
        manager.register(transfer, at: date(2))
        manager.register(timer, at: date(3))

        let identities = manager.activeActivities.map(\.identity)
        #expect(
            identities == [
                ActivityIdentity("timer.pomodoro"),
                ActivityIdentity("file.copy"),
                ActivityIdentity("music.track"),
            ])
    }

    @Test("enforces compact slot limit and reports overflow count")
    func compactSlotLimitAndOverflow() {
        let manager = ActivityManager(compactCapacity: 2)
        let first = StubManagerActivity(
            identity: ActivityIdentity("act.1"),
            kind: .timer,
            priority: .high
        )
        let second = StubManagerActivity(
            identity: ActivityIdentity("act.2"),
            kind: .fileTransfer,
            priority: .normal
        )
        let third = StubManagerActivity(
            identity: ActivityIdentity("act.3"),
            kind: .music,
            priority: .low
        )

        manager.register(first, at: date(1))
        manager.register(second, at: date(2))
        manager.register(third, at: date(3))

        #expect(manager.compactPresentation.activities.count == 1)
        #expect(manager.compactPresentation.overflowCount == 2)
        #expect(manager.expandedActivities.count == 3)
    }

    @Test("fires auto-dismiss when expiration condition is reached")
    func autoDismissFiring() async {
        let manager = ActivityManager(sleep: { _ in })
        let autoDismissActivity = StubManagerActivity(
            identity: ActivityIdentity("charging.status"),
            kind: .charging,
            priority: .normal,
            autoDismiss: AutoDismissDescriptor(after: .seconds(5))
        )

        manager.register(autoDismissActivity, at: date(1))
        await Task.yield()
        await Task.yield()

        #expect(manager.activeActivities.isEmpty)
    }

    @Test("emits idle signal exactly once when transitioning to empty")
    func idleSignalOnEmptying() {
        let manager = ActivityManager()
        var idleSignalCount = 0
        manager.onBecomeIdle = {
            idleSignalCount += 1
        }

        let first = StubManagerActivity(
            identity: ActivityIdentity("act.1"),
            kind: .timer,
            priority: .high
        )
        let second = StubManagerActivity(
            identity: ActivityIdentity("act.2"),
            kind: .music,
            priority: .low
        )

        manager.register(first, at: date(1))
        manager.register(second, at: date(2))

        manager.end(first.identity, at: date(3))
        #expect(idleSignalCount == 0)

        manager.end(second.identity, at: date(4))
        #expect(idleSignalCount == 1)

        manager.end(ActivityIdentity("non-existent"), at: date(5))
        #expect(idleSignalCount == 1)
    }

    @Test("signals every change to the active set")
    func changeSignalOnEveryMutation() {
        let manager = ActivityManager()
        var changeSignalCount = 0
        manager.onActivitiesChanged = {
            changeSignalCount += 1
        }

        let activity = StubManagerActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .normal
        )

        manager.register(activity, at: date(1))
        #expect(changeSignalCount == 1)

        manager.update(activity, at: date(2))
        #expect(changeSignalCount == 2)

        manager.end(activity.identity, at: date(3))
        #expect(changeSignalCount == 3)

        manager.end(ActivityIdentity("non-existent"), at: date(4))
        #expect(changeSignalCount == 3)
    }

    @Test("multiple presentation observers receive changes independently")
    func multipleChangeObservers() {
        let manager = ActivityManager()
        var firstCount = 0
        var secondCount = 0
        let firstID = manager.observeActivitiesChanged { firstCount += 1 }
        _ = manager.observeActivitiesChanged { secondCount += 1 }
        let activity = StubManagerActivity(
            identity: ActivityIdentity("timer.multi-display"),
            kind: .timer,
            priority: .normal
        )

        manager.register(activity, at: date(1))
        #expect(firstCount == 1)
        #expect(secondCount == 1)

        manager.removeActivitiesObserver(firstID)
        manager.end(activity.identity, at: date(2))
        #expect(firstCount == 1)
        #expect(secondCount == 2)
    }
}

private struct StubManagerActivity: Activity {
    let identity: ActivityIdentity
    let kind: ActivityKind
    let priority: ActivityPriority
    let autoDismiss: AutoDismissDescriptor?

    init(
        identity: ActivityIdentity,
        kind: ActivityKind,
        priority: ActivityPriority,
        autoDismiss: AutoDismissDescriptor? = nil
    ) {
        self.identity = identity
        self.kind = kind
        self.priority = priority
        self.autoDismiss = autoDismiss
    }
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}
