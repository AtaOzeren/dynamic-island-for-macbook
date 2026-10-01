import Foundation
import Testing

@testable import KerNotchCore

/// What cuts in on what: the rules the tracker plays reactions by.
@Suite("Pet reactions on the island")
struct PetDirectorTests {
    private static let geometry = IslandPet.shiba.stageGeometry()
    private static let openGeometry = IslandPet.shiba.openIslandStageGeometry(stripWidth: 85)
    private static let start: TimeInterval = 1_000

    private static func scene(
        _ stage: PetStage = .roaming,
        mood: PetMood = .calm,
        geometry: PetStageGeometry = geometry
    ) -> PetScene {
        PetScene(stage: stage, geometry: geometry, mood: mood)
    }

    /// A pet settled on its flank long enough that its entrance is over.
    private static func settledTracker(dice: inout PetDice) -> PetRoutineTracker {
        var tracker = PetRoutineTracker(species: .dog)
        tracker.follow(scene(), at: start - 120, dice: &dice)
        return tracker
    }

    @Test("news gets a reaction, and while an agent waits the pet keeps asking")
    func askingIsAnsweredAndHeld() throws {
        var dice = PetDice(seed: 7)
        var tracker = Self.settledTracker(dice: &dice)

        tracker.follow(Self.scene(mood: .asking), moments: [.agentAsked], at: Self.start, dice: &dice)
        let routine = try #require(tracker.performance?.routine)
        let loop = try #require(routine.loop)

        #expect(routine.reactionEnd != nil)
        #expect(loop.effects.contains { $0.effect == .question })
    }

    @Test("nothing new, nothing changes")
    func sameSceneKeepsTheRoutine() {
        var dice = PetDice(seed: 7)
        var tracker = Self.settledTracker(dice: &dice)
        let before = tracker.performance

        tracker.follow(Self.scene(), at: Self.start, dice: &dice)

        #expect(tracker.performance == before)
    }

    /// Hovering back and forth over the island opens and closes it all day.
    @Test("the island opening is answered about one time in four")
    func openingIsAnsweredNowAndThen() {
        var dice = PetDice(seed: 42)
        var tracker = Self.settledTracker(dice: &dice)
        var answered = 0
        let trials = 400
        for trial in 0..<trials {
            let now = Self.start + Double(trial) * (PetRoutineTracker.occasionalCooldown + 1)
            let before = tracker.performance
            tracker.follow(Self.scene(), moments: [.islandOpened], at: now, dice: &dice)
            if tracker.performance != before {
                answered += 1
            }
        }
        let share = Double(answered) / Double(trials)

        #expect((0.17...0.33).contains(share))
    }

    @Test("never twice within a minute, and never the same way twice running")
    func openingsHaveACooldownAndVariety() throws {
        var played: [PetReaction] = []
        for seed in UInt64(1)...40 {
            var dice = PetDice(seed: seed)
            var tracker = Self.settledTracker(dice: &dice)
            var last: TimeInterval?
            var lastReaction: PetReaction?
            for step in 0..<200 {
                let now = Self.start + Double(step) * 7
                let before = tracker.performance
                tracker.follow(Self.scene(), moments: [.islandClosed], at: now, dice: &dice)
                guard tracker.performance != before, let routine = tracker.performance?.routine else { continue }
                let reaction = try #require(Self.closingReaction(in: routine))
                if let last {
                    #expect(now - last >= PetRoutineTracker.occasionalCooldown)
                }
                #expect(reaction != lastReaction)
                last = now
                lastReaction = reaction
                played.append(reaction)
            }
        }

        #expect(Set(played) == Set(PetSpecies.dog.reactions(to: .islandClosed)))
    }

    /// Which closing reaction a routine plays, told apart by the frame only it
    /// uses.
    private static func closingReaction(in routine: PetRoutine) -> PetReaction? {
        let frames = Set(routine.entrance.keyframes.map(\.pose.frame))
        if frames.contains(.shakeLeft) { return .shakeOff }
        if frames.contains(.playBow) { return .stretch }
        if frames.contains(.sitPant) { return .relief }
        return nil
    }

