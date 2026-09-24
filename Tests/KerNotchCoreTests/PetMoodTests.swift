import Foundation
import Testing

@testable import KerNotchCore

/// What the pet does between reactions, mood by mood, and the nap an empty
/// island ends in.
@Suite("Pet moods")
struct PetMoodTests {
    private static let geometry = IslandPet.shiba.stageGeometry()
    private static let home = PetPose(position: 6, facing: .right, frame: .sit)

    private static func routine(
        _ mood: PetMood,
        on stage: PetStage = .roaming,
        from pose: PetPose = home,
        askingStyle: PetReaction? = nil,
        napDelay: TimeInterval? = nil
    ) -> PetRoutine {
        PetRoutine(
            stage: stage,
            from: pose,
            geometry: geometry,
            direction: PetDirection(mood: mood, askingStyle: askingStyle, napDelay: napDelay)
        )
    }

    private static let moods: [PetMood] = [.calm, .listening, .digging, .onCall, .napping, .asking]

    @Test("every mood's loop comes back round seamlessly", arguments: moods)
    func loopsCloseSeamlessly(mood: PetMood) throws {
        for stage in [PetStage.roaming, .resting] {
            let loop = try #require(Self.routine(mood, on: stage).loop)

            #expect(loop.keyframes.last.map { $0.time < loop.duration } == true)
            #expect(loop.lastPose.position == loop.firstPose.position)
            #expect(loop.lastPose.facing == loop.firstPose.facing)
            #expect(loop.lastPose.lift == 0)
            for track in loop.effects {
                #expect(track.keyframes.first?.time == 0)
                #expect(track.keyframes.allSatisfy { $0.time <= loop.duration })
            }
        }
    }

    @Test("a mood never takes the pet off its place beside an icon", arguments: moods)
    func moodsStayInTheRestingPlace(mood: PetMood) throws {
        let loop = try #require(Self.routine(mood, on: .resting).loop)

        #expect(loop.keyframes.allSatisfy { $0.pose.position == Self.geometry.restingPosition })
    }

    @Test(
        "each mood has its own look",
        arguments: [
            (PetMood.listening, PetFrame.sitNod, PetEffect.note), (.digging, .digA, .dirt), (.onCall, .headset, nil),
            (.napping, .sleep, .smallZ),
        ] as [(PetMood, PetFrame, PetEffect?)]
    )
    func moodsLookTheirPart(mood: PetMood, frame: PetFrame, effect: PetEffect?) throws {
        let loop = try #require(Self.routine(mood).loop)

        #expect(loop.keyframes.contains { $0.pose.frame == frame })
        if let effect {
            #expect(loop.effects.contains { $0.effect == effect })
        }
    }

    @Test("on a call the headset stays on", arguments: [PetStage.roaming, .resting])
    func headsetStaysOn(stage: PetStage) throws {
        let loop = try #require(Self.routine(.onCall, on: stage).loop)

        #expect(loop.keyframes.allSatisfy { [.headset, .headsetNod, .headsetBlink].contains($0.pose.frame) })
    }

    /// The question mark is how the user sees the pet is waiting on them, so
    /// it never leaves while the loop runs, whichever gesture the pet makes.
    @Test("while an agent waits there is always a question mark", arguments: PetMoment.agentAsked.reactions)
    func askingKeepsTheQuestion(style: PetReaction) throws {
        let loop = try #require(Self.routine(.asking, askingStyle: style).loop)
        let questions = loop.effects.filter { $0.effect == .question }

        #expect(questions.isEmpty == false)
        for moment in stride(from: 0.05, to: loop.duration - 0.3, by: 0.1) where style != .barkForAttention {
            #expect(questions.contains { $0.point(at: moment) != nil }, "\(style) at \(moment)")
        }
    }

    @Test("asleep, the pet stays where it lay down")
    func nappingStaysPut() throws {
        let spot = PetPose(position: 20, facing: .left, frame: .sit)
        let routine = Self.routine(.napping, from: spot)
        let loop = try #require(routine.loop)

        #expect(loop.firstPose == PetPose(position: 20, facing: .left, frame: .sleep))
        #expect(loop.keyframes.allSatisfy { $0.pose.frame == .sleep })
    }

