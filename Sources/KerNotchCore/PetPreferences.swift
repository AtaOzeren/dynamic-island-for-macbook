/// The user's Pet tab choices, as one value the settings pane edits and the
/// composition root applies.
public struct PetPreferences: Equatable, Sendable {
    public static let `default` = PetPreferences()

    /// Off by default. The idle island draws nothing that moves, and a pet
    /// walking across it is a change to that the user opts into rather than one
    /// made for them.
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    /// The pet these choices put on the island, or `nil` for none.
    public var pet: IslandPet? {
        isEnabled ? .shiba : nil
    }
}