    @Test("a reaction that matters less waits for nothing: it is let go")
    func lesserNewsIsDropped() throws {
        var dice = PetDice(seed: 3)
        var tracker = Self.settledTracker(dice: &dice)
        tracker.follow(Self.scene(), moments: [.agentFailed], at: Self.start, dice: &dice)
        let failing = tracker.performance

        tracker.follow(Self.scene(), moments: [.petted], at: Self.start + 0.5, dice: &dice)
        #expect(tracker.performance == failing)

        tracker.follow(Self.scene(), moments: [.chargerConnected], at: Self.start + 0.6, dice: &dice)
        #expect(tracker.performance == failing)
    }

    @Test("news that matters as much cuts in, from wherever the pet is")
    func equalNewsCutsIn() throws {
        var dice = PetDice(seed: 3)
        var tracker = Self.settledTracker(dice: &dice)
        tracker.follow(Self.scene(), moments: [.agentFailed], at: Self.start, dice: &dice)
        let pose = try #require(tracker.performance).pose(at: Self.start + 0.5)

        tracker.follow(Self.scene(mood: .asking), moments: [.agentAsked], at: Self.start + 0.5, dice: &dice)
        let performance = try #require(tracker.performance)

        #expect(performance.startedAt == Self.start + 0.5)
        #expect(performance.routine.entrance.firstPose.position == pose.position)
    }

    @Test("once a reaction is over, anything may be answered again")
    func afterAReactionAnythingGoes() throws {
        var dice = PetDice(seed: 3)
        var tracker = Self.settledTracker(dice: &dice)
        tracker.follow(Self.scene(), moments: [.agentFailed], at: Self.start, dice: &dice)
        let failing = tracker.performance

        tracker.follow(Self.scene(), moments: [.petted], at: Self.start + 30, dice: &dice)

        #expect(tracker.performance != failing)
    }

    @Test("an icon arriving on the pet's spot drops whatever it was doing")
    func stageChangeDropsTheReaction() throws {
        var dice = PetDice(seed: 3)
        var tracker = Self.settledTracker(dice: &dice)
        tracker.follow(Self.scene(), moments: [.agentCompleted], at: Self.start, dice: &dice)

        tracker.follow(Self.scene(.resting), at: Self.start + 0.4, dice: &dice)
        let routine = try #require(tracker.performance?.routine)

        #expect(routine.reactionEnd == nil)
        #expect(routine.loop?.firstPose.position == Self.geometry.restingPosition)
    }

    /// Opening the island to see what just finished must not cut off the
    /// celebration it set off.
    @Test("the island opening mid-reaction lets it carry on on the wider stage")
    func openingCarriesTheReactionOn() throws {
        var dice = PetDice(seed: 3)
        var tracker = Self.settledTracker(dice: &dice)
        tracker.follow(Self.scene(), moments: [.petted], at: Self.start, dice: &dice)
        let petted = try #require(tracker.performance)
        let end = try #require(petted.routine.reactionEnd)

        tracker.follow(Self.scene(geometry: Self.openGeometry), at: Self.start + 0.5, dice: &dice)
        let open = try #require(tracker.performance)

        #expect(open.routine.geometry == Self.openGeometry)
        #expect(try #require(open.routine.reactionEnd) == end - 0.5)
        #expect(open.pose(at: Self.start + 1) == petted.pose(at: Self.start + 1))
    }

