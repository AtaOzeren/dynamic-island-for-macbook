/// The companion that lives on the compact island.
public struct IslandPet: Hashable, Sendable {
    /// A Shiba Inu puppy.
    public static let shiba = IslandPet(species: .dog)
    /// A penguin in the likeness of Tux.
    public static let penguin = IslandPet(species: .penguin)

    public let species: PetSpecies
    public let sprites: PetSpriteSheet

    public init(species: PetSpecies) {
        self.species = species
        sprites = species.sprites
    }

    /// Where this pet can stand on a pill drawn with `pill`.
    public func stageGeometry(on pill: CompactPillMetrics = .default) -> PetStageGeometry {
        PetStageGeometry(pill: pill, spriteWidth: sprites.pointWidth)
    }

    /// Where this pet can stand on the open island, whose strip beside the
    /// notch is `stripWidth` points wide.
    public func openIslandStageGeometry(stripWidth: Int, on pill: CompactPillMetrics = .default) -> PetStageGeometry {
        PetStageGeometry(openIslandStripWidth: stripWidth, pill: pill, spriteWidth: sprites.pointWidth)
    }
}
