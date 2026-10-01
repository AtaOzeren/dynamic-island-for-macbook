/// The user's Pet tab choices, as one value the settings pane edits and the
/// composition root applies.
public struct PetPreferences: Equatable, Sendable {
    public static let `default` = PetPreferences()

    /// Off by default. The idle island draws nothing that moves, and a pet
    /// walking across it is a change to that the user opts into rather than one
    /// made for them.
    public var isEnabled: Bool
    /// Which pet lives on the island: the Shiba unless the user picks another.
    public var species: PetSpecies

    public init(isEnabled: Bool = false, species: PetSpecies = .dog) {
        self.isEnabled = isEnabled
        self.species = species
    }

    /// The pet these choices put on the island, or `nil` for none.
    public var pet: IslandPet? {
        isEnabled ? IslandPet(species: species) : nil
    }
}
