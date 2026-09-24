/// One pose the pet can be drawn in.
///
/// Every frame is drawn facing right. Facing left is the same art mirrored,
/// which is why it is a separate value rather than a second set of frames that
/// would have to be kept in step with the first.
public enum PetFrame: String, CaseIterable, Sendable {
    case stand
    case standBlink
    case strideA
    case strideB
    case crouch
    case sit
    case sitBlink
    case sitPant
    case sitWag

    /// On its haunches. `crouch` is the step between standing and sitting and
    /// counts as neither.
    public var isSitting: Bool {
        switch self {
        case .sit, .sitBlink, .sitPant, .sitWag: true
        case .stand, .standBlink, .strideA, .strideB, .crouch: false
        }
    }
}

/// Which way the pet looks, and walks.
public enum PetFacing: Sendable {
    case left
    case right
}

/// One colour of a pet's palette, in sRGB.
///
/// Bytes rather than an AppKit colour, so the art lives in the module without
/// AppKit, where its shape can be checked without a screen.
public struct PetColor: Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    /// `hex` is `0xRRGGBB`.
    public init(hex: UInt32) {
        red = UInt8(truncatingIfNeeded: hex >> 16)
        green = UInt8(truncatingIfNeeded: hex >> 8)
        blue = UInt8(truncatingIfNeeded: hex)
    }
}

/// A pet's pixel art: every frame as rows of palette keys, drawn facing right.
///
/// Each frame is drawn once into a small image and shown `pixelsPerPoint`
/// image pixels to a point. At two, an image pixel is one device pixel on a
/// Retina panel: the art is as dense as the screen allows, and — shown at
/// exactly its own size — it needs no resampling at all.
public struct PetSpriteSheet: Hashable, Sendable {
    /// The key that leaves a pixel empty.
    public static let transparentKey: Character = "."

    /// The art's size in image pixels.
    public let width: Int
    public let height: Int
    /// Image pixels per point on screen.
    public let pixelsPerPoint: Int
    public let palette: [Character: PetColor]
    /// Rows from the top, one character per pixel.
    public let frames: [PetFrame: [String]]

    private let grids: [PetFrame: [[Character]]]

    public init(
        width: Int,
        height: Int,
        pixelsPerPoint: Int,
        palette: [Character: PetColor],
        frames: [PetFrame: [String]]
    ) {
        self.width = width
        self.height = height
        self.pixelsPerPoint = max(pixelsPerPoint, 1)
        self.palette = palette
        self.frames = frames
        grids = frames.mapValues { rows in rows.map(Array.init) }
    }

    /// The art's width on screen, in points.
    public var pointWidth: Int { width / pixelsPerPoint }

    /// The art's height on screen, in points.
    public var pointHeight: Int { height / pixelsPerPoint }

    /// The colour at `column`, `row` of `frame` as seen facing `facing`, counted
    /// from the top left, or `nil` where nothing is drawn — including anywhere
    /// outside the art.
    public func color(of frame: PetFrame, facing: PetFacing, column: Int, row: Int) -> PetColor? {
        guard
            let rows = grids[frame],
            rows.indices.contains(row),
            (0..<width).contains(column)
        else {
            return nil
        }
        let artColumn = facing == .right ? column : width - 1 - column
        let pixels = rows[row]
        guard pixels.indices.contains(artColumn) else { return nil }
        return palette[pixels[artColumn]]
    }
}

extension PetSpriteSheet {
    /// A Shiba Inu puppy: orange coat, cream cheeks, bib and paws, and a tail
    /// curled over its back — 32 × 24 pixels, drawn in 16 × 12 points.
    ///
    /// `O` coat, `H` the coat where the light falls, `D` the coat in shadow —
    /// the far legs, the belly, the haunch — and `R` its deepest folds, inside
    /// the ears. `C` cream and `c` cream in shadow, `K` eye and nose, `W` the
    /// eye's catchlight, `P` tongue and `p` the open mouth. Orange rather than
    /// white because the island's icons are white, and a white dog beside them
    /// read as one more glyph.
    public static let shiba = PetSpriteSheet(
        width: 32,
        height: 24,
        pixelsPerPoint: 2,
        palette: [
            "O": PetColor(hex: 0xE8983E),
            "H": PetColor(hex: 0xF6B967),
            "D": PetColor(hex: 0xC0702C),
            "R": PetColor(hex: 0x8A4A1C),
            "C": PetColor(hex: 0xFCEBCD),
            "c": PetColor(hex: 0xE2C699),
            "K": PetColor(hex: 0x22150D),
            "W": PetColor(hex: 0xFFFFFF),
            "P": PetColor(hex: 0xF07C95),
            "p": PetColor(hex: 0xC4506A),
        ],
        frames: [
            .stand: shibaStandingTop + shibaStandingBody + shibaStandingLegs,
            .standBlink: painting(shibaStandingTop, shibaShutEye) + shibaStandingBody + shibaStandingLegs,
            .strideA: shibaStandingTop + shibaStandingBody + shibaStrideALegs,
            .strideB: shibaStandingTop + shibaStandingBody + shibaStrideBLegs,
            .crouch: shibaCrouching,
            .sit: shibaSittingTop + shibaSittingBody,
            .sitBlink: painting(shibaSittingTop, shibaShutEye) + shibaSittingBody,
            .sitPant: painting(shibaSittingTop + shibaSittingBody, shibaPantingMouth),
            .sitWag: shibaSittingTop + shibaWaggingBody,
        ]
    )

