import Foundation
import Testing
@testable import NotchFlowCore

@Suite("ActivityLifecycle")
struct ActivityLifecycleTests {
    @Test("preserves activity identity, kind, priority, and auto-dismiss policy")
    func activityDescriptor() {
        let activity = StubActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .high,
            autoDismiss: AutoDismissDescriptor(after: .seconds(5))
        )

        #expect(activity.identity == ActivityIdentity("timer.focus"))
        #expect(activity.kind == .timer)
        #expect(activity.priority == .high)
        #expect(activity.autoDismiss == AutoDismissDescriptor(after: .seconds(5)))
    }

    @Test("drives an activity through start, update, and end")
    func completeLifecycle() {
        var lifecycle = ActivityLifecycle()

        let didStart = lifecycle.apply(.start(at: date(1)))
        let didUpdate = lifecycle.apply(.update(at: date(2)))
        let didEnd = lifecycle.apply(.end(at: date(3)))

        #expect(didStart)
        #expect(didUpdate)
        #expect(didEnd)
        #expect(lifecycle.state == .ended)
    }

    @Test("auto-dismiss expires after the most recent update")
    func autoDismissExpiry() {
        var lifecycle = ActivityLifecycle()
        let descriptor = AutoDismissDescriptor(after: .seconds(5))

        let didStart = lifecycle.apply(.start(at: date(1)))
        let didUpdate = lifecycle.apply(.update(at: date(3)))
        let didExpireEarly = lifecycle.apply(
            .autoDismissExpired(at: date(7), descriptor: descriptor)
        )
        let didExpire = lifecycle.apply(
            .autoDismissExpired(at: date(8), descriptor: descriptor)
        )

        #expect(didStart)
        #expect(didUpdate)
        #expect(!didExpireEarly)
        #expect(didExpire)
        #expect(lifecycle.state == .ended)
    }

    @Test("rejects illegal lifecycle transitions")
    func illegalTransitions() {
        var inactive = ActivityLifecycle()
        let didUpdateInactive = inactive.apply(.update(at: date(1)))
        let didEndInactive = inactive.apply(.end(at: date(1)))

        #expect(!didUpdateInactive)
        #expect(!didEndInactive)

        var active = ActivityLifecycle()
        let didStart = active.apply(.start(at: date(1)))
        let didRestart = active.apply(.start(at: date(2)))
        let didEnd = active.apply(.end(at: date(3)))
        let didUpdateEnded = active.apply(.update(at: date(4)))
        let didEndAgain = active.apply(.end(at: date(4)))

        #expect(didStart)
        #expect(!didRestart)
        #expect(didEnd)
        #expect(!didUpdateEnded)
        #expect(!didEndAgain)
    }

    @Test("rejects auto-dismiss before start and for activities without a policy")
    func invalidAutoDismiss() {
        var lifecycle = ActivityLifecycle()
        let descriptor = AutoDismissDescriptor(after: .seconds(5))

        let didExpireInactive = lifecycle.apply(
            .autoDismissExpired(at: date(5), descriptor: descriptor)
        )
        let didStart = lifecycle.apply(.start(at: date(1)))
        let didExpireWithoutPolicy = lifecycle.apply(
            .autoDismissExpired(at: date(100), descriptor: nil)
        )

        #expect(!didExpireInactive)
        #expect(didStart)
        #expect(!didExpireWithoutPolicy)
        #expect(lifecycle.state == .active)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }
}

private struct StubActivity: Activity {
    let identity: ActivityIdentity
    let kind: ActivityKind
    let priority: ActivityPriority
    let autoDismiss: AutoDismissDescriptor?
}
