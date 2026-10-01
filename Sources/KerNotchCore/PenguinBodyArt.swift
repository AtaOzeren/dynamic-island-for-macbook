/// The body under the penguin's head, standing, crouching and sitting, and
/// the feet: the blocks `PenguinArt` puts its frames together from, with the
/// flippers, the props and the poses on the ground below.
extension PenguinArt {
    /// Neck to rump, with the near flipper hanging at its side.
    static let body = [
        ".........HKKKKKWWWWWWWK.........",
        "........HKKKKKWWWWWWWWWK........",
        "........HKKKKWWWWWWWWWWK........",
        ".......HKKKKWWWWWWWWWWWKK.......",
        "......HKKHKKWWWWWWWWWWWWK.......",
        "......HKKHKWWWWWWWWWWWWWK.......",
        ".....HKKKHKWWWWWWWWWWWWWKK......",
        ".....HKKKHKWWWWWWWWWWWWWKK......",
        "......KKK.KWWWWWWWWWWWWwKK......",
        "..........KwWWWWWWWWWWwwKK......",
        "..........KKwwWWWWWWWwwKK.......",
        "...........KKwwwwwwwwKKK........",
        "............KKKKKKKKKKK.........",
    ]

    /// The same with the near flipper lifted away, for the frames that hold it
    /// somewhere else.
    static let bareBody = [
        ".........HKKKKKWWWWWWWK.........",
        "........HKKKKKWWWWWWWWWK........",
        "........HKKKKWWWWWWWWWWK........",
        ".......HKKKKWWWWWWWWWWWKK.......",
        ".........HKKWWWWWWWWWWWWK.......",
        ".........HKWWWWWWWWWWWWWK.......",
        ".........HKWWWWWWWWWWWWWKK......",
        ".........HKWWWWWWWWWWWWWKK......",
        ".........HKWWWWWWWWWWWWwKK......",
        "..........KwWWWWWWWWWWwwKK......",
        "..........KKwwWWWWWWWwwKK.......",
        "...........KKwwwwwwwwKKK........",
        "............KKKKKKKKKKK.........",
    ]

    /// Knees bent: two rows lower and a little wider, flipper held off the side.
    static let crouchingBody = [
        ".........HKKKKKWWWWWWWK.........",
        "........HKKKKKWWWWWWWWWK........",
        ".......HKKKKWWWWWWWWWWWKK.......",
        ".....HKKHKKWWWWWWWWWWWWWK.......",
        "....HKKKHKWWWWWWWWWWWWWWKK......",
        "....HKKKHKWWWWWWWWWWWWWWKK......",
        "....HKKKHKWWWWWWWWWWWWWWKK......",
        ".....KKK.KwWWWWWWWWWWWWwwKK.....",
        ".........KKwwWWWWWWWWWwwKKK.....",
        "..........KKwwwwwwwwwwKKK.......",
        "...........KKKKKKKKKKKK.........",
    ]

    /// Sat on its tail like the Linux logo, both feet out in front.
    static let sittingBody = [
        ".........HKKKKKWWWWWWWK.........",
        "........HKKKKKWWWWWWWWWK........",
        ".......HKKKKWWWWWWWWWWWKK.......",
        "......HKKHKKWWWWWWWWWWWWK.......",
        ".....HKKKHKWWWWWWWWWWWWWKK......",
        ".....HKKKHKWWWWWWWWWWWWWKK......",
        ".....HKKK.KWWWWWWWWWWWWWwKK.....",
        "......KK..KwWWWWWWWWWWWwwKK.....",
        ".......HKKKKwwWWWWWWWwwwKKYY....",
        "........KKKYYYYKKKKKKKYYYYY.....",
        ".......yYYYYYY.......yYYYYYY....",
    ]

    static let feet = [
        "...........YYYYY...YYYYYY.......",
        "..........yYYYYY..yYYYYYY.......",
    ]

    /// The far foot lifted for a step.
    static let strideAFeet = [
        "...........YYYYY...yYYYYY.......",
        "..........yYYYYY................",
    ]