    /// Music starting half-way through a celebration: the celebration
    /// finishes, then the pet nods along.
    @Test("a change of mood lets the reaction finish and changes what follows")
    func moodChangeLetsTheReactionFinish() throws {
        var dice = PetDice(seed: 3)
        var tracker = Self.settledTracker(dice: &dice)
        tracker.follow(Self.scene(), moments: [.agentCompleted], at: Self.start, dice: &dice)
        let celebrating = try #require(tracker.performance)
        let end = try #require(celebrating.routine.reactionEnd)

        tracker.follow(Self.scene(mood: .listening), at: Self.start + 0.5, dice: &dice)
        let listening = try #require(tracker.performance)

        #expect(try #require(listening.routine.reactionEnd) == end - 0.5)
        for moment in stride(from: 0.5, to: end, by: 0.1) {
            #expect(listening.pose(at: Self.start + moment) == celebrating.pose(at: Self.start + moment))
        }
        #expect(listening.routine.loop?.keyframes.contains { $0.pose.frame == .sitNod } == true)
    }

    @Test("off the island the pet hears nothing, and a screen recording sends it off")
    func awayIgnoresNews() throws {
        var dice = PetDice(seed: 3)
        var tracker = Self.settledTracker(dice: &dice)

        tracker.follow(Self.scene(mood: .hiding), moments: [.agentCompleted], at: Self.start, dice: &dice)
        let routine = try #require(tracker.performance?.routine)

        #expect(routine.stage == .away)
        #expect(routine.reactionEnd == nil)
        #expect(routine.loop == nil)
    }

    @Test("resting the pointer on the pet wags it once, not continuously")
    func pettingHasACooldown() {
        var dice = PetDice(seed: 3)
        var tracker = Self.settledTracker(dice: &dice)
        tracker.follow(Self.scene(), moments: [.petted], at: Self.start, dice: &dice)
        let petted = tracker.performance

        tracker.follow(Self.scene(), moments: [.petted], at: Self.start + 5, dice: &dice)
        #expect(tracker.performance == petted)

        tracker.follow(Self.scene(), moments: [.petted], at: Self.start + 9, dice: &dice)
        #expect(tracker.performance != petted)
    }

    @Test("the gesture chosen when a question came is the one repeated while it waits")
    func askingStyleIsKept() throws {
        var dice = PetDice(seed: 11)
        var tracker = Self.settledTracker(dice: &dice)
        tracker.follow(Self.scene(mood: .asking), moments: [.agentAsked], at: Self.start, dice: &dice)
        let firstLoop = try #require(tracker.performance?.routine.loop)

        tracker.follow(Self.scene(.resting, mood: .asking), at: Self.start + 20, dice: &dice)
        let restingLoop = try #require(tracker.performance?.routine.loop)

        #expect(Set(firstLoop.keyframes.map(\.pose.frame)) == Set(restingLoop.keyframes.map(\.pose.frame)))
    }

    @Test("lying down to watch the open island lasts until the island changes")
    func watchingLastsTheStage() throws {
        var dice = PetDice(seed: 3)
        var tracker = PetRoutineTracker(species: .dog)
        tracker.follow(Self.scene(geometry: Self.openGeometry), at: Self.start - 120, dice: &dice)
        var watched = false
        for step in 0..<60 where watched == false {
            let now = Self.start + Double(step) * 61
            tracker.follow(Self.scene(geometry: Self.openGeometry), moments: [.islandOpened], at: now, dice: &dice)
            watched = tracker.performance?.routine.loop?.firstPose.frame == .lie
        }
        #expect(watched)

        tracker.follow(Self.scene(), at: Self.start + 5_000, dice: &dice)
        #expect(tracker.performance?.routine.loop?.firstPose.frame.isSitting == true)
    }

    @Test("switching the pet off forgets everything about it")
    func forgettingForgetsAll() {
        var dice = PetDice(seed: 3)
        var tracker = Self.settledTracker(dice: &dice)
        tracker.follow(Self.scene(), moments: [.agentFailed], at: Self.start, dice: &dice)

        tracker.forget()

        #expect(tracker == PetRoutineTracker(species: .dog))
    }

    @Test("the same seed makes the same choices")
    func diceAreRepeatable() {
        var first = PetDice(seed: 99)
        var second = PetDice(seed: 99)

        #expect((0..<20).map { _ in first.next() } == (0..<20).map { _ in second.next() })
        #expect(first.pick(from: [Int]()) == nil)
    }
}
