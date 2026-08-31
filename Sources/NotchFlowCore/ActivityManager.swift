import Foundation

public struct CompactActivityPresentation {
    public let activities: [any Activity]
    public let overflowCount: Int
}

@MainActor
public final class ActivityManager {
    public typealias Sleep = @Sendable (Duration) async -> Void

    private struct Entry {
        let activity: any Activity
        let registrationTime: Date
        let generation: Int
    }

    private let compactCapacity: Int
    private let sleep: Sleep
    private var entries: [ActivityIdentity: Entry] = [:]
    private var dismissTasks: [ActivityIdentity: Task<Void, Never>] = [:]
    private var nextGeneration = 0

    public var onBecomeIdle: (() -> Void)?

    /// Fired after every mutation of the active set — registration, in-place
    /// update, and removal — so a presenter can re-read `activeActivities`
    /// without polling.
    public var onActivitiesChanged: (() -> Void)?

    public init(
        compactCapacity: Int = 3,
        sleep: @escaping Sleep = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.compactCapacity = max(1, compactCapacity)
        self.sleep = sleep
    }

    public var activeActivities: [any Activity] {
        orderedEntries.map(\.activity)
    }

    public var compactPresentation: CompactActivityPresentation {
        let activities = activeActivities
        guard activities.count > compactCapacity else {
            return CompactActivityPresentation(activities: activities, overflowCount: 0)
        }

        let visibleCount = compactCapacity - 1
        return CompactActivityPresentation(
            activities: Array(activities.prefix(visibleCount)),
            overflowCount: activities.count - visibleCount
        )
    }

    public var expandedActivities: [any Activity] {
        activeActivities
    }

    public func register(_ activity: any Activity, at registrationTime: Date = Date()) {
        let preservedRegistrationTime = entries[activity.identity]?.registrationTime ?? registrationTime
        store(activity, registrationTime: preservedRegistrationTime)
    }

    public func update(_ activity: any Activity, at updateTime: Date = Date()) {
        guard let entry = entries[activity.identity] else { return }
        store(activity, registrationTime: entry.registrationTime)
    }

    public func end(_ identity: ActivityIdentity, at endTime: Date = Date()) {
        remove(identity)
    }

    private var orderedEntries: [Entry] {
        entries.values.sorted { left, right in
            ActivityOrderingKey(
                priority: left.activity.priority,
                startTime: left.registrationTime
            )
                < ActivityOrderingKey(
                    priority: right.activity.priority,
                    startTime: right.registrationTime
                )
        }
    }

    private func store(_ activity: any Activity, registrationTime: Date) {
        defer { onActivitiesChanged?() }

        dismissTasks[activity.identity]?.cancel()
        nextGeneration += 1

        let generation = nextGeneration
        entries[activity.identity] = Entry(
            activity: activity,
            registrationTime: registrationTime,
            generation: generation
        )

        guard let autoDismiss = activity.autoDismiss else {
            dismissTasks[activity.identity] = nil
            return
        }

        let identity = activity.identity
        let sleep = sleep
        dismissTasks[identity] = Task { [weak self] in
            await sleep(autoDismiss.after)
            guard !Task.isCancelled else { return }
            self?.remove(identity, generation: generation)
        }
    }

    private func remove(_ identity: ActivityIdentity, generation: Int? = nil) {
        guard let entry = entries[identity] else { return }
        guard generation == nil || entry.generation == generation else { return }

        entries[identity] = nil
        dismissTasks[identity]?.cancel()
        dismissTasks[identity] = nil

        onActivitiesChanged?()

        if entries.isEmpty {
            onBecomeIdle?()
        }
    }
}