    /// The near foot lifted for a step.
    static let strideBFeet = [
        "..........yYYYYY...YYYYYY.......",
        "..................yYYYYYY.......",
    ]

    /// Dangling, in the air.
    static let hopFeet = [
        "............YYY...YYYY..........",
        "............yY.....yY...........",
    ]

    /// The far foot's toes up, tapping.
    static let tappingFeet = [
        "...........YYYYY.....YYYYY......",
        "..........yYYYYY..yY............",
    ]

    /// Kicked out in front, going from under it.
    static let slippingFeet = [
        "......................YYYYY.....",
        "..........yYYYYY......yYYY......",
    ]
}

/// The flippers held anywhere but at the side. Each is laid over a body
/// drawn without that flipper, its top left at the place its frame says.
extension PenguinArt {
    static let nearFlipperOut = [
        "....HH...",
        "...HKKH..",
        "....HKKKK",
    ]

    static let farFlipperOut = [
        "KK..",
        "KKKK",
        "..KK",
    ]

    static let nearFlipperUp = [
        "....H",
        "...HK",
        "...HKK",
        "....HKK",
        ".....KK",
        "......K",
    ]

    static let farFlipperUp = [
        "...KH",
        "..KKH",
        ".KKK.",
        "KK...",
    ]

    /// Up high like a hand, clear of the head.
    static let raisedFlipper = [
        ".HK..",
        "HKK..",
        "HKK..",
        ".HKK.",
        ".HKK.",
        "..HK.",
        "..HKK",
        "...KK",
    ]

    /// Bent out with its tip on the hip.
    static let akimboFlipper = [
        ".....HKK",
        "....HKK.",
        "....HK..",
        ".....HK.",
    ]

    /// Swept back and down, stretching.
    static let backFlipper = [
        "....HK...",
        "...HKK...",
        "..HKK....",
        ".HKK.....",
    ]

    /// Up in front of the face, fanning it.
    static let farFlipperFanningUp = [
        "..KKH",
        ".KKKH",
        ".KKK.",
        "KKK..",
        "KK...",
    ]

    /// Down across the chest, on the fan's down-stroke.
    static let farFlipperFanningDown = [
        "KKKKH",
        "KKKKH",
        ".KK..",
    ]
}

/// What the penguin catches, wears and works with.
extension PenguinArt {
    /// Head first in the beak, tail out.
    static let heldFish = [
        "..BBB.b",
        ".BWBBbb",
        "BBBBBbb",
        "..bbb.b",
    ]

    /// Over the crown, a cup over the near side of the head, the microphone
    /// down to the beak.
    static let headset = [
        "............gGGGGGg.............",
        "...........G.......G............",
        "..........g.........g...........",
        ".........gGg....................",
        ".........GGg....................",
        ".........gGg....................",
        "..........g.....................",
        "...........ggg..................",
    ]

    /// Open in front of it, a prompt on the screen and the cursor lit.
    static let laptop = [
        "......gggggg",
        "......gSSSSg",
        "......gSLSSg",
        "......gSSLSg",
        "......gSLSLL",
        "......gSSSSg",
        "......gggggg",
        "..GGGGGGGGGG",
        ".gggggggggg.",
    ]

    /// The same with the cursor out.
    static let laptopCursorOff = [
        "......gggggg",
        "......gSSSSg",
        "......gSLSSg",
        "......gSSLSg",
        "......gSLSSg",
        "......gSSSSg",
        "......gggggg",
        "..GGGGGGGGGG",
        ".gggggggggg.",
    ]

    /// The far flipper down on the keys.
    static let typingFlipper = [
        "...KK",
        "..KKK",
        ".KKK.",
    ]

    /// The far flipper lifted between keystrokes.
    static let liftedFlipper = [
        "..KK.",
        "KKK..",
        "KK...",
    ]

    /// The far flipper forward, holding the rod.
    static let rodFlipper = [
        "KKK",
        "KK.",
    ]

    /// Up and out over the ice, the line straight down.
    static let rod = [
        "......N",
        ".....NG",
        "....N.G",
        "...N..G",
        "..N...G",
        ".N....G",
        "N.....G",
        "......G",
        "......G",
        "......G",
        "......G",
        "......G",
    ]

