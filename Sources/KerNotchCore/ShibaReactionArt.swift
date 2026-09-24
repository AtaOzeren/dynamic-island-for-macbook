/// The Shiba's poses beyond walking and sitting: the ones it reacts in.
///
/// Most are a sitting or standing frame with something painted over it — a
/// mouth opened, an ear flopped, a bone held — so the pet reacts without its
/// body shifting under it. The poses it lowers itself into, lying and bowing,
/// are drawn whole.
extension ShibaArt {
    /// In the air: the hind legs trailing, the front ones tucked under.
    static let hopLegs = [
        ".....DDDOOO...........DDDOOO....",
        "....cccCCc...............CCCc...",
    ]

    /// The jaw dropped open, the tongue behind the teeth.
    static let barkingMouth: [ArtPixel] = [
        ArtPixel(column: 25, row: 10, key: "p"),
        ArtPixel(column: 26, row: 10, key: "p"),
        ArtPixel(column: 27, row: 10, key: "p"),
        ArtPixel(column: 28, row: 10, key: "p"),
        ArtPixel(column: 29, row: 10, key: "p"),
        ArtPixel(column: 30, row: 10, key: "."),
        ArtPixel(column: 26, row: 11, key: "P"),
        ArtPixel(column: 27, row: 11, key: "P"),
        ArtPixel(column: 28, row: 11, key: "p"),
        ArtPixel(column: 29, row: 11, key: "p"),
        ArtPixel(column: 29, row: 12, key: "c"),
    ]

    /// Wider and deeper than a bark, the lip lifted off the nose.
    static let yawningMouth: [ArtPixel] = [
        ArtPixel(column: 31, row: 9, key: "."),
        ArtPixel(column: 25, row: 10, key: "p"),
        ArtPixel(column: 26, row: 10, key: "p"),
        ArtPixel(column: 27, row: 10, key: "p"),
        ArtPixel(column: 28, row: 10, key: "p"),
        ArtPixel(column: 29, row: 10, key: "p"),
        ArtPixel(column: 30, row: 10, key: "."),
        ArtPixel(column: 25, row: 11, key: "p"),
        ArtPixel(column: 26, row: 11, key: "P"),
        ArtPixel(column: 27, row: 11, key: "P"),
        ArtPixel(column: 28, row: 11, key: "P"),
        ArtPixel(column: 29, row: 11, key: "p"),
        ArtPixel(column: 26, row: 12, key: "p"),
        ArtPixel(column: 27, row: 12, key: "p"),
        ArtPixel(column: 28, row: 12, key: "p"),
        ArtPixel(column: 29, row: 12, key: "C"),
    ]

    /// The near ear flopped forward and the eye turned up.
    static let curiousFace: [ArtPixel] = [
        ArtPixel(column: 28, row: 0, key: "."),
        ArtPixel(column: 27, row: 1, key: "."),
        ArtPixel(column: 28, row: 1, key: "."),
        ArtPixel(column: 29, row: 1, key: "."),
        ArtPixel(column: 30, row: 1, key: "O"),
        ArtPixel(column: 31, row: 1, key: "O"),
        ArtPixel(column: 27, row: 2, key: "."),
        ArtPixel(column: 28, row: 2, key: "O"),
        ArtPixel(column: 29, row: 2, key: "O"),
        ArtPixel(column: 30, row: 2, key: "R"),
        ArtPixel(column: 31, row: 2, key: "O"),
        ArtPixel(column: 26, row: 6, key: "K"),
        ArtPixel(column: 26, row: 7, key: "W"),
    ]

    /// The eye crossed out, as cartoons knock a character silly.
    static let crossedEye: [ArtPixel] = [
        ArtPixel(column: 25, row: 5, key: "K"),
        ArtPixel(column: 27, row: 5, key: "K"),
        ArtPixel(column: 26, row: 6, key: "K"),
        ArtPixel(column: 27, row: 6, key: "O"),
        ArtPixel(column: 25, row: 7, key: "K"),
        ArtPixel(column: 26, row: 7, key: "O"),
    ]

    /// Held across the mouth, one knuckle each side of the muzzle.
    static let bone = [
        ".W....W.",
        "WWWWWWWW",
        ".c....c.",
    ]

    /// The band over the crown, the cup on the near ear and the microphone at
    /// the mouth.
    static func wearingHeadset(_ rows: [String]) -> [String] {
        stamping(
            [
                "...gg...",
                "..g..g..",
                ".g......",
                "gGGg....",
                "GGGG....",
                "GGGG....",
                "gGGg....",
                ".g......",
                "..ggggKK",
            ],
            onto: rows,
            column: 21,
            row: 2
        )
    }

