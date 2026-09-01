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

    // MARK: - Media and capture stay on top

    /// What is playing and what is recording sit above everything else, however
    /// urgent the rest is. Sorting by urgency alone put a finished agent above
    /// the track the user was listening to.
    @Test("the pinned band outranks every priority")
    func pinnedBandOutranksPriority() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let pinnedAndLeastUrgent = ActivityOrderingKey(
            band: .pinned,
            priority: .low,
            startTime: now.addingTimeInterval(1_000)
        )

        for priority in ActivityPriority.allCases {
            let standard = ActivityOrderingKey(
                band: .standard,
                priority: priority,
                startTime: now
            )

            #expect(pinnedAndLeastUrgent < standard, "\(priority) outranked the pinned band")
        }
    }

    /// Inside the band, the old rules still apply.
    @Test("priority and start time still order within a band")
    func priorityStillOrdersWithinTheBand() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let urgent = ActivityOrderingKey(band: .pinned, priority: .high, startTime: now)
        let calm = ActivityOrderingKey(band: .pinned, priority: .low, startTime: now)
        let older = ActivityOrderingKey(band: .pinned, priority: .low, startTime: now)
        let newer = ActivityOrderingKey(
            band: .pinned,
            priority: .low,
            startTime: now.addingTimeInterval(1)
        )

        #expect(urgent < calm)
        #expect(older < newer)
    }
}