    /// Bent to the water: something is biting.
    static let bentRod = [
        ".......",
        "......N",
        ".....N.",
        "....NNG",
        "...N..G",
        "..N...G",
        ".N....G",
        "N.....G",
        "......G",
        "......G",
        "......G",
        "......G",
    ]

    /// The hole in the ice the line goes into.
    static let iceHole = [
        "BbbbB.",
        "BbbbbB",
    ]
}

/// The poses on the ground: lying on its belly, sliding, asleep, and flat on
/// its back.
extension PenguinArt {
    /// On its belly with the head up, watching.
    static let lying = [
        "...................HHKKK........",
        ".................HKKKKKKKK......",
        "................HKKKKWWKKWWK....",
        "..........HHHHHHKKKKWWkKWWkK....",
        ".......HHHKKKKKKKKKKKWKKYYYYYY..",
        "....YYHKKKKKKKKKKKKKKKKKYYYYYYY.",
        "...YYyKKKKKKKKKKKKKKKKKKKyyyyy..",
        "....yKKKKKKKKKKKKKKKKKKKKKKK....",
        ".....KKWWWWWWWWWWWWWWWWWWKK.....",
        "......wwwwWWWWWWWWWWWWWWWK......",
        ".......wwwwwwwwwwwwwwwwww.......",
    ]

    static let lyingBlink = [
        "...................HHKKK........",
        ".................HKKKKKKKK......",
        "................HKKKKWWKKWWK....",
        "..........HHHHHHKKKKKKkKKKkK....",
        ".......HHHKKKKKKKKKKkkkKkkkYYY..",
        "....YYHKKKKKKKKKKKKKKKKKYYYYYYY.",
        "...YYyKKKKKKKKKKKKKKKKKKKyyyyy..",
        "....yKKKKKKKKKKKKKKKKKKKKKKK....",
        ".....KKWWWWWWWWWWWWWWWWWWKK.....",
        "......wwwwWWWWWWWWWWWWWWWK......",
        ".......wwwwwwwwwwwwwwwwww.......",
    ]

    /// Flat on its belly, head forward and flippers swept back along its sides.
    static let sliding = [
        "..................HKKKKK........",
        "..........HHHHHHHKKKKKWWKKWWK...",
        ".......HHHKKKKKKKKKKKWWkKWWkK...",
        "....YYHKKHHHHKKKKKKKKKWKKKKKYYYY",
        "...YYHKKKKKKKHHKKKKKKKKKKKYYYYYy",
        "....YKKKKKKKKKKKKKKKKKKKKKKyyyy.",
        ".....KKWWWWWWWWWWWWWWWWKKKK.....",
        "......wwwwWWWWWWWWWWWWWWWK......",
    ]

    /// Flat out with the head down and the eyes shut.
    static let sleeping = [
        "..........HHHHHHHHKKKKK.........",
        ".......HHHKKKKKKKKKKKKKKKK......",
        "....YYHKKKKKKKKKKKKKKWWWKWWWK...",
        "...YYyKKKKKKKKKKKKKKKKkkkKkkkKY.",
        "....yKKKKKKKKKKKKKKKKKKKKKKKYYYY",
        ".....KKWWWWWWWWWWWWWWWWKKKKyyy..",
        "......wwwwWWWWWWWWWWWWWWWK......",
        "........wwwwwwwwwwwwwwww........",
    ]

    /// On its back, feet in the air and eyes crossed out: the end of a fall.
    static let onBack = [
        "..........YY.....YY.............",
        "..........yY.....yY.............",
        ".........KwWWWWWWWWWK...........",
        ".......HKWWWWWWWWWWWWWK...KKK...",
        "......HKKWWWWWWWWWWWWWWKKKWkWK..",
        ".....HKKKKWWWWWWWWWWWWKKKKKWkWKY",
        ".....KKKKKKKKKKKKKKKKKKKKKKKKKYY",
        "......KKKKKKKKKKKKKKKKKKKKKKKKK.",
        ".........KKKKKKKKKKKKKKKKKKK....",
    ]
}
