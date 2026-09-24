import Foundation

/// What the pet does on a stage: an entrance from wherever it was when the
/// stage began, then a loop it repeats for as long as the stage lasts.
///
/// The whole routine is decided the moment the stage changes and then played
/// by Core Animation, so a pet on the island costs KerNotch no wake-ups: no
/// timer decides when it next sits down.
public struct PetRoutine: Equatable, Sendable {
    public let stage: PetStage
    /// From the pose the pet was in to the loop's opening pose. Empty — a
    /// single pose, no duration — when the pet is already there.
    public let entrance: PetTimeline
    /// Absent while the pet is away: once it has left there is nothing to
    /// repeat.
    public let loop: PetTimeline?

    public init(stage: PetStage, from pose: PetPose, geometry: PetStageGeometry) {
        self.stage = stage
        switch stage {
        case .roaming:
            let loop = Self.roamingLoop(in: geometry)
            self.loop = loop
            entrance = Self.entrance(from: pose, to: loop.firstPose, gait: .walk)
        case .resting:
            let loop = Self.restingLoop(in: geometry)
            self.loop = loop
            // Hurrying only when an icon is arriving on the spot it stands on;
            // coming back onto the island there is nothing to hurry for.
            entrance = Self.entrance(
                from: pose,
                to: loop.firstPose,
                gait: pose.position < 0 ? .walk : .run
            )
        case .away:
            loop = nil
            entrance = Self.entrance(
                from: pose,
                to: PetPose(position: geometry.offstagePosition, facing: .left, frame: .stand),
                gait: .run
            )
        }
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

    /// The pose held when the pet may not move at all — Reduce Motion, or the
    /// CPU watchdog standing the island still — or `nil` when it is off the
    /// island.
    public var stillPose: PetPose? {
        loop?.firstPose
    }

    private static func entrance(from pose: PetPose, to target: PetPose, gait: PetGait) -> PetTimeline {
        var choreographer = PetChoreographer(startingAt: pose)
        choreographer.travel(to: target.position, gait: gait)
        choreographer.turn(target.facing)
        if target.frame.isSitting {
            choreographer.sitDown()
        } else {
            choreographer.standUp()
        }
        // A pet caught mid-gesture — panting, wagging — settles into the exact
        // frame the loop opens with, so handing over to the loop changes
        // nothing on screen.
        choreographer.show(target.frame)
        return choreographer.timeline()
    }

    /// About twenty seconds on the empty flank: sitting most of it, a stroll to
    /// each end, and something small — a blink, a wag, a pant — in every sit.
    /// Long sits are the point as much as the walks: a pet that never stops
    /// moving is a distraction on the edge of the screen, not a companion.
    private static func roamingLoop(in geometry: PetStageGeometry) -> PetTimeline {
        let range = geometry.roamingRange
        func spot(_ fraction: Double) -> Int {
            range.lowerBound + Int((Double(range.upperBound - range.lowerBound) * fraction).rounded())
        }
        let home = PetPose(position: spot(0.18), facing: .right, frame: .sit)

        var choreographer = PetChoreographer(startingAt: home)
        choreographer.sit(
            for: 3.2,
            beats: [PetBeat(offset: 1.2, gesture: .blink), PetBeat(offset: 2.0, gesture: .pant)]
        )
        choreographer.walk(to: spot(1))
        choreographer.hold(0.5)
        choreographer.show(.standBlink)
        choreographer.hold(0.15)
        choreographer.show(.stand)
        choreographer.hold(0.35)
        choreographer.sit(
            for: 4.0,
            beats: [PetBeat(offset: 1.0, gesture: .wag), PetBeat(offset: 2.8, gesture: .blink)]
        )
        choreographer.walk(to: spot(0.35))
        choreographer.sit(for: 2.6, beats: [PetBeat(offset: 1.2, gesture: .blink)])
        choreographer.walk(to: spot(0))
        choreographer.hold(0.3)
        choreographer.turn(.right)
        choreographer.hold(0.4)
        choreographer.sit(
            for: 3.4,
            beats: [PetBeat(offset: 1.0, gesture: .pant), PetBeat(offset: 2.6, gesture: .blink)]
        )
        choreographer.walk(to: home.position)
        choreographer.sitDown()
        return choreographer.loop()
    }

    /// Beside a single icon, in the one place left: sitting, and every quarter
    /// of a minute standing to look back towards the edge of the island.
    private static func restingLoop(in geometry: PetStageGeometry) -> PetTimeline {
        let home = PetPose(position: geometry.restingPosition, facing: .right, frame: .sit)

        var choreographer = PetChoreographer(startingAt: home)
        choreographer.sit(
            for: 7.0,
            beats: [PetBeat(offset: 2.0, gesture: .blink), PetBeat(offset: 4.5, gesture: .wag)]
        )
        choreographer.standUp()
        choreographer.hold(0.4)
        choreographer.turn(.left)
        choreographer.hold(0.9)
        choreographer.show(.standBlink)
        choreographer.hold(0.15)
        choreographer.show(.stand)
        choreographer.hold(0.3)
        choreographer.turn(.right)
        choreographer.hold(0.3)
        choreographer.sit(
            for: 6.0,
            beats: [PetBeat(offset: 1.5, gesture: .pant), PetBeat(offset: 4.0, gesture: .blink)]
        )
        return choreographer.loop()
    }
}
