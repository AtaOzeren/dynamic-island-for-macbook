import Foundation

/// Everything besides the stage that shapes a routine.
struct PetDirection: Equatable, Sendable {
    /// Which pet performs it.
    var species: PetSpecies
    var mood: PetMood = .calm
    /// Played first, where the pet is.
    var reaction: PetReaction?
    /// The gesture the pet repeats while an agent waits on the user.
    var askingStyle: PetReaction?
    /// How the pet spends a mood it knows more than one way of spending.
    var pastime: PetPastime?
    /// Lying to watch the open island, for as long as the stage lasts.
    var isWatching = false
    /// Seconds from the routine's start until the pet lies down for a nap on
    /// an empty island; `nil` while there is something on it.
    var napDelay: TimeInterval?
    /// What is left of a reaction the pet is in the middle of, played out
    /// before anything new.
    var unfinished: PetTimeline?
}

/// What the pet does on a stage: an entrance from wherever the pet was when the
/// stage began, then a loop it repeats for as long as the stage lasts.
///
/// The entrance is where everything that happens once goes — walking in,
/// reacting to news, waking up, dozing off — and the loop is what the pet does
/// in the meantime, chosen by its mood. The whole routine is decided the moment
/// something changes and then played by Core Animation, so a pet on the island
/// costs KerNotch no wake-ups: no timer decides when it next sits down, reacts
/// or falls asleep.
public struct PetRoutine: Equatable, Sendable {
    public let stage: PetStage
    public let geometry: PetStageGeometry
    /// From the pose the pet was in to the loop's opening pose. Empty — a
    /// single pose, no duration — when the pet is already there.
    public let entrance: PetTimeline
    /// Absent while the pet is away: once it has left there is nothing to
    /// repeat.
    public let loop: PetTimeline?
    /// Seconds into the entrance at which its reaction is over, or `nil` when
    /// it has none.
    public let reactionEnd: TimeInterval?
    /// The pose held when the pet may not move at all — Reduce Motion, or the
    /// CPU watchdog standing the island still — or `nil` when it is off the
    /// island.
    public let stillPose: PetPose?

    /// The stage's own routine for `species`, with nothing to react to.
    public init(stage: PetStage, from pose: PetPose, geometry: PetStageGeometry, species: PetSpecies) {
        self.init(stage: stage, from: pose, geometry: geometry, direction: PetDirection(species: species))
    }

    init(stage: PetStage, from pose: PetPose, geometry: PetStageGeometry, direction: PetDirection) {
        self.stage = stage
        self.geometry = geometry
        let species = direction.species
        var choreographer =
            direction.unfinished.map {
                PetChoreographer(continuing: $0, spriteWidth: geometry.spriteWidth, species: species)
            }
            ?? PetChoreographer(startingAt: pose, spriteWidth: geometry.spriteWidth, species: species)

        guard stage != .away else {
            Self.settle(
                &choreographer,
                into: PetPose(position: geometry.offstagePosition, facing: .left, frame: .stand),
                on: stage
            )
            entrance = choreographer.timeline()
            loop = nil
            reactionEnd = nil
            stillPose = nil
            return
        }

        var reactionEnd = direction.unfinished?.duration
        if direction.unfinished == nil {
            Self.wakeIfAsleep(&choreographer, for: direction)
            Self.takeItsPlace(&choreographer, on: stage, in: geometry)
            if let reaction = direction.reaction {
                choreographer.perform(reaction, on: stage, in: geometry)
                reactionEnd = choreographer.time
            }
        }
        self.reactionEnd = reactionEnd

        if let napDelay = direction.napDelay, direction.isWatching == false,
            let awake = PetLoops.idleLoop(on: stage, in: geometry, species: species)
        {
            Self.settle(&choreographer, into: awake.firstPose, on: stage)
            let awakeFor = napDelay - choreographer.time
            if awakeFor > 0, awake.duration > 0 {
                for _ in 0..<Int((awakeFor / awake.duration).rounded(.up)) {
                    choreographer.append(awake)
                }
                choreographer.show(awake.firstPose.frame)
            }
            Self.fallAsleep(&choreographer)
            entrance = choreographer.timeline()
            loop = PetLoops.napping(at: choreographer.pose, spriteWidth: geometry.spriteWidth, species: species)
            stillPose = awake.firstPose
            return
        }

        let loop = PetLoops.loop(for: direction, on: stage, in: geometry, at: choreographer.pose)
        if let loop {
            Self.settle(&choreographer, into: loop.firstPose, on: stage)
        }
        entrance = choreographer.timeline()
        self.loop = loop
        stillPose = loop?.firstPose
    }