    /// The head is the same in every frame — only the body moves under it — so
    /// the eye and the mouth are always at these pixels.
    private static let shibaShutEye: [ArtPixel] = [
        ArtPixel(column: 26, row: 6, key: "O"),
        ArtPixel(column: 27, row: 6, key: "O"),
        ArtPixel(column: 26, row: 7, key: "R"),
        ArtPixel(column: 27, row: 7, key: "R"),
    ]

    /// The mouth open under the nose, and the tongue hanging past the chin.
    private static let shibaPantingMouth: [ArtPixel] = [
        ArtPixel(column: 29, row: 10, key: "p"),
        ArtPixel(column: 30, row: 10, key: "p"),
        ArtPixel(column: 29, row: 11, key: "P"),
        ArtPixel(column: 30, row: 11, key: "P"),
        ArtPixel(column: 29, row: 12, key: "P"),
        ArtPixel(column: 30, row: 12, key: "p"),
    ]

    /// Ears to chin, with the curled tail, shared by every standing frame.
    private static let shibaStandingTop = [
        "......................O.....O...",
        ".....................OOO...OOO..",
        ".....................ORO...ORRO.",
        "....HHHH............OORRO.OORRO.",
        "...HOOOOOO..........OHHOOOOOOOO.",
        "..HOOCCCOOO........OOHOOOCOOOOO.",
        "..OOCCCCCOO........OOOOOOOWKOOOO",
        "..OOCCOOCOD........OOOOOOOKKOOOO",
        "..OOCCOOCOD........OOOOOOOOOOOKK",
        "...OOCCCODD........OOOOOCCCCCCCC",
        "....DOOODD.........CCCCCCCCCCCc.",
        ".....DOOD...........cCCCCCCCCc..",
    ]

    /// Back to belly, shared by every standing frame: only the legs move.
    private static let shibaStandingBody = [
        "....OOHHHHHHHHHHHOOCCCCCCCCC....",
        "....OOOOOOOOOOOOOOOOOCCCCCCC....",
        "....OOOOOOOOOOOOOOOOOOCCCCC.....",
        "....OOOOOOOOOOOOOOOOOOOCCCC.....",
        "....DOOOOOOOOOOOOOOOOOOCCC......",
        ".....DDOOOOOOOOOOOOOOODCC.......",
        "......DCCCCCCCCCCCCCCCCC........",
        ".......cccccccccccccccc.........",
    ]

    /// Standing square. Each pair is the far leg, in shadow, and the near leg
    /// beside it.
    private static let shibaStandingLegs = [
        "......DDDOOO.........DDDOOO.....",
        "......DDDOOO.........DDDOOO.....",
        "......cccCCC.........cccCCC.....",
        "......cccCCc.........cccCCc.....",
    ]

    /// Mid-stride: each paw a point ahead of or behind where its leg joins the
    /// body, the two legs of a pair going opposite ways, which is what makes a
    /// leg read as reaching.
    private static let shibaStrideALegs = [
        "......DDDOOO.........DDDOOO.....",
        ".......DOOO.........DDD..OOO....",
        ".......CCCc........ccc....CCC...",
        ".......CCcc........ccc....CCc...",
    ]

    /// The other half of the stride.
    private static let shibaStrideBLegs = [
        "......DDDOOO.........DDDOOO.....",
        ".....DDD..OOO.........DOOO......",
        "....ccc....CCC........CCCc......",
        "....ccc....CCc........CCcc......",
    ]

