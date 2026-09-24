import Foundation

/// A routine, and the moment it began.
///
/// Moments are seconds of system uptime (`ProcessInfo.systemUptime`), the
/// clock Core Animation's media time runs on. Once a routine is handed to Core
/// Animation, only that clock moves the pet on screen; timing the routine by
/// the wall clock would let a clock correction or plain drift put the pose
/// this reads somewhere the pet is not, and the next change would start from
/// there — a jump.
public struct PetPerformance: Equatable, Sendable {
    public let routine: PetRoutine
    public let startedAt: TimeInterval

    public init(routine: PetRoutine, startedAt: TimeInterval) {
        self.routine = routine
        self.startedAt = startedAt
    }

    /// Seconds into the routine at uptime `now`; never negative, so a clock
    /// read a hair before the routine began shows its opening pose.
    public func elapsed(at now: TimeInterval) -> TimeInterval {
        max(now - startedAt, 0)
    }

    public func pose(at now: TimeInterval) -> PetPose {
        routine.pose(atElapsed: elapsed(at: now))
    }
}

/// The pet's life across everything that happens around it: which routine it
/// is performing, since when, and what it is in the middle of reacting to.
///
/// Held by the presenter rather than by the view that draws the pet. That view
/// is rebuilt every time the island expands and collapses, and a routine kept
/// there would start over from the edge of the island on every hover.
///
/// A new routine is planned only when something changes — the stage, the mood,
/// or a moment worth reacting to — and it always starts from wherever the pet
/// is at that instant, mid-hop or asleep, so the pet never jumps. What cuts in
/// on what is decided here:
///
/// - The pet having to move always wins: an icon arriving on its spot, the
///   flank filling, a screen recording starting. Whatever it was doing is
///   dropped — it has somewhere to be.
/// - The island opening or closing around the pet lets a reaction carry on on
///   the new stage, if it fits there: a celebration the user opened the
///   island to look at is not cut off by the opening.
/// - A moment cuts in on a reaction that is still going on only if it matters
///   as much (`PetMoment.urgency`); anything less is let go rather than
///   queued, since news that waited would no longer be news. A reaction the
///   change drops anyway holds nothing back.
/// - The mood changing mid-reaction lets the reaction finish, and changes only
///   what follows it.
public struct PetRoutineTracker: Equatable, Sendable {
    /// One island opening or closing in four gets a reaction.
    public static let occasionalChance = 0.25
    /// And never two within a minute, so hovering back and forth over the
    /// island does not keep the pet performing.
    public static let occasionalCooldown: TimeInterval = 60
    /// Running the pointer over the pet wags it once, not continuously.
    public static let pettingCooldown: TimeInterval = 8
    /// How long the island stays empty before the pet lies down for a nap.
    public static let napDelay: TimeInterval = 300

    public private(set) var performance: PetPerformance?
    private var scene: PetScene?
    private var askingStyle: PetReaction?
    private var isWatching = false
    private var runningUrgency: PetUrgency?
    private var reactionEndsAt: TimeInterval?
    private var lastOccasionalReaction: PetReaction?
    private var lastOccasionalAt: TimeInterval?
    private var lastPettedAt: TimeInterval?

    public init() {}

    /// Follows the pet into `scene` at uptime `now`, reacting to the strongest
    /// of `moments` it will answer. Nothing changed and nothing to react to
    /// changes nothing, so this is safe to call on every refresh.
    ///
    /// A pet with no routine yet — just switched on — enters from beyond the
    /// island's outer edge.
    public mutating func follow(
        _ scene: PetScene,
        moments: [PetMoment] = [],
        at now: TimeInterval,
        dice: inout PetDice
    ) {
        let resolved = PetScene(
            stage: scene.mood == .hiding ? .away : scene.stage,
            geometry: scene.geometry,
            mood: scene.mood
        )
        let stageChanged = self.scene?.stage != resolved.stage
        let islandChanged = self.scene?.geometry != resolved.geometry
        if stageChanged || islandChanged {
            isWatching = false
        }

        let unfinished = survivingReaction(
            at: now,
            into: resolved,
            stageChanged: stageChanged,
            islandChanged: islandChanged
        )
        let pick =
            resolved.stage == .away
            ? nil
            : strongestReaction(
                to: moments,
                mattering: unfinished == nil ? nil : runningUrgency(at: now),
                on: resolved.stage,
                at: now,
                dice: &dice
            )
        chooseAskingStyle(for: resolved.mood, picked: pick?.reaction, dice: &dice)
        if pick?.reaction == .lieAndWatch {
            isWatching = true
        }

        let moodChanged = self.scene?.mood != resolved.mood
        guard performance == nil || stageChanged || islandChanged || moodChanged || pick != nil else { return }

        var direction = PetDirection(
            mood: resolved.mood,
            reaction: pick?.reaction,
            askingStyle: askingStyle,
            isWatching: isWatching,
            napDelay: napDelay(in: resolved.mood, at: now)
        )
        if pick == nil {
            direction.unfinished = unfinished
        }

        let pose =
            performance?.pose(at: now)
            ?? PetPose(position: resolved.geometry.offstagePosition, facing: .right, frame: .stand)
        let routine = PetRoutine(stage: resolved.stage, from: pose, geometry: resolved.geometry, direction: direction)
        performance = PetPerformance(routine: routine, startedAt: now)
        reactionEndsAt = routine.reactionEnd.map { now + $0 }
        runningUrgency = routine.reactionEnd == nil ? nil : (pick?.urgency ?? runningUrgency)
        self.scene = resolved
    }

