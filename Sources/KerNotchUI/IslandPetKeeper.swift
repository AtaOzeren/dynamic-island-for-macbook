import Foundation
import KerNotchCore

/// Everything the island keeps about its pet from one refresh to the next: the
/// routine it is performing, what it has noticed on the island, the dice it
/// picks its reactions with, and the pointer having moved onto it.
///
/// Held by the presenter for the island's lifetime rather than by a view,
/// because the views are rebuilt on every expand and collapse. A refresh is one
/// call: the island as it is about to be drawn goes in, the pet as it will be
/// drawn comes out.
public struct IslandPetKeeper: Sendable {
    private var routines = PetRoutineTracker()
    private var cues = PetCueReader()
    private var dice: PetDice
    private var pendingMoments: [PetMoment] = []

    public init(dice: PetDice = .random()) {
        self.dice = dice
    }

    /// The pointer moved onto the pet. The next refresh answers it.
    public mutating func notePetting() {
        pendingMoments.append(.petted)
    }

    /// The pet as `island` is about to draw it at uptime `now`: on the stage
    /// the icons leave it, or on the open island's strip beside the notch,
    /// reacting to whatever it has noticed among `activities` since the last
    /// refresh. `nil` while the island has no pet, which forgets it too, so a
    /// pet switched back on walks in afresh.
    public mutating func presentation(
        on island: IslandExtentInput,
        activities: [any Activity],
        at now: TimeInterval
    ) -> IslandPetPresentation? {
        guard let pet = island.pet, let compactStage = islandCompactSlotLayout(island).petStage else {
            self = IslandPetKeeper(dice: dice)
            return nil
        }
        let isOpen = island.state == .expanded
        let noticed = cues.read(activities: activities, isExpanded: isOpen, at: now)
        routines.follow(
            PetScene(
                stage: isOpen ? .roaming : compactStage,
                geometry: islandPetStageGeometry(island, for: pet),
                mood: noticed.mood
            ),
            moments: noticed.moments + pendingMoments,
            at: now,
            dice: &dice
        )
        pendingMoments = []
        return routines.performance.map { IslandPetPresentation(pet: pet, performance: $0) }
    }
}
