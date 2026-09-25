import Foundation
import Testing

@testable import KerNotchCore

/// Everything the penguin is ever shown doing is drawn on its sheet.
@Suite("Penguin repertoire")
struct PenguinRepertoireTests {
    private static let geometry = IslandPet.penguin.stageGeometry()

    private static func frames(of timeline: PetTimeline?) -> Set<PetFrame> {
        Set(timeline?.keyframes.map(\.pose.frame) ?? [])
    }

    @Test("every pose of every reaction and loop is on the penguin's sheet")
    func everyPoseIsDrawn() {
        var shown: Set<PetFrame> = []
        for reaction in PetSpecies.penguin.repertoire {
            for pose in PetReactionTests.startingPoses(for: .penguin) {
                let routine = PetReactionTests.routine(reaction, of: .penguin, on: .roaming, from: pose)
                shown.formUnion(Self.frames(of: routine.entrance))
                shown.formUnion(Self.frames(of: routine.loop))
            }
        }
        let moods: [(PetMood, PetPastime?, PetReaction?)] = [
            (.listening, .nodding, nil), (.listening, .swaying, nil), (.digging, .typing, nil),
            (.digging, .fishing, nil), (.onCall, nil, nil), (.napping, nil, nil), (.asking, nil, .barkForAttention),
            (.asking, nil, .raisePaw), (.asking, nil, .tapFoot), (.idle(since: 0), nil, nil),
        ]
        for (mood, pastime, style) in moods {
            for stage in [PetStage.roaming, .resting] {
                let routine = PetRoutine(
                    stage: stage,
                    from: PetPose(position: 6, facing: .right, frame: .sleep),
                    geometry: Self.geometry,
                    direction: PetDirection(
                        species: .penguin,
                        mood: mood,
                        askingStyle: style,
                        pastime: pastime,
                        napDelay: mood == .idle(since: 0) ? 300 : nil
                    )
                )
                shown.formUnion(Self.frames(of: routine.entrance))
                shown.formUnion(Self.frames(of: routine.loop))
            }
        }

        let undrawn = shown.filter { PetSpriteSheet.penguin.frames[$0] == nil }
        #expect(undrawn.isEmpty, "shown but not drawn: \(undrawn)")
    }
}

/// How the tracker picks among the penguin's ways of spending a mood.
@Suite("Penguin pastimes")
struct PenguinPastimeTests {
    private static let geometry = IslandPet.penguin.stageGeometry()

    private static func loopFrames(_ tracker: PetRoutineTracker) -> Set<PetFrame> {
        Set(tracker.performance?.routine.loop?.keyframes.map(\.pose.frame) ?? [])
    }

    @Test("music and work are each spent both ways, one picked each time the mood begins")
    func bothWaysComeUp() {
        var sawTyping = false
        var sawFishing = false
        var sawNodding = false
        var sawSwaying = false
        for seed in UInt64(1)...30 {
            var dice = PetDice(seed: seed)
            var tracker = PetRoutineTracker(species: .penguin)
            tracker.follow(PetScene(stage: .roaming, geometry: Self.geometry, mood: .digging), at: 0, dice: &dice)
            let working = Self.loopFrames(tracker)
            sawTyping = sawTyping || working.contains(.typing)
            sawFishing = sawFishing || working.contains(.fishing)
            tracker.follow(PetScene(stage: .roaming, geometry: Self.geometry, mood: .listening), at: 30, dice: &dice)
            let listening = Self.loopFrames(tracker)
            sawNodding = sawNodding || listening.contains(.sitNod)
            sawSwaying = sawSwaying || listening.contains(.swayLeft)
        }

        #expect(sawTyping && sawFishing)
        #expect(sawNodding && sawSwaying)
    }

    @Test("the way picked holds for as long as the mood does")
    func pastimeHoldsThroughTheMood() {
        var dice = PetDice(seed: 3)
        var tracker = PetRoutineTracker(species: .penguin)
        let working = PetScene(stage: .roaming, geometry: Self.geometry, mood: .digging)
        tracker.follow(working, at: 0, dice: &dice)
        let first = Self.loopFrames(tracker)

        for step in 1...20 {
            tracker.follow(working, moments: [.petted], at: Double(step) * 10, dice: &dice)
            #expect(Self.loopFrames(tracker) == first)
        }
    }

    /// A mood a pet spends only one way rolls no die, so the dog's choices are
    /// exactly what they were before the penguin came.
    @Test("a mood spent one way rolls no die")
    func singleWayRollsNothing() {
        var rolled = PetDice(seed: 11)
        let untouched = PetDice(seed: 11)
        var tracker = PetRoutineTracker(species: .dog)
        tracker.follow(
            PetScene(stage: .roaming, geometry: IslandPet.shiba.stageGeometry(), mood: .listening),
            at: 0,
            dice: &rolled
        )

        #expect(rolled == untouched)
    }

    @Test("a penguin reacts only with its own reactions")
    func reactsWithItsOwn() throws {
        var dice = PetDice(seed: 5)
        var tracker = PetRoutineTracker(species: .penguin)
        tracker.follow(PetScene(stage: .roaming, geometry: Self.geometry), at: 0, dice: &dice)
        for (index, moment) in [PetMoment.agentAsked, .agentFailed, .agentCompleted].enumerated() {
            tracker.follow(
                PetScene(stage: .roaming, geometry: Self.geometry),
                moments: [moment],
                at: Double(index + 1) * 100,
                dice: &dice
            )
            let frames = Set(try #require(tracker.performance).routine.entrance.keyframes.map(\.pose.frame))
            #expect(frames.allSatisfy { PetSpriteSheet.penguin.frames[$0] != nil }, "\(moment)")
        }
    }

    @Test("forgotten, a pet is still the same pet")
    func forgettingKeepsTheSpecies() {
        var tracker = PetRoutineTracker(species: .penguin)
        tracker.forget()

        #expect(tracker.species == .penguin)
    }
}
