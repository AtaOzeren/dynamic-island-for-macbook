/// The companion that lives on the compact island.
public struct IslandPet: Hashable, Sendable {
    /// The one pet KerNotch ships so far.
    public static let shiba = IslandPet(sprites: .shiba)

    public let sprites: PetSpriteSheet

    public init(sprites: PetSpriteSheet) {
        self.sprites = sprites
    }

    /// Where this pet can stand on a pill drawn with `pill`.
    public func stageGeometry(on pill: CompactPillMetrics = .default) -> PetStageGeometry {
        PetStageGeometry(pill: pill, spriteWidth: sprites.pointWidth)
    }
}