    /// Five minutes of an empty island, all of it played by Core Animation
    /// from the moment the island emptied: no timer puts the pet to sleep.
    @Test("an empty island's pet keeps to its loop, then naps")
    func idleEndsInANap() throws {
        let routine = Self.routine(.idle(since: 0), napDelay: 300)
        let loop = try #require(routine.loop)

        #expect(loop.keyframes.allSatisfy { $0.pose.frame == .sleep })
        #expect(routine.entrance.duration >= 300)
        #expect(routine.entrance.duration < 300 + 30)
        #expect(routine.pose(atElapsed: 290).frame != .sleep)
        #expect(routine.pose(atElapsed: routine.entrance.duration + 1).frame == .sleep)
        #expect(routine.entrance.keyframes.filter { $0.time < 299 }.allSatisfy { $0.pose.frame.posture != .lying })
        // Held still, the pet sits up rather than sleeping through the island
        // being used.
        #expect(routine.stillPose?.frame.isSitting == true)
    }

    @Test("a nap already due starts now")
    func overdueNapStartsNow() throws {
        let routine = Self.routine(.idle(since: 0), napDelay: -5)

        #expect(routine.entrance.duration < 5)
        #expect(routine.loop?.firstPose.frame == .sleep)
    }

    @Test("woken by something arriving, the pet stretches and yawns")
    func wakingIsAStretch() {
        let routine = Self.routine(.calm, from: PetPose(position: 6, facing: .right, frame: .sleep))
        let frames = routine.entrance.keyframes.map(\.pose.frame)

        #expect(frames.contains(.playBow))
        #expect(frames.contains(.yawn))
        #expect(routine.entrance.lastPose == routine.loop?.firstPose)
    }

    @Test("woken by news, the pet goes straight to it")
    func newsWakesAtOnce() {
        let routine = PetRoutine(
            stage: .roaming,
            from: PetPose(position: 6, facing: .right, frame: .sleep),
            geometry: Self.geometry,
            direction: PetDirection(mood: .asking, reaction: .headTilt, askingStyle: .headTilt)
        )

        #expect(routine.entrance.keyframes.contains { $0.pose.frame == .playBow } == false)
        #expect(routine.entrance.keyframes.contains { $0.pose.frame == .curious })
    }

    @Test("a nap that is not over yet is left alone")
    func napStaysAsleep() throws {
        let asleep = PetPose(position: 6, facing: .right, frame: .sleep)
        let routine = Self.routine(.napping, from: asleep)

        #expect(routine.entrance.duration == 0)
        #expect(try #require(routine.loop).firstPose == asleep)
    }

    /// What is left of a reaction, carried into a routine for a new mood.
    @Test("a routine carrying on a reaction plays out the rest of it first")
    func unfinishedReactionPlaysFirst() throws {
        let celebrating = PetRoutine(
            stage: .roaming,
            from: Self.home,
            geometry: Self.geometry,
            direction: PetDirection(reaction: .celebrate)
        )
        let end = try #require(celebrating.reactionEnd)
        let rest = celebrating.entrance.cut(from: 0.4, to: end)
        let carried = PetRoutine(
            stage: .roaming,
            from: rest.firstPose,
            geometry: Self.geometry,
            direction: PetDirection(mood: .listening, unfinished: rest)
        )

        #expect(carried.reactionEnd == rest.duration)
        for moment in stride(from: 0.0, to: rest.duration, by: 0.05) {
            #expect(carried.entrance.pose(at: moment) == celebrating.entrance.pose(at: moment + 0.4))
        }
        #expect(carried.entrance.lastPose == carried.loop?.firstPose)
    }

    @Test("cutting a timeline keeps what shows at the cut and drops what is over")
    func cuttingKeepsTheVisible() throws {
        let celebrating = PetRoutine(
            stage: .roaming,
            from: Self.home,
            geometry: Self.geometry,
            direction: PetDirection(reaction: .celebrate)
        )
        let end = try #require(celebrating.reactionEnd)
        let rest = celebrating.entrance.cut(from: 1.0, to: end)

        #expect(rest.duration == end - 1.0)
        #expect(rest.firstPose == celebrating.entrance.pose(at: 1.0))
        for track in rest.effects {
            #expect(track.keyframes.first?.time == 0)
            #expect(track.keyframes.last?.point == nil)
            #expect(track.keyframes.contains { $0.point != nil })
        }
        #expect(celebrating.entrance.cut(from: 2, to: 1).duration == 0)
    }
}
