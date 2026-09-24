import Foundation
import Testing

@testable import KerNotchCore

/// The awkward moments: the island opening beside an icon, the mood changing
/// while the pet is still walking on, news arriving as an icon pushes the pet
/// aside, news ignored mid-reaction, and a pet caught in the air.
@Suite("Pet interruptions")
struct PetInterruptionTests {
    private static let geometry = IslandPet.shiba.stageGeometry()
    private static let openGeometry = IslandPet.shiba.openIslandStageGeometry(stripWidth: 85)
    private static let start: TimeInterval = 1_000

    private static func settled(on stage: PetStage, dice: inout PetDice) -> PetRoutineTracker {
        var tracker = PetRoutineTracker()
        tracker.follow(PetScene(stage: stage, geometry: geometry), at: start - 120, dice: &dice)
        return tracker
    }

    /// Music on the flank and an agent finishing: opening the island to look
    /// must not cut off the celebration because the pet was beside an icon.
    @Test("beside an icon, the island opening and closing lets the reaction carry on")
    func openingBesideAnIconCarriesOn() throws {
        var dice = PetDice(seed: 3)
        var tracker = Self.settled(on: .resting, dice: &dice)
        tracker.follow(
            PetScene(stage: .resting, geometry: Self.geometry),
            moments: [.petted],
            at: Self.start,
            dice: &dice
        )
        let petted = try #require(tracker.performance)
        let end = try #require(petted.routine.reactionEnd)

        tracker.follow(PetScene(stage: .roaming, geometry: Self.openGeometry), at: Self.start + 0.5, dice: &dice)
        let open = try #require(tracker.performance)
        #expect(try #require(open.routine.reactionEnd) == end - 0.5)
        #expect(open.pose(at: Self.start + 0.8) == petted.pose(at: Self.start + 0.8))

        tracker.follow(PetScene(stage: .resting, geometry: Self.geometry), at: Self.start + 1, dice: &dice)
        let closed = try #require(tracker.performance)
        #expect(abs(try #require(closed.routine.reactionEnd) - (end - 1)) < 0.000_001)
    }

    /// Switched on while an agent waits, the pet walks in and asks; the answer
    /// coming while it is still walking changes what follows, not the walk.
    @Test("a change of mood while the pet is still walking on lets it finish")
    func moodChangeDuringTheWalkOnCarriesOn() throws {
        var dice = PetDice(seed: 5)
        var tracker = PetRoutineTracker()
        tracker.follow(
            PetScene(stage: .roaming, geometry: Self.geometry, mood: .asking),
            moments: [.agentAsked],
            at: Self.start,
            dice: &dice
        )
        let asking = try #require(tracker.performance)
        #expect(asking.pose(at: Self.start + 0.3).position < 0)

        tracker.follow(
            PetScene(stage: .roaming, geometry: Self.geometry, mood: .digging), at: Self.start + 0.3, dice: &dice)
        let digging = try #require(tracker.performance)

        #expect(digging.routine.reactionEnd != nil)
        #expect(digging.pose(at: Self.start + 1) == asking.pose(at: Self.start + 1))
    }

    /// The celebration is dropped for the battery icon arriving on its spot;
    /// the charger's own news is not lost with it.
    @Test("news arriving with an icon that drops the running reaction is still answered")
    func newsIsNotLostWithADroppedReaction() throws {
        var dice = PetDice(seed: 3)
        var tracker = Self.settled(on: .roaming, dice: &dice)
        tracker.follow(
            PetScene(stage: .roaming, geometry: Self.geometry),
            moments: [.agentCompleted],
            at: Self.start,
            dice: &dice
        )

        tracker.follow(
            PetScene(stage: .resting, geometry: Self.geometry),
            moments: [.chargerConnected],
            at: Self.start + 0.5,
            dice: &dice
        )
        let routine = try #require(tracker.performance?.routine)

        #expect(routine.reactionEnd != nil)
        #expect(routine.entrance.effects.contains { $0.effect == .bolt })
    }

    @Test("petting ignored during a more urgent reaction does not use up the petting")
    func ignoredPettingKeepsItsCooldown() throws {
        var dice = PetDice(seed: 3)
        var tracker = Self.settled(on: .roaming, dice: &dice)
        tracker.follow(
            PetScene(stage: .roaming, geometry: Self.geometry),
            moments: [.agentFailed],
            at: Self.start,
            dice: &dice
        )
        let failing = try #require(tracker.performance)
        let end = try #require(failing.routine.reactionEnd)

        tracker.follow(
            PetScene(stage: .roaming, geometry: Self.geometry), moments: [.petted], at: Self.start + 1, dice: &dice)
        #expect(tracker.performance == failing)

        tracker.follow(
            PetScene(stage: .roaming, geometry: Self.geometry),
            moments: [.petted],
            at: Self.start + end + 0.1,
            dice: &dice
        )
        #expect(tracker.performance != failing)
    }

    /// An island opening let go during a reaction must not start the
    /// minute-long wait: the closing after it is answered as often as ever.
    @Test("an island opening let go mid-reaction starts no cooldown")
    func ignoredOpeningStartsNoCooldown() {
        var answered = 0
        let trials = 2_000
        for seed in 0..<UInt64(trials) {
            var dice = PetDice(seed: seed)
            var tracker = Self.settled(on: .roaming, dice: &dice)
            let scene = PetScene(stage: .roaming, geometry: Self.geometry)
            tracker.follow(scene, moments: [.agentFailed], at: Self.start, dice: &dice)
            tracker.follow(scene, moments: [.islandOpened], at: Self.start + 1, dice: &dice)
            let before = tracker.performance
            tracker.follow(scene, moments: [.islandClosed], at: Self.start + 20, dice: &dice)
            if tracker.performance != before {
                answered += 1
            }
        }
        let share = Double(answered) / Double(trials)

        #expect(share > 0.22)
        #expect(share < 0.28)
    }

    /// Caught at the top of a hop, the pet comes down as a hop does, rather
    /// than appearing on the floor: from the height it was caught at, never
    /// more than a hop's last step at a time.
    @Test("a pet caught high in the air comes down two points a frame", arguments: [2, 3, 4, 5])
    func caughtMidHopComesDownGently(lift: Int) {
        let airborne = PetPose(position: 10, lift: lift, facing: .right, frame: .hop)
        let routine = PetRoutine(stage: .roaming, from: airborne, geometry: Self.geometry)
        let lifts = [airborne.lift] + routine.entrance.keyframes.map(\.pose.lift)

        for (before, after) in zip(lifts, lifts.dropFirst()) {
            #expect(before - after <= PetChoreographer.landingStep)
        }
        #expect(routine.entrance.lastPose.lift == 0)
    }
}
