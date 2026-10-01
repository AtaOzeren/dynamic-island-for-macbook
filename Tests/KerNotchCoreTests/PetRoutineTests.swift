import Foundation
import Testing

@testable import KerNotchCore

@Suite("Pet timeline")
struct PetTimelineTests {
    private static let standing = PetPose(position: 4, facing: .right, frame: .stand)

    @Test("a pose holds until the next keyframe, and the ends are clamped")
    func posesHoldBetweenKeyframes() {
        var choreographer = PetChoreographer(startingAt: Self.standing, spriteWidth: 16, species: .dog)
        choreographer.hold(1)
        choreographer.show(.standBlink)
        choreographer.hold(1)
        let timeline = choreographer.timeline()
        var blinking = Self.standing
        blinking.frame = .standBlink

        #expect(timeline.duration == 2)
        #expect(timeline.pose(at: -1) == Self.standing)
        #expect(timeline.pose(at: 0.5) == Self.standing)
        #expect(timeline.pose(at: 1) == blinking)
        #expect(timeline.pose(at: 1.5) == blinking)
        #expect(timeline.pose(at: 99) == blinking)
    }
}

@Suite("Pet choreographer")
struct PetChoreographerTests {
    private static let standing = PetPose(position: 0, facing: .right, frame: .stand)

    @Test("walking covers fifteen points a second, one point per step")
    func walkingPace() {
        var choreographer = PetChoreographer(startingAt: Self.standing, spriteWidth: 16, species: .dog)
        choreographer.walk(to: 15)
        let timeline = choreographer.timeline()

        #expect(timeline.lastPose == PetPose(position: 15, facing: .right, frame: .stand))
        #expect(abs(timeline.duration - (1 + PetGait.walk.stepInterval)) < 0.0001)
        #expect(Self.largestStep(in: timeline) == 1)
    }

    @Test("running covers the same ground in half the time")
    func runningPace() {
        var walker = PetChoreographer(startingAt: Self.standing, spriteWidth: 16, species: .dog)
        walker.walk(to: 15)
        var runner = PetChoreographer(startingAt: Self.standing, spriteWidth: 16, species: .dog)
        runner.travel(to: 15, gait: .run)

        #expect(runner.timeline().duration < walker.timeline().duration * 0.6)
        #expect(Self.largestStep(in: runner.timeline()) == 1)
    }

    @Test("the legs cycle through both strides on the way")
    func legsCycle() {
        var choreographer = PetChoreographer(startingAt: Self.standing, spriteWidth: 16, species: .dog)
        choreographer.walk(to: 12)
        let frames = Set(choreographer.timeline().keyframes.map(\.pose.frame))

        #expect(frames.isSuperset(of: [.strideA, .strideB, .stand]))
    }

    @Test("a pet turns towards where it is going before it sets off")
    func facesTheWayItWalks() {
        var choreographer = PetChoreographer(
            startingAt: PetPose(position: 10, facing: .right, frame: .stand), spriteWidth: 16, species: .dog)
        choreographer.walk(to: 0)
        let moving = choreographer.timeline().keyframes.filter { $0.pose.position != 10 }

        #expect(moving.isEmpty == false)
        #expect(moving.allSatisfy { $0.pose.facing == .left })
    }

