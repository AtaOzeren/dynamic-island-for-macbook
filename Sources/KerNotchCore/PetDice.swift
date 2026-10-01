/// The pet's randomness: which of a moment's reactions it plays, and whether it
/// answers an island opening at all.
///
/// A small generator with a seed of its own rather than the system's, so the
/// tracker holding it stays a plain value and a test can replay exactly the
/// choices a pet would make.
public struct PetDice: RandomNumberGenerator, Equatable, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    /// Seeded from the system's generator: a different pet every launch.
    public static func random() -> PetDice {
        PetDice(seed: UInt64.random(in: .min ... .max))
    }

    /// SplitMix64: fast, and evenly spread for a seed of any shape.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// True `chance` of the time.
    mutating func roll(_ chance: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < chance
    }

    /// One of `options`, or `nil` when there are none.
    mutating func pick<Option>(from options: [Option]) -> Option? {
        options.randomElement(using: &self)
    }
}
