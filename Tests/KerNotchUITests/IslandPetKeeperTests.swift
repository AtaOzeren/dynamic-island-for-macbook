import CoreGraphics
import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// What the island keeps about its pet between refreshes, and what it hands
/// the pet each time.
@Suite("Island pet keeper")
@MainActor
struct IslandPetKeeperTests {
    private static let charging = ChargingActivity(state: .charging, level: BatteryLevel(fraction: 0.5))
    private static let start: TimeInterval = 1_000

    private static func island(_ state: PresentationState, pet: IslandPet? = .shiba) -> IslandExtentInput {
        IslandExtentInput(
            state: state,
            compact: ActivityManager().compactPresentation,
            hiddenMusicSlotIDs: [],
            pet: pet,
            expanded: [charging],
            disclosedInstances: [],
            registrationTimes: [:],
            notchSize: CGSize(width: 185, height: 32),
            layout: .minimalist
        )
    }

    @Test("without a pet there is nothing to draw, and nothing is remembered")
    func noPetNoPresentation() throws {
        var keeper = IslandPetKeeper(dice: PetDice(seed: 1))
        _ = keeper.presentation(on: Self.island(.compact), activities: [], at: Self.start)

        let gone = keeper.presentation(on: Self.island(.compact, pet: nil), activities: [], at: Self.start + 1)
        let back = keeper.presentation(on: Self.island(.compact), activities: [], at: Self.start + 2)

        #expect(gone == nil)
        let again = try #require(back)
        #expect(again.performance.startedAt == Self.start + 2)
        #expect(again.performance.routine.entrance.firstPose.position < 0)
    }

    @Test("compact, the pet has the flank; open, the strip beside the notch")
    func stageFollowsTheIsland() throws {
        var keeper = IslandPetKeeper(dice: PetDice(seed: 1))
        let compactPet = keeper.presentation(on: Self.island(.compact), activities: [], at: Self.start)
        let openPet = keeper.presentation(on: Self.island(.expanded), activities: [], at: Self.start + 1)

        let compact = try #require(compactPet)
        let open = try #require(openPet)
        #expect(compact.performance.routine.geometry == IslandPet.shiba.stageGeometry())
        #expect(open.performance.routine.geometry == islandPetStageGeometry(Self.island(.expanded), for: .shiba))
        #expect(open.performance.routine.stage == .roaming)
        #expect(open.performance.startedAt == Self.start + 1)
    }

    @Test("the pointer moving onto the pet is answered on the next refresh")
    func pettingIsAnswered() throws {
        var keeper = IslandPetKeeper(dice: PetDice(seed: 1))
        let before = keeper.presentation(on: Self.island(.compact), activities: [], at: Self.start)

        keeper.notePetting()
        let answered = keeper.presentation(on: Self.island(.compact), activities: [], at: Self.start + 30)
        let next = keeper.presentation(on: Self.island(.compact), activities: [], at: Self.start + 31)

        let petted = try #require(answered)
        #expect(petted != before)
        #expect(petted.performance.routine.entrance.effects.contains { $0.effect == .smallHeart })
        #expect(next == petted)
    }

    @Test("an agent asking something reaches the pet")
    func newsReachesThePet() throws {
        var keeper = IslandPetKeeper(dice: PetDice(seed: 1))
        _ = keeper.presentation(on: Self.island(.compact), activities: [], at: Self.start)
        let asking = AIAgentActivity(
            agent: .claudeCode,
            sessionID: UUID(),
            state: .waitingForUser,
            detail: "May I run the tests?"
        )

        let answered = keeper.presentation(on: Self.island(.compact), activities: [asking], at: Self.start + 30)

        let pet = try #require(answered)
        #expect(pet.performance.routine.reactionEnd != nil)
        #expect(pet.performance.routine.loop?.effects.contains { $0.effect == .question } == true)
    }
}
