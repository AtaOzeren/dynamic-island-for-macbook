/// A small sprite drawn beside the pet while it reacts: the question mark over
/// its head while an agent waits, the hearts when it is petted, the Zs of a nap.
public enum PetEffect: String, CaseIterable, Sendable {
    case exclamation
    case question
    case heart
    case smallHeart
    case smallZ
    case bigZ
    case star
    case sparkle
    case cloud
    case raindrop
    case note
    case bolt
    case bone
    case dust
    case puff
    case droplet
    /// The lines a bark leaves in the air, pointing the way the pet faces.
    case barkLines
    case bell
    case sweat
    case dirt
    case fish
    case snowflake
}

/// The art the effects are drawn from: each one as rows of palette keys, at
/// the pets' own density, so an effect's pixels are the same size as the dog's.
public struct PetEffectArt: Hashable, Sendable {
    /// Image pixels per point on screen.
    public let pixelsPerPoint: Int
    public let palette: [Character: PetColor]
    /// Rows from the top, one character per pixel, each effect at its own size.
    public let effects: [PetEffect: [String]]

    private let grids: [PetEffect: [[Character]]]

    public init(pixelsPerPoint: Int, palette: [Character: PetColor], effects: [PetEffect: [String]]) {
        self.pixelsPerPoint = max(pixelsPerPoint, 1)
        self.palette = palette
        self.effects = effects
        grids = effects.mapValues { rows in rows.map(Array.init) }
    }

    /// The effect's width in image pixels.
    public func pixelWidth(of effect: PetEffect) -> Int {
        grids[effect]?.first?.count ?? 0
    }

    /// The effect's height in image pixels.
    public func pixelHeight(of effect: PetEffect) -> Int {
        grids[effect]?.count ?? 0
    }

    /// The colour at `column`, `row` of `effect`, counted from the top left and
    /// read from the far side when `mirrored`, or `nil` where nothing is drawn.
    public func color(of effect: PetEffect, mirrored: Bool, column: Int, row: Int) -> PetColor? {
        let width = pixelWidth(of: effect)
        guard let rows = grids[effect], rows.indices.contains(row), (0..<width).contains(column) else {
            return nil
        }
        let pixels = rows[row]
        let artColumn = mirrored ? width - 1 - column : column
        guard pixels.indices.contains(artColumn) else { return nil }
        return palette[pixels[artColumn]]
    }
}

extension PetEffectArt {
    /// The effects every pet shares. Yellow for alarm and delight, blue for
    /// water and sleep, grey for weather and dust, white for what the pet says
    /// — never the icons' own white shapes, which are glyphs, but marks drawn
    /// in the pet's pixels.
    public static let standard = PetEffectArt(
        pixelsPerPoint: 2,
        palette: [
            "Y": PetColor(hex: 0xFFD34D),
            "y": PetColor(hex: 0xE09A1F),
            "B": PetColor(hex: 0x8FD0FF),
            "b": PetColor(hex: 0x3C8DDB),
            "G": PetColor(hex: 0xA7ADB5),
            "g": PetColor(hex: 0x646A72),
            "W": PetColor(hex: 0xFFFFFF),
            "c": PetColor(hex: 0xE2C699),
            "P": PetColor(hex: 0xF07C95),
            "N": PetColor(hex: 0xB98252),
            "n": PetColor(hex: 0x8A5A34),
        ],
        effects: [
            .exclamation: ["YY", "YY", "YY", "YY", "YY", "..", "YY", "YY"],
            .question: [
                ".WWWW.",
                "WW..WW",
                "....WW",
                "...WW.",
                "..WW..",
                "..WW..",
                "......",
                "..WW..",
                "..WW..",
            ],
            .heart: [".PP.PP.", "PWPPPPP", "PPPPPPP", ".PPPPP.", "..PPP..", "...P..."],
            .smallHeart: ["PP.PP", "PPPPP", ".PPP.", "..P.."],
            .smallZ: ["BBBB", "..B.", ".B..", "BBBB"],
            .bigZ: ["BBBBB", "...B.", "..B..", ".B...", "BBBBB"],
            .star: [".Y.", "YWY", ".Y."],
            .sparkle: ["..Y..", "..Y..", "YYWYY", "..Y..", "..Y.."],
            .cloud: ["...GGG....", ".GGGGGGG..", "GGGGGGGGGG", ".gggggggg."],
            .raindrop: ["B", "B"],
            .note: ["..WW", "..WW", "..W.", "..W.", "WWW.", "WW.."],
            .bolt: ["..YYY", ".YYY.", "YYYY.", "..YY.", ".YY..", ".Y..."],
            .bone: [".W....W.", "WWWWWWWW", ".c....c."],
            .dust: ["GG", "GG"],
            .puff: ["G"],
            .droplet: ["B"],
            .barkLines: ["W...", ".W..", "....", "WWW.", "....", ".W..", "W..."],
            .bell: ["..Y..", ".YYY.", ".YYY.", "YYYYY", "..y.."],
            .sweat: [".B.", "BBB", "BbB", ".b."],
            .dirt: ["Nn", "nN"],
            .fish: ["..BBB.b", ".BWBBbb", "BBBBBbb", "..bbb.b"],
            .snowflake: [".B.", "BWB", ".B."],
        ]
    )
}
