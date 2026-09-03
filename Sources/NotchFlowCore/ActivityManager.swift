import Foundation

public struct CompactActivityPresentation {
    public init(
        activities: [any Activity],
        overflowCount: Int,
        groupSizes: [ActivityIdentity: Int]
    ) {
        self.activities = activities
        self.overflowCount = overflowCount
        self.groupSizes = groupSizes
    }

    public let activities: [any Activity]
    public let overflowCount: Int
    /// How many distinct instances each drawn element stands for, keyed by
    /// `compactGroupIdentity`.
    ///
    /// Only grouped kinds ever exceed one. It exists because the pill draws one
    /// icon for every concurrent session of an AI agent, and an icon that says
    /// nothing about how many are behind it lets a second one — possibly the one
    /// asking a question — disappear behind the first.
    ///
    /// Counted over `compactInstanceIdentity` rather than over members, so the
    /// sub-agents an instance spawns never inflate it.
    public let groupSizes: [ActivityIdentity: Int]
}

@MainActor
public final class ActivityManager {
    public typealias Sleep = @Sendable (Duration) async -> Void

    private struct Entry {
        let activity: any Activity
        let registrationTime: Date
        let generation: Int
    }

    private struct CompactGroup {
        let identity: ActivityIdentity
        var representative: any Activity
        let order: Int
        var latestRegistrationTime: Date
        var instanceIdentities: Set<ActivityIdentity>

        var instanceCount: Int { instanceIdentities.count }

        /// What decides which agent groups survive the compact capacity.
        ///
        /// Urgency first, recency only to break ties. Ordering on recency alone
        /// dropped whichever agent started earliest, so three concurrent agents
        /// could push the one waiting on the user out of the pill entirely —
        /// the island then showed two agents working and no sign that a third
        /// had stopped to ask something.
        var admissionKey: (CompactRepresentationPriority, Date) {
            (representative.compactRepresentationPriority, latestRegistrationTime)
        }
    }

    private static let compactAgentCapacity = 2

    private let compactCapacity: Int
    private let sleep: Sleep
    private var entries: [ActivityIdentity: Entry] = [:]
    private var dismissTasks: [ActivityIdentity: Task<Void, Never>] = [:]
    private var activitiesObservers: [UUID: () -> Void] = [:]
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
        let groups = compactGroups
        let groupSizes = Dictionary(
            uniqueKeysWithValues: groups.map { ($0.identity, $0.instanceCount) }
        )
        let standardActivities =
            groups
            .filter { $0.representative.compactRegion == .standard }
            .sorted { $0.order < $1.order }
            .map(\.representative)
        let agentActivities =
            groups
            .filter { $0.representative.compactRegion == .agentTrailing }
            .sorted { $0.admissionKey > $1.admissionKey }
            .prefix(Self.compactAgentCapacity)
            .sorted { $0.latestRegistrationTime < $1.latestRegistrationTime }
            .map(\.representative)

        guard standardActivities.count > compactCapacity else {
            return CompactActivityPresentation(
                activities: standardActivities + agentActivities,
                overflowCount: 0,
                groupSizes: groupSizes
            )
        }

        let visibleStandardCount = compactCapacity - 1
        return CompactActivityPresentation(
            activities: Array(standardActivities.prefix(visibleStandardCount)) + agentActivities,
            overflowCount: standardActivities.count - visibleStandardCount,
            groupSizes: groupSizes
        )
    }

    public var expandedActivities: [any Activity] {
        activeActivities
    }

    /// When each active activity first registered.
    ///
    /// `activeActivities` is ordered by urgency, which is the right order to
    /// *read* a list in and the wrong one to number it by: a presentation that
    /// numbers concurrent sessions from that order renumbers them every time one
    /// of them changes state, so the card labelled "OpenCode 1" becomes
    /// "OpenCode 2" merely because the other session started waiting on the
    /// user. Registration time is the only ordering that stays put.
    public var registrationTimes: [ActivityIdentity: Date] {
        entries.mapValues(\.registrationTime)
    }

    @discardableResult
    public func observeActivitiesChanged(_ observer: @escaping () -> Void) -> UUID {
        let identifier = UUID()
        activitiesObservers[identifier] = observer
        return identifier
    }

    public func removeActivitiesObserver(_ identifier: UUID) {
        activitiesObservers[identifier] = nil
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
            Self.orderingKey(for: left) < Self.orderingKey(for: right)
        }
    }

    private static func orderingKey(for entry: Entry) -> ActivityOrderingKey {
        ActivityOrderingKey(
            band: entry.activity.orderBand,
            priority: entry.activity.priority,
            startTime: entry.registrationTime
        )
    }

    private var compactGroups: [CompactGroup] {
        var groups: [ActivityIdentity: CompactGroup] = [:]

        for (order, entry) in orderedEntries.enumerated() {
            let activity = entry.activity
            let groupIdentity = activity.compactGroupIdentity
            guard var group = groups[groupIdentity] else {
                groups[groupIdentity] = CompactGroup(
                    identity: groupIdentity,
                    representative: activity,
                    order: order,
                    latestRegistrationTime: entry.registrationTime,
                    instanceIdentities: [activity.compactInstanceIdentity]
                )
                continue
            }

            if group.representative.compactRepresentationPriority
                < activity.compactRepresentationPriority
            {
                group.representative = activity
            }
            group.latestRegistrationTime = max(group.latestRegistrationTime, entry.registrationTime)
            group.instanceIdentities.insert(activity.compactInstanceIdentity)
            groups[groupIdentity] = group
        }

        return Array(groups.values)
    }

    private func store(_ activity: any Activity, registrationTime: Date) {
        defer { notifyActivitiesChanged() }

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

        notifyActivitiesChanged()

        if entries.isEmpty {
            onBecomeIdle?()
        }
    }

    private func notifyActivitiesChanged() {
        onActivitiesChanged?()
        for observer in activitiesObservers.values {
            observer()
        }
    }
}