    /// The crouch replaces the standing pose it starts from at the same
    /// instant: a pose held for no time is never a keyframe of its own.
    @Test("sitting down and standing up pass through the crouch")
    func crouchBetweenPostures() {
        var choreographer = PetChoreographer(startingAt: Self.standing, spriteWidth: 16, species: .dog)
        choreographer.sitDown()
        choreographer.hold(1)
        choreographer.standUp()

        #expect(
            choreographer.timeline().keyframes.map(\.pose.frame) == [.crouch, .sit, .crouch, .stand]
        )
    }

    @Test("a sitting pet stands before it turns round")
    func turnsOnlyOnItsFeet() throws {
        var choreographer = PetChoreographer(
            startingAt: PetPose(position: 3, facing: .right, frame: .sit), spriteWidth: 16, species: .dog)
        choreographer.turn(.left)
        let turned = try #require(
            choreographer.timeline().keyframes.first { $0.pose.facing == .left }
        )

        #expect(turned.pose.frame == .stand)
    }

    /// Turning mirrors whatever frame is showing, so a leg caught mid-stride
    /// or an eye mid-blink would be seen reversed for the whole turn.
    @Test(
        "a pet caught mid-stride or mid-blink stands square before it turns",
        arguments: [PetFrame.strideA, .strideB, .standBlink]
    )
    func turnsFromAStandingFrame(frame: PetFrame) throws {
        var choreographer = PetChoreographer(
            startingAt: PetPose(position: 10, facing: .right, frame: frame), spriteWidth: 16, species: .dog)
        choreographer.hold(0.2)
        choreographer.turn(.left)
        let turned = try #require(
            choreographer.timeline().keyframes.first { $0.pose.facing == .left }
        )

        #expect(turned.pose.frame == .stand)
    }

    @Test("every gesture in a sit ends back in the sitting pose")
    func gesturesReturnToSitting() {
        var choreographer = PetChoreographer(
            startingAt: PetPose(position: 3, facing: .right, frame: .sit), spriteWidth: 16, species: .dog)
        choreographer.sit(
            for: 4,
            beats: [
                PetBeat(offset: 0.5, gesture: .blink),
                PetBeat(offset: 1, gesture: .pant),
                PetBeat(offset: 2.5, gesture: .wag),
            ]
        )
        let timeline = choreographer.timeline()

        #expect(timeline.duration == 4)
        #expect(timeline.lastPose.frame == .sit)
        #expect(timeline.keyframes.allSatisfy { $0.pose.frame.isSitting })
    }

    @Test("a gesture running past the end of a sit lengthens it")
    func lateGestureLengthensTheSit() {
        var choreographer = PetChoreographer(
            startingAt: PetPose(position: 3, facing: .right, frame: .sit), spriteWidth: 16, species: .dog)
        choreographer.sit(for: 0.2, beats: [PetBeat(offset: 0.1, gesture: .pant)])
        let pantLength = PetGesture.pant.sequence.reduce(0) { $0 + $1.duration }

        #expect(choreographer.timeline().duration >= 0.1 + pantLength)
    }

    /// Two changes at one instant are one pose: nobody sees a pose held for
    /// no time, and Core Animation must not be handed two values at one key
    /// time.
    @Test("keyframes never share an instant")
    func keyframesAreDistinctInTime() {
        var choreographer = PetChoreographer(
            startingAt: PetPose(position: 3, facing: .right, frame: .sit), spriteWidth: 16, species: .dog)
        choreographer.turn(.left)
        choreographer.walk(to: 0)
        let times = choreographer.timeline().keyframes.map(\.time)

        #expect(Set(times).count == times.count)
    }

    static func largestStep(in timeline: PetTimeline) -> Int {
        zip(timeline.keyframes, timeline.keyframes.dropFirst())
            .map { abs($1.pose.position - $0.pose.position) }
            .max() ?? 0
    }
}

@Suite("Pet routine")
struct PetRoutineTests {
    private static let geometry = IslandPet.shiba.stageGeometry()

    /// Every kind of place a stage change can find the pet in: off the island,
    /// sitting, mid-stride, crouched, at both ends of the flank, facing both
    /// ways.
    private static let startingPoses: [PetPose] = [
        PetPose(position: geometry.offstagePosition, facing: .right, frame: .stand),
        PetPose(position: geometry.offstagePosition, facing: .left, frame: .stand),
        PetPose(position: 0, facing: .right, frame: .sit),
        PetPose(position: 3, facing: .right, frame: .sit),
        PetPose(position: 6, facing: .right, frame: .sitPant),
        PetPose(position: 12, facing: .left, frame: .sitBlink),
        PetPose(position: 20, facing: .right, frame: .strideA),
        PetPose(position: 17, facing: .left, frame: .crouch),
        PetPose(position: 34, facing: .left, frame: .stand),
        PetPose(position: 34, facing: .right, frame: .sitWag),
    ]

    private static let stages: [PetStage] = [.roaming, .resting, .away]

    private static var everyRoutine: [PetRoutine] {
        stages.flatMap { stage in
            startingPoses.map { PetRoutine(stage: stage, from: $0, geometry: geometry, species: .dog) }
        }
    }

    private static func timelines(of routine: PetRoutine) -> [PetTimeline] {
        [routine.entrance] + (routine.loop.map { [$0] } ?? [])
    }

    @Test("every entrance begins where the pet was", arguments: stages)
    func entranceBeginsInPlace(stage: PetStage) {
        for pose in Self.startingPoses {
            let routine = PetRoutine(stage: stage, from: pose, geometry: Self.geometry, species: .dog)
            #expect(routine.entrance.firstPose.position == pose.position)
        }
    }

    @Test("every entrance ends exactly where its loop begins", arguments: [PetStage.roaming, .resting])
    func entranceEndsWhereTheLoopBegins(stage: PetStage) throws {
        for pose in Self.startingPoses {
            let routine = PetRoutine(stage: stage, from: pose, geometry: Self.geometry, species: .dog)
            let loop = try #require(routine.loop)
            #expect(routine.entrance.lastPose == loop.firstPose)
        }
    }