    /// Half-way between standing and sitting: the rear lowered, the front
    /// still standing, the tail still over the back.
    private static let shibaCrouching = [
        "......................O.....O...",
        ".....................OOO...OOO..",
        ".....................ORO...ORRO.",
        "....................OORRO.OORRO.",
        "....................OHHOOOOOOOO.",
        "...................OOHOOOCOOOOO.",
        "...................OOOOOOOWKOOOO",
        "...................OOOOOOOKKOOOO",
        "....HHH............OOOOOOOOOOOKK",
        "...HOOOOO..........OOOOOCCCCCCCC",
        "..HOCCCOOO.........CCCCCCCCCCCc.",
        "..OOCOOCOD..........cCCCCCCCCc..",
        "..OOCOOCOD.......OOOCCCCCCCCC...",
        "..DOOCCODD.....OHHOOOCCCCCCC....",
        "...DDOOOD...OHHOOOOOOOCCCCCC....",
        "....DOOD..OHOOOOOOOOOOOCCCC.....",
        "......OOOHOOOOOOOOOOOOOCCC......",
        ".....OHOOOOOOOODDOOOOOOCCC......",
        ".....OOOOOODDDDOOOOOOOCCCC......",
        "....DOOOOODOOOOOOOODDCCCC.......",
        "....DOOOODOOOO.......DDDOOO.....",
        "....DDOOOOOOD........DDDOOO.....",
        "....cCCCCCCCc........cccCCC.....",
        ".....cccCCcc.........cccCCc.....",
    ]

    /// Ears to chin, and the neck where the back starts sloping down.
    private static let shibaSittingTop = [
        "......................O.....O...",
        ".....................OOO...OOO..",
        ".....................ORO...ORRO.",
        "....................OORRO.OORRO.",
        "....................OHHOOOOOOOO.",
        "...................OOHOOOCOOOOO.",
        "...................OOOOOOOWKOOOO",
        "...................OOOOOOOKKOOOO",
        "...................OOOOOOOOOOOKK",
        "...................OOOOOCCCCCCCC",
        "..................OCCCCCCCCCCCc.",
        ".................OHOcCCCCCCCCc..",
    ]

    /// On its haunches: the back sloping to the rump, the front legs straight
    /// under the bib, the tail curled on the floor behind.
    private static let shibaSittingBody = [
        "................OHOOCCCCCCCCC...",
        "...............OHOOOCCCCCCCCC...",
        "..............OHOOOOOCCCCCCC....",
        ".............OHOOOOOOOCCCCCC....",
        "............OHOOOOOOOOOCCCCC....",
        "...........OHOOOOOODDOODOCCC....",
        "....HHH...OHOOOODOOOODDOOOCC....",
        "...HOOOO..OOOODOOOOOODDOOOOC....",
        "..HOCCOO.OOOODOOOOOODDDOOOOC....",
        "..OOCCOO.OOOODOOOOOODDDOOOOC....",
        "..OOCCCOOcCCCCCCCCc.cccCCCCC....",
        "...DOOOOccCCCCCCCc..cccCCCCc....",
    ]

    /// The same, with the tail flicked up off the floor.
    private static let shibaWaggingBody = [
        "................OHOOCCCCCCCCC...",
        "...............OHOOOCCCCCCCCC...",
        "..............OHOOOOOCCCCCCC....",
        ".............OHOOOOOOOCCCCCC....",
        "............OHOOOOOOOOOCCCCC....",
        "...O.......OHOOOOOODDOODOCCC....",
        "..OHO.....OHOOOODOOOODDOOOCC....",
        "..OCO.....OOOODOOOOOODDOOOOC....",
        "..OCO....OOOODOOOOOODDDOOOOC....",
        "..OCOO...OOOODOOOOOODDDOOOOC....",
        "...OCOOOOcCCCCCCCCc.cccCCCCC....",
        "....DOOOccCCCCCCCc..cccCCCCc....",
    ]

    /// One pixel of art, placed over a frame: how a blink or a pant is drawn on
    /// a pose without copying the whole frame.
    private struct ArtPixel {
        let column: Int
        let row: Int
        let key: Character
    }

    private static func painting(_ rows: [String], _ pixels: [ArtPixel]) -> [String] {
        var grid = rows.map(Array.init)
        for pixel in pixels where grid.indices.contains(pixel.row) && grid[pixel.row].indices.contains(pixel.column) {
            grid[pixel.row][pixel.column] = pixel.key
        }
        return grid.map { String($0) }
    }
}