    /// Ears flattened back and the head a row lower, down to the neck, which
    /// the body below meets unchanged.
    static let earsBackTop = [
        "................................",
        "................................",
        "................................",
        "...................OO......OO...",
        "..................ORROO...ORROO.",
        "....................OHHOOOOROOO.",
        "...................OOHOOOOROOOO.",
        "...................OOOOOOOKKOOOO",
        "...................OOOOOOOWKOOOO",
        "...................OOOOOOOOOOOKK",
        "..................OOOOOOCCCCCCCC",
        ".................OHCCCCCCCCCCCc.",
        "................OHOOcCCCCCCCCc..",
    ]

    /// The near front leg lifted and bent, paw forward at chest height.
    static let pawUpLegs = [
        "...........OHOOOOOODDOODOCCCCC..",
        "....HHH...OHOOOODOOOODOOOOOOCCc.",
        "...HOOOO..OOOODOOOOOODOOOOCC....",
        "..HOCCOO.OOOODOOOOOODDOOOC......",
        "..OOCCOO.OOOODOOOOOODDD.........",
        "..OOCCCOOcCCCCCCCCc.ccc.........",
        "...DOOOOccCCCCCCCc..ccc.........",
    ]

    /// Lying down with the head up: the body flat on the floor, the front paws
    /// stretched out ahead, the tail still curled over the back.
    static let lyingBody = [
        "......................O.....O...",
        ".....................OOO...OOO..",
        "....HHHH.............ORO...ORRO.",
        "...HOOOOOO..........OORRO.OORRO.",
        "..HOOCCCOOO.........OHHOOOOOOOO.",
        "..OOCCCCCOO........OOHOOOCOOOOO.",
        "..OOCCOOCOD........OOOOOOOWKOOOO",
        "..OOCCOOCOD........OOOOOOOKKOOOO",
        "...OOCCCODD........OOOOOOOOOOOKK",
        "....DOOODD.........OOOOOCCCCCCCC",
        "....OOHHHHHHHHHHHOOCCCCCCCCCCCc.",
        "....OOOOOOOOOOOOOOOOcCCCCCCCCc..",
        "....OOOOOOOOOOOOOOOOOOCCCCC.....",
        "....OOOOOOOOOOOOOOOOOOOCCCC.....",
        "....DOOOOOOOOOOOOOOOOOOCCC......",
    ]

    /// The belly on the floor and the front paws, shared by every lying frame.
    static let lyingHaunch = [
        ".....DDOOOOOOOOOOOOOOODCC.......",
        "......DCCCCCCCCCCCCCCCDDOOOOCCC.",
        ".......cccccccccccccDDOOOOOOCCCc",
    ]

    /// The lying head's eye, six rows below the sitting one.
    static let lyingShutEye: [ArtPixel] = [
        ArtPixel(column: 26, row: 12, key: "O"),
        ArtPixel(column: 27, row: 12, key: "O"),
        ArtPixel(column: 26, row: 13, key: "R"),
        ArtPixel(column: 27, row: 13, key: "R"),
    ]

    /// Chin down on the paws, eyes shut.
    static let sleeping = [
        "....HHHH........................",
        "...HOOOOOO............O.....O...",
        "..HOOCCCOOO..........OOO...OOO..",
        "..OOCCCCCOO..........ORO...ORRO.",
        "..OOCCOOCOD.........OORRO.OORRO.",
        "..OOCCOOCOD.........OHHOOOOOOOO.",
        "...OOCCCODD........OOHOOOCOOOOO.",
        "....DOOODD.........OOOOOOOOOOOOO",
        "....OOHHHHHHHHHHHOOOOOOOOORROOOO",
        "....OOOOOOOOOOOOOOOOOOOOOOOOOOKK",
        "....OOOOOOOOOOOOOOOOOOOOCCCCCCCC",
        "....OOOOOOOOOOOOOOOCCCCCCCCCCCc.",
        "....DOOOOOOOOOOOOOOOcCCCCCCCCc..",
    ]

    /// Chin down, ears flat, looking up from under the brow.
    static let sulking = [
        "....HHHH........................",
        "...HOOOOOO......................",
        "..HOOCCCOOO.....................",
        "..OOCCCCCOO........OO......OO...",
        "..OOCCOOCOD.......ORROO...ORROO.",
        "..OOCCOOCOD.........OHHOOOOROOO.",
        "...OOCCCODD........OOHOOOOROOOO.",
        "....DOOODD.........OOOOOOOKKOOOO",
        "....OOHHHHHHHHHHHOOOOOOOOOWKOOOO",
        "....OOOOOOOOOOOOOOOOOOOOOOOOOOKK",
        "....OOOOOOOOOOOOOOOOOOOOCCCCCCCC",
        "....OOOOOOOOOOOOOOOCCCCCCCCCCCc.",
        "....DOOOOOOOOOOOOOOOcCCCCCCCCc..",
    ]