    /// The whole point of routines starting from the pet's own pose: whatever
    /// the stage change, the pet walks or runs to its new place a point at a
    /// time rather than appearing there.
    @Test("the pet never jumps, however its stage changes")
    func noTeleporting() {
        for routine in Self.everyRoutine {
            for timeline in Self.timelines(of: routine) {
                #expect(PetChoreographerTests.largestStep(in: timeline) <= 1)
            }
        }
    }

    @Test("a turn happens on the spot")
    func turnsInPlace() {
        for routine in Self.everyRoutine {
            for timeline in Self.timelines(of: routine) {
                for (before, after) in zip(timeline.keyframes, timeline.keyframes.dropFirst())
                where before.pose.facing != after.pose.facing {
                    #expect(before.pose.position == after.pose.position)
                    #expect(after.pose.frame == .stand)
                }
            }
        }
    }

    @Test("every timeline starts at zero and runs forwards")
    func timelinesAreOrdered() {
        for routine in Self.everyRoutine {
            for timeline in Self.timelines(of: routine) {
                #expect(timeline.keyframes.first?.time == 0)
                let times = timeline.keyframes.map(\.time)
                #expect(times == times.sorted())
                #expect(timeline.duration >= (times.last ?? 0))
            }
        }
    }

    @Test("a loop comes back round to the pose it began in", arguments: [PetStage.roaming, .resting])
    func loopsCloseSeamlessly(stage: PetStage) throws {
        let routine = PetRoutine(stage: stage, from: Self.startingPoses[0], geometry: Self.geometry, species: .dog)
        let loop = try #require(routine.loop)

        #expect(loop.lastPose.position == loop.firstPose.position)
        #expect(loop.lastPose.facing == loop.firstPose.facing)
        #expect(loop.firstPose.frame.isSitting)
        // Wrapping round drops straight into the sit: either from the crouch
        // on the way down, or from a sit that is already there.
        #expect(loop.lastPose.frame == .crouch || loop.lastPose.frame.isSitting)
        #expect(loop.keyframes.last.map { $0.time < loop.duration } == true)
    }

    @Test("roaming covers the whole flank and never leaves it")
    func roamingStaysOnTheFlank() throws {
        let loop = try #require(
            PetRoutine(stage: .roaming, from: Self.startingPoses[0], geometry: Self.geometry, species: .dog).loop)
        let positions = Set(loop.keyframes.map(\.pose.position))

        #expect(positions.allSatisfy(Self.geometry.roamingRange.contains))
        #expect(positions.contains(Self.geometry.roamingRange.lowerBound))
        #expect(positions.contains(Self.geometry.roamingRange.upperBound))
    }

    @Test("resting never leaves the outer place")
    func restingStaysInItsPlace() throws {
        let loop = try #require(
            PetRoutine(stage: .resting, from: Self.startingPoses[0], geometry: Self.geometry, species: .dog).loop)

        #expect(loop.keyframes.allSatisfy { $0.pose.position == Self.geometry.restingPosition })
    }

    /// Sitting is when the pet asks nothing of the screen: a loop that walked
    /// more than it sat would keep the compositor busier than the pet is worth.
    @Test("the pet sits more than it moves", arguments: [PetStage.roaming, .resting])
    func sitsMostOfTheTime(stage: PetStage) throws {
        let loop = try #require(
            PetRoutine(stage: stage, from: Self.startingPoses[0], geometry: Self.geometry, species: .dog).loop)
        let boundaries = loop.keyframes.map(\.time) + [loop.duration]
        let sitting = zip(loop.keyframes, boundaries.dropFirst())
            .filter { $0.0.pose.frame.isSitting }
            .reduce(0) { $0 + ($1.1 - $1.0.time) }

        #expect(sitting / loop.duration > 0.5)
        #expect((15...60).contains(loop.duration))
    }

    @Test("a pet already in its place has no entrance to make", arguments: [PetStage.roaming, .resting])
    func noEntranceWhenAlreadyThere(stage: PetStage) throws {
        let loop = try #require(
            PetRoutine(stage: stage, from: Self.startingPoses[0], geometry: Self.geometry, species: .dog).loop)
        let routine = PetRoutine(stage: stage, from: loop.firstPose, geometry: Self.geometry, species: .dog)

        #expect(routine.entrance.duration == 0)
    }

    /// The island closing onto a pet out on the open island's strip leaves it
    /// beyond its place, so it hurries back; coming onto the island there is
    /// nothing to hurry for.
    @Test("getting back into its place is a run, coming onto the island is a walk")
    func hurriesOnlyToMakeRoom() {
        let target = Self.geometry.restingPosition
        let distance = 27
        let fromInside = PetRoutine(
            stage: .resting,
            from: PetPose(position: target + distance, facing: .left, frame: .stand),
            geometry: Self.geometry,
            species: .dog
        )
        let fromOutside = PetRoutine(
            stage: .resting,
            from: PetPose(position: target - distance, facing: .right, frame: .stand),
            geometry: Self.geometry,
            species: .dog
        )

        #expect(fromInside.entrance.duration < fromOutside.entrance.duration)
    }

    @Test("leaving ends past the island's edge, facing out, with nothing left to play")
    func leavingEndsOffTheIsland() {
        let routine = PetRoutine(
            stage: .away,
            from: PetPose(position: 10, facing: .right, frame: .sit),
            geometry: Self.geometry,
            species: .dog
        )

        let offstage = PetPose(position: Self.geometry.offstagePosition, facing: .left, frame: .stand)

        #expect(routine.loop == nil)
        #expect(routine.entrance.lastPose == offstage)
        #expect(routine.settledPose == routine.entrance.lastPose)
        #expect(routine.stillPose == nil)
    }

    @Test("the pose keeps pace with the loop however long it has run")
    func poseWrapsWithTheLoop() throws {
        let routine = PetRoutine(stage: .roaming, from: Self.startingPoses[0], geometry: Self.geometry, species: .dog)
        let loop = try #require(routine.loop)

        for offset in stride(from: 0.0, to: loop.duration, by: 0.37) {
            #expect(
                routine.pose(atElapsed: routine.entrance.duration + loop.duration * 3 + offset)
                    == loop.pose(at: offset)
            )
        }
    }

    @Test("held still, the pet sits where its loop rests")
    func stillPoseIsTheLoopsRest() throws {
        let routine = PetRoutine(stage: .roaming, from: Self.startingPoses[4], geometry: Self.geometry, species: .dog)
        let still = try #require(routine.stillPose)

        #expect(still == routine.loop?.firstPose)
        #expect(still.frame.isSitting)
        #expect(routine.settledPose == still)
    }
}

