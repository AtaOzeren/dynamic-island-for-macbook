/// The Shiba's pixel art: its palette, the blocks its frames are built from,
/// and the frames themselves.
///
/// Frames share blocks wherever the pet holds part of itself still — the head
/// over a changing body, the body under a changing face — so a pose is drawn
/// once and every frame that holds it reads the same rows.
///
/// `O` coat, `H` the coat where the light falls, `D` the coat in shadow — the
/// far legs, the belly, the haunch — and `R` its deepest folds, inside the
/// ears. `C` cream and `c` cream in shadow, `K` eye and nose, `W` the eye's
/// catchlight, `P` tongue and `p` the open mouth. `G` and `g` are the grey of
/// the headset the pet wears on a call. Orange rather than white because the
/// island's icons are white, and a white dog beside them read as one more
/// glyph.
enum ShibaArt {
    static let palette: [Character: PetColor] = [
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
        "G": PetColor(hex: 0xA7ADB5),
        "g": PetColor(hex: 0x646A72),
    ]

    static let frames: [PetFrame: [String]] = [
        .stand: standingTop + standingBody + standingLegs,
        .standBlink: painting(standingTop, shutEye) + standingBody + standingLegs,
        .strideA: standingTop + standingBody + strideALegs,
        .strideB: standingTop + standingBody + strideBLegs,
        .shakeLeft: shifting(standingTop, by: -1) + standingBody + standingLegs,
        .shakeRight: shifting(standingTop, by: 1) + standingBody + standingLegs,
        .crouch: crouching,
        .hop: standingTop + standingBody + hopLegs + emptyRows(2),
        .sit: sitting,
        .sitBlink: painting(sittingTop, shutEye) + sittingBody,
        .sitPant: painting(sitting, pantingMouth),
        .sitWag: sittingTop + waggingBody,
        .sitNod: loweringHead(sitting),
        .bark: painting(sitting, barkingMouth),
        .yawn: painting(sitting, shutEye + yawningMouth),
        .curious: curious,
        .curiousLow: loweringHead(curious),
        .earsBack: earsBackTop + sittingBody.dropFirst(),
        .pawUp: sittingTop + sittingBody.prefix(5) + pawUpLegs,
        .dazed: painting(sitting, crossedEye),
        .holdBone: stamping(bone, onto: sitting, column: 24, row: 9),
        .holdBoneWag: stamping(bone, onto: sittingTop + waggingBody, column: 24, row: 9),
        .headset: wearingHeadset(sitting),
        .headsetBlink: wearingHeadset(painting(sittingTop, shutEye) + sittingBody),
        .headsetNod: loweringHead(wearingHeadset(sitting)),
        .lie: lying,
        .lieBlink: painting(lying, lyingShutEye),
        .sleep: emptyRows(8) + sleeping + lyingHaunch,
        .lieSad: emptyRows(8) + sulking + lyingHaunch,
        .lieDazed: emptyRows(8) + fainted + lyingHaunch,
        .playBow: emptyRows(3) + playBow,
        .digA: emptyRows(3) + digging + digALegs,
        .digB: emptyRows(3) + digging + digBLegs,
    ]

    private static let sitting = sittingTop + sittingBody
    private static let curious = painting(sitting, curiousFace)
    private static let lying = emptyRows(6) + lyingBody + lyingHaunch

    /// The head is the same in every standing and sitting frame — only the body
    /// moves under it — so the eye and the mouth are always at these pixels.
    private static let shutEye: [ArtPixel] = [
        ArtPixel(column: 26, row: 6, key: "O"),
        ArtPixel(column: 27, row: 6, key: "O"),
        ArtPixel(column: 26, row: 7, key: "R"),
        ArtPixel(column: 27, row: 7, key: "R"),
    ]

    /// The mouth open under the nose, and the tongue hanging past the chin.
    private static let pantingMouth: [ArtPixel] = [
        ArtPixel(column: 29, row: 10, key: "p"),
        ArtPixel(column: 30, row: 10, key: "p"),
        ArtPixel(column: 29, row: 11, key: "P"),
        ArtPixel(column: 30, row: 11, key: "P"),
        ArtPixel(column: 29, row: 12, key: "P"),
        ArtPixel(column: 30, row: 12, key: "p"),
    ]

    /// Ears to chin, with the curled tail, shared by every standing frame.
    static let standingTop = [
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
    static let standingBody = [
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
    static let standingLegs = [
        "......DDDOOO.........DDDOOO.....",
        "......DDDOOO.........DDDOOO.....",
        "......cccCCC.........cccCCC.....",
        "......cccCCc.........cccCCc.....",
    ]

    /// Mid-stride: each paw a point ahead of or behind where its leg joins the
    /// body, the two legs of a pair going opposite ways, which is what makes a
    /// leg read as reaching.
    private static let strideALegs = [
        "......DDDOOO.........DDDOOO.....",
        ".......DOOO.........DDD..OOO....",
        ".......CCCc........ccc....CCC...",
        ".......CCcc........ccc....CCc...",
    ]

    /// The other half of the stride.
    private static let strideBLegs = [
        "......DDDOOO.........DDDOOO.....",
        ".....DDD..OOO.........DOOO......",
        "....ccc....CCC........CCCc......",
        "....ccc....CCc........CCcc......",
    ]

    /// Half-way between standing and sitting: the rear lowered, the front
    /// still standing, the tail still over the back.
    private static let crouching = [
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
    static let sittingTop = [
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
    static let sittingBody = [
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
    private static let waggingBody = [
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
}

extension ShibaArt: PetArtComposer {
    static let artWidth = 32

    /// The same pose with the head a row lower — the top twelve rows from the
    /// neck forwards — which is a nod, or a chin dropped in thought.
    static func loweringHead(_ rows: [String]) -> [String] {
        lowering(rows, columns: 17..<32, topRows: 12)
    }
}