    /// The pose `elapsed` seconds after the routine began.
    public func pose(atElapsed elapsed: TimeInterval) -> PetPose {
        guard elapsed >= entrance.duration, let loop, loop.duration > 0 else {
            return entrance.pose(at: elapsed)
        }
        return loop.pose(at: (elapsed - entrance.duration).truncatingRemainder(dividingBy: loop.duration))
    }

    /// Where the routine leaves the pet whenever nothing is animating it: the
    /// loop's opening pose, or where the entrance ends when there is no loop.
    public var settledPose: PetPose {
        loop?.firstPose ?? entrance.lastPose
    }

    /// Goes to `target` a point at a time and takes up its posture there.
    /// Hurrying only off the island; coming onto it, or across the pet's own
    /// place, there is nothing to hurry for.
    private static func settle(_ choreographer: inout PetChoreographer, into target: PetPose, on stage: PetStage) {
        choreographer.travel(to: target.position, gait: stage == .away ? .run : .walk)
        choreographer.turn(target.facing)
        switch target.frame.posture {
        case .sitting:
            choreographer.sitDown()
        case .lying:
            choreographer.lieDown()
        case .standing, .crouching, .airborne, .bowing:
            choreographer.standUp()
        }
        // A pet caught mid-gesture — panting, wagging — settles into the exact
        // frame the loop opens with, so handing over to the loop changes
        // nothing on screen.
        choreographer.show(target.frame)
    }

    /// Onto the stage before anything else: to the middle of its place beside
    /// an icon, or back onto its stage from wherever the pet was — beyond the
    /// island's edge, or further in than a narrower island reaches. Only the
    /// island shrinking out from under it hurries the pet: an icon arriving
    /// beside it takes a place of its own, so the pet just steps aside.
    private static func takeItsPlace(
        _ choreographer: inout PetChoreographer,
        on stage: PetStage,
        in geometry: PetStageGeometry
    ) {
        let position = choreographer.pose.position
        switch stage {
        case .resting:
            let isBeyondItsPlace = position > geometry.roamingRange.upperBound
            choreographer.travel(to: geometry.restingPosition, gait: isBeyondItsPlace ? .run : .walk)
        case .roaming:
            let range = geometry.roamingRange
            if position < range.lowerBound {
                choreographer.travel(to: range.lowerBound, gait: .walk)
            } else if position > range.upperBound {
                choreographer.travel(to: range.upperBound, gait: .run)
            }
        case .away:
            break
        }
    }

    /// A pet woken from its nap by something arriving on the island blinks,
    /// gets up, stretches and yawns. News wakes it straight into the reaction
    /// instead, and a nap that is not over yet is left alone.
    private static func wakeIfAsleep(_ choreographer: inout PetChoreographer, for direction: PetDirection) {
        let stillNapping = direction.mood == .napping || (direction.napDelay.map { $0 <= 0 } ?? false)
        guard choreographer.pose.frame == .sleep, stillNapping == false, direction.reaction == nil else { return }
        choreographer.show(.lieBlink)
        choreographer.hold(0.3)
        choreographer.show(.lie)
        choreographer.hold(0.4)
        choreographer.standUp()
        switch choreographer.species {
        case .dog:
            choreographer.show(.playBow)
            choreographer.hold(0.8)
            choreographer.show(.stand)
            choreographer.hold(0.15)
            choreographer.sitDown()
            choreographer.show(.yawn)
            choreographer.hold(0.6)
            choreographer.show(.sit)
        case .penguin:
            choreographer.show(.stretch)
            choreographer.hold(0.9)
            choreographer.show(.stand)
            choreographer.hold(0.15)
            choreographer.show(.standYawn)
            choreographer.hold(0.6)
            choreographer.show(.standBlink)
            choreographer.hold(0.13)
            choreographer.show(.stand)
            choreographer.hold(0.2)
            choreographer.sitDown()
        }
        choreographer.hold(0.2)
    }

    /// Down on the floor, eyes heavy, then asleep.
    private static func fallAsleep(_ choreographer: inout PetChoreographer) {
        choreographer.lieDown()
        choreographer.hold(0.6)
        choreographer.show(.lieBlink)
        choreographer.hold(0.2)
        choreographer.show(.lie)
        choreographer.hold(0.5)
        choreographer.show(.lieBlink)
        choreographer.hold(0.3)
        choreographer.show(.sleep)
    }
}