    /// The pet is gone from the island — switched off in the Pet tab. When it
    /// comes back it enters from beyond the edge again rather than resuming a
    /// routine nobody saw finish.
    public mutating func forget() {
        self = PetRoutineTracker()
    }

    /// What is left at `now` of the reaction still playing, if it lives
    /// through this change into `scene`: always through a change of mood
    /// alone, through the island opening or closing if it fits the new stage,
    /// and never when the pet has to move. `nil` once it is over.
    private func survivingReaction(
        at now: TimeInterval,
        into scene: PetScene,
        stageChanged: Bool,
        islandChanged: Bool
    ) -> PetTimeline? {
        guard runningUrgency(at: now) != nil, let performance, let end = performance.routine.reactionEnd else {
            return nil
        }
        if stageChanged, islandChanged == false {
            return nil
        }
        let rest = performance.routine.entrance.cut(from: performance.elapsed(at: now), to: end)
        guard islandChanged else { return rest }
        return Self.fits(rest, on: scene) ? rest : nil
    }

    /// Whether every step of `rest` stays where the pet may be on `scene`'s
    /// stage: anywhere on a flank it has to itself, in the one place beside an
    /// icon give or take a sway, and nowhere once it has to leave.
    private static func fits(_ rest: PetTimeline, on scene: PetScene) -> Bool {
        switch scene.stage {
        case .roaming:
            rest.keyframes.allSatisfy { scene.geometry.roamingRange.contains($0.pose.position) }
        case .resting:
            rest.keyframes.allSatisfy { abs($0.pose.position - scene.geometry.restingPosition) <= 1 }
        case .away:
            false
        }
    }

    /// How much the reaction still playing at `now` matters, or `nil` once it
    /// is over.
    private func runningUrgency(at now: TimeInterval) -> PetUrgency? {
        guard let runningUrgency, let reactionEndsAt, reactionEndsAt > now else { return nil }
        return runningUrgency
    }

    /// Seconds from `now` until the pet naps on an empty island — counted from
    /// the island emptying, or from the last time it was petted, whichever came
    /// later — or `nil` while the island has something on it.
    private func napDelay(in mood: PetMood, at now: TimeInterval) -> TimeInterval? {
        guard case .idle(let since) = mood else { return nil }
        return max(since, lastPettedAt ?? since) + Self.napDelay - now
    }

    /// The gesture the pet keeps making while an agent waits: the one it
    /// reacted with when the question came, or one of its own if it came onto
    /// the island with the question already asked.
    private mutating func chooseAskingStyle(for mood: PetMood, picked: PetReaction?, dice: inout PetDice) {
        guard mood == .asking else {
            askingStyle = nil
            return
        }
        if let picked, PetMoment.agentAsked.reactions.contains(picked) {
            askingStyle = picked
        } else if askingStyle == nil {
            askingStyle = dice.pick(from: PetMoment.agentAsked.reactions)
        }
    }

    /// The reaction to the most urgent of `moments` the pet answers, leaving
    /// out any that matter less than `floor` — the reaction still going on —
    /// before a die is rolled or a cooldown started for them.
    private mutating func strongestReaction(
        to moments: [PetMoment],
        mattering floor: PetUrgency?,
        on stage: PetStage,
        at now: TimeInterval,
        dice: inout PetDice
    ) -> (reaction: PetReaction, urgency: PetUrgency)? {
        let contenders = moments.filter { moment in floor.map { moment.urgency >= $0 } ?? true }
        for moment in contenders.sorted(by: { $0.urgency > $1.urgency }) {
            if let reaction = reaction(to: moment, on: stage, at: now, dice: &dice) {
                return (reaction, moment.urgency)
            }
        }
        return nil
    }

    /// The reaction the pet plays for `moment`, if it plays one: any the stage
    /// has room for, picked at random, the island's comings and goings only
    /// now and then and never the same way twice running.
    private mutating func reaction(
        to moment: PetMoment,
        on stage: PetStage,
        at now: TimeInterval,
        dice: inout PetDice
    ) -> PetReaction? {
        let options = moment.reactions.filter { $0.needsRoom == false || stage == .roaming }
        guard options.isEmpty == false else { return nil }

        if moment.isOccasional {
            if let last = lastOccasionalAt, now - last < Self.occasionalCooldown {
                return nil
            }
            guard dice.roll(Self.occasionalChance) else { return nil }
            let fresh = options.filter { $0 != lastOccasionalReaction }
            let chosen = dice.pick(from: fresh.isEmpty ? options : fresh)
            lastOccasionalAt = now
            lastOccasionalReaction = chosen
            return chosen
        }
        if moment == .petted {
            if let last = lastPettedAt, now - last < Self.pettingCooldown {
                return nil
            }
            lastPettedAt = now
        }
        return dice.pick(from: options)
    }
}