    /// Flat out: the eye crossed out and the tongue lolling.
    static let fainted = [
        "....HHHH........................",
        "...HOOOOOO............O.....O...",
        "..HOOCCCOOO..........OOO...OOO..",
        "..OOCCCCCOO..........ORO...ORRO.",
        "..OOCCOOCOD.........OORRO.OORRO.",
        "..OOCCOOCOD.........OHHOOOOOOOO.",
        "...OOCCCODD........OOHOOOKOKOOO.",
        "....DOOODD.........OOOOOOOKOOOOO",
        "....OOHHHHHHHHHHHOOOOOOOOKOKOOOO",
        "....OOOOOOOOOOOOOOOOOOOOOOOOOOKK",
        "....OOOOOOOOOOOOOOOOOOOOCCCCCCCC",
        "....OOOOOOOOOOOOOOOCCCCCCCCCCpc.",
        "....DOOOOOOOOOOOOOOOcCCCCCCCCPP.",
    ]

    /// Rump and tail up, chest down, front legs flat along the floor.
    static let playBow = [
        "....HHHH........................",
        "...HOOOOOO......................",
        "..HOOCCCOOO.....................",
        "..OOCCCCCOO..........O.....O....",
        "..OOCCOOCOD.........OOO...OOO...",
        "..OOCCOOCOD.........ORO...ORRO..",
        "...OOCCCODD........OORRO.OORRO..",
        "....DOOODD.........OHHOOOOOOOO..",
        ".....DOOD.........OOHOOOCOOOOO..",
        "....OOHHHHHHHH....OOOOOOOWKOOOO.",
        "....OOOOOOOOOOHH..OOOOOOOKKOOOO.",
        "....OOOOOOOOOOOOHOOOOOOOOOOOOKK.",
        "....OOOOOOOOOOOOOOOOOOOCCCCCCCC.",
        "....DOOOOOOOOOOOOOCCCCCCCCCCCc..",
        ".....DDOOOOOOOOOOOOcCCCCCCCCc...",
        "......DCCCCCCCOOOOOOOOCCCCCC....",
        ".......cccccccCCOOOOOOCCCCCC....",
        "......DDDOOO..ccCCOOOOOCCCC.....",
        "......DDDOOO....ccCCOOOCCCC.....",
        "......cccCCC......DDDOOOOOOOCC..",
        "......cccCCc......cccCCCCCCCCCc.",
    ]

    /// Bowed lower than the stretch, nose to the ground, down to where the
    /// front paws take turns at the earth.
    static let digging = [
        "....HHHH........................",
        "...HOOOOOO......................",
        "..HOOCCCOOO.....................",
        "..OOCCCCCOO.....................",
        "..OOCCOOCOD.........O.....O.....",
        "..OOCCOOCOD........OOO...OOO....",
        "...OOCCCODD........ORO...ORRO...",
        "....DOOODD........OORRO.OORRO...",
        ".....DOOD.........OHHOOOOOOOO...",
        "....OOHHHHHHHH...OOHOOOCOOOOO...",
        "....OOOOOOOOOOHH.OOOOOOOWKOOOO..",
        "....OOOOOOOOOOOOHOOOOOOOKKOOOO..",
        "....OOOOOOOOOOOOOOOOOOOOOOOOKK..",
        "....DOOOOOOOOOOOOOOOOOCCCCCCCC..",
        ".....DDOOOOOOOOOOCCCCCCCCCCCc...",
        "......DCCCCCCCOOOOcCCCCCCCCc....",
        ".......cccccccCCOOOOOOCCCCCC....",
        "......DDDOOO..ccCCOOOOOCCCC.....",
    ]

    /// One paw reaching forward to scrape, the other pulling back.
    static let digALegs = [
        "......DDDOOO....cDDOOOOCCCC.....",
        "......cccCCC....DDOOOCDCCCODD...",
        "......cccCCc...cccCCccCCC.Ccc...",
    ]

    /// The paws the other way round.
    static let digBLegs = [
        "......DDDOOO....ccCDDOOOCCC.....",
        "......cccCCC......ccDDOOOOCC....",
        "......cccCCc........ccccCCCc....",
    ]
}
