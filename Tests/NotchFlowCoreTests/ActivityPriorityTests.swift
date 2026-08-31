import Foundation
import Testing

@testable import NotchFlowCore

@Suite("Priority")
struct ActivityPriorityTests {
    @Test("sorts all priority levels from highest to lowest")
    func allPriorityLevels() {
        let priorities: [ActivityPriority] = [.normal, .low, .critical, .high]

        #expect(priorities.sorted() == [.critical, .high, .normal, .low])
    }

    @Test("orders older activities first when priorities match")
    func startTimeTieBreaker() {
        let earlier = ActivityOrderingKey(priority: .normal, startTime: date(1))
        let later = ActivityOrderingKey(priority: .normal, startTime: date(2))

        #expect([later, earlier].sorted() == [earlier, later])
    }

    @Test("priority outranks start time")
    func priorityBeforeStartTime() {
        let olderLow = ActivityOrderingKey(priority: .low, startTime: date(1))
        let newerCritical = ActivityOrderingKey(priority: .critical, startTime: date(2))

        #expect([olderLow, newerCritical].sorted() == [newerCritical, olderLow])
    }

    @Test("sorting is total and stable across repeated sorts")
    func repeatedSorts() {
        let expected = [
            ActivityOrderingKey(priority: .critical, startTime: date(4)),
            ActivityOrderingKey(priority: .high, startTime: date(1)),
            ActivityOrderingKey(priority: .high, startTime: date(3)),
            ActivityOrderingKey(priority: .normal, startTime: date(2)),
            ActivityOrderingKey(priority: .low, startTime: date(0)),
        ]
        let input = [expected[3], expected[2], expected[4], expected[0], expected[1]]

        let sortedOnce = input.sorted()
        let sortedAgain = sortedOnce.sorted()

        #expect(sortedOnce == expected)
        #expect(sortedAgain == sortedOnce)
        for left in expected {
            for right in expected {
                #expect(left <= right || right <= left)
            }
        }
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }
}