@Suite("Pet routine tracker")
struct PetRoutineTrackerTests {
    private static let geometry = IslandPet.shiba.stageGeometry()
    private static let start: TimeInterval = 1_000

    private static func follow(_ tracker: inout PetRoutineTracker, _ stage: PetStage, at time: TimeInterval) {
        var dice = PetDice(seed: 1)
        tracker.follow(PetScene(stage: stage, geometry: geometry), at: time, dice: &dice)
    }

    @Test("a pet just switched on walks in from beyond the island's edge")
    func newPetEntersFromOffstage() throws {
        var tracker = PetRoutineTracker(species: .dog)

        Self.follow(&tracker, .roaming, at: Self.start)
        let performance = try #require(tracker.performance)

        #expect(performance.startedAt == Self.start)
        #expect(performance.routine.entrance.firstPose.position == Self.geometry.offstagePosition)
    }

    @Test("staying on a stage keeps the routine it is in the middle of")
    func sameStageKeepsTheRoutine() {
        var tracker = PetRoutineTracker(species: .dog)
        Self.follow(&tracker, .roaming, at: Self.start)
        let first = tracker.performance

        Self.follow(&tracker, .roaming, at: Self.start + 5)

        #expect(tracker.performance == first)
    }

    @Test("a stage change starts from wherever the pet is at that moment")
    func stageChangeStartsInPlace() throws {
        var tracker = PetRoutineTracker(species: .dog)
        Self.follow(&tracker, .roaming, at: Self.start)
        let later = Self.start + 9.3
        let pose = try #require(tracker.performance).pose(at: later)

        Self.follow(&tracker, .resting, at: later)
        let performance = try #require(tracker.performance)

        #expect(performance.startedAt == later)
        #expect(performance.routine.stage == .resting)
        #expect(performance.routine.entrance.firstPose.position == pose.position)
        #expect(performance.pose(at: later).position == pose.position)
    }

    @Test("switching the pet off forgets its routine")
    func forgettingStartsOver() throws {
        var tracker = PetRoutineTracker(species: .dog)
        Self.follow(&tracker, .roaming, at: Self.start)

        tracker.forget()
        #expect(tracker.performance == nil)

        Self.follow(&tracker, .roaming, at: Self.start + 60)
        #expect(try #require(tracker.performance).routine.entrance.firstPose.position == Self.geometry.offstagePosition)
    }

    @Test("a clock read before the routine began shows its opening pose")
    func elapsedNeverNegative() throws {
        var tracker = PetRoutineTracker(species: .dog)
        Self.follow(&tracker, .roaming, at: Self.start)
        let performance = try #require(tracker.performance)

        #expect(performance.elapsed(at: Self.start - 3) == 0)
        #expect(performance.pose(at: Self.start - 3) == performance.routine.entrance.firstPose)
    }
}
