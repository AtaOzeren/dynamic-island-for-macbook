/// The penguin's pixel art: its palette, the blocks its frames are built from,
/// and the frames themselves.
///
/// Tux's colours in a three-quarter view — a dark coat, a white front and eye
/// patches, a yellow beak and feet — with the beak and the eyes turned the way
/// it faces, so its walk has a direction and mirroring it turns it round.
///
/// `K` coat, and `H` its rim where the light catches it: a dark penguin on the
/// island's black would otherwise be a white belly floating on nothing, so the
/// coat is slate rather than black and its outline is lit. `k` pupils, `W`
/// the white front and eye patches, `w` the white in shadow, `Y` beak and feet
/// and `y` their shade, `M` inside the open beak. `G` and `g` are the grey of
/// the headset and the laptop, `S` the laptop's screen and `L` its prompt, `N`
/// the fishing rod, `B` and `b` the fish and the water under the ice.
enum PenguinArt {
    static let palette: [Character: PetColor] = [
        "K": PetColor(hex: 0x353A47),
        "H": PetColor(hex: 0x6A7388),
        "k": PetColor(hex: 0x0E0F12),
        "W": PetColor(hex: 0xF7F7F2),
        "w": PetColor(hex: 0xC6CAD3),
        "Y": PetColor(hex: 0xF8C02C),
        "y": PetColor(hex: 0xD98A16),
        "M": PetColor(hex: 0xB8475A),
        "G": PetColor(hex: 0xA7ADB5),
        "g": PetColor(hex: 0x646A72),
        "S": PetColor(hex: 0x122218),
        "L": PetColor(hex: 0x6BF08A),
        "N": PetColor(hex: 0xB98252),
        "B": PetColor(hex: 0x8FD0FF),
        "b": PetColor(hex: 0x3C8DDB),
    ]

    static let frames: [PetFrame: [String]] = [
        .stand: stand,
        .standBlink: blinkingHead + body + feet,
        .strideA: shifting(head, by: -1) + shifting(Array(body.prefix(6)), by: -1) + body.dropFirst(6) + strideAFeet,
        .strideB: shifting(head, by: 1) + shifting(Array(body.prefix(6)), by: 1) + body.dropFirst(6) + strideBFeet,
        .shakeLeft: shaking(by: -1),
        .shakeRight: shaking(by: 1),
        .crouch: emptyRows(2) + head + crouchingBody + feet,
        .hop: flappingOut(head, over: bareBody + hopFeet),
        .sit: sit,
        .sitBlink: emptyRows(4) + blinkingHead + sittingBody,
        .sitNod: sitNod,
        .dazed: emptyRows(4) + dazedHead + sittingBody,
        .headset: wearingHeadset(sit, headTop: 4),
        .headsetBlink: wearingHeadset(emptyRows(4) + blinkingHead + sittingBody, headTop: 4),
        .headsetNod: wearingHeadset(sitNod, headTop: 5),
        .lie: emptyRows(13) + lying,
        .lieBlink: emptyRows(13) + lyingBlink,
        .sleep: emptyRows(16) + sleeping,
        .flippersOut: flappingOut(head, over: bareBody + feet),
        .flippersUp: flappingUp(head),
        .cheerOut: flappingOut(smilingHead, over: bareBody + feet),
        .cheerUp: cheerUp,
        .beam: beam,
        .sitBeam: emptyRows(4) + smilingHead + sittingBody,
        .waveLow: stamping(nearFlipperUp, onto: smilingHead + bareBody + feet, column: 1, row: 7),
        .waveHigh: stamping(raisedFlipper, onto: smilingHead + bareBody + feet, column: 3, row: 3),
        .flipperRaised: stamping(raisedFlipper, onto: head + bareBody + feet, column: 3, row: 3),
        .footTapDown: footTapDown,
        .footTapUp: Array(footTapDown.prefix(22)) + tappingFeet,
        .squawk: Array(head.prefix(6)) + squawkingBeak + body.dropFirst() + feet,
        .standYawn: Array(shutHead.prefix(6)) + yawningBeak + body.dropFirst(2) + feet,
        .stretch: stamping(backFlipper, onto: shutHead + bareBody + feet, column: 2, row: 14),
        .fanUp: stamping(farFlipperFanningUp, onto: liddedHead + body + feet, column: 23, row: 7),
        .fanDown: stamping(farFlipperFanningDown, onto: liddedHead + body + feet, column: 22, row: 11),
        .preenA: preenHead + body.dropFirst(3) + feet,
        .preenB: shifting(preenHead, by: -1) + body.dropFirst(3) + feet,
        .lookUp: lookingUpHead + squawkingBeak + body.dropFirst() + feet,
        .holdFish: stamping(heldFish, onto: stand, column: 23, row: 5),
        .gulp: lowering(beam, columns: 9..<27, topRows: 9),
        .danceLeft: shifting(Array(cheerUp.prefix(15)), by: -1) + cheerUp[15..<22] + strideAFeet,
        .danceRight: shifting(Array(cheerUp.prefix(15)), by: 1) + cheerUp[15..<22] + strideBFeet,
        .swayLeft: shifting(Array(beam.prefix(15)), by: -1) + beam.dropFirst(15),
        .swayRight: shifting(Array(beam.prefix(15)), by: 1) + beam.dropFirst(15),
        .slip: leaningBack(flappingUp(dazedHead)) + slippingFeet,
        .typing: typing(on: sit),
        .typingLift: stamping(
            liftedFlipper, onto: stamping(laptopCursorOff, onto: sit, column: 20, row: 15), column: 22, row: 17),
        .typingBlink: typing(on: emptyRows(4) + blinkingHead + sittingBody),
        .fishing: fishing(on: sit, rod: rod),
        .fishingBite: fishing(on: sit, rod: bentRod),
        .fishingBlink: fishing(on: emptyRows(4) + blinkingHead + sittingBody, rod: rod),
        .slide: emptyRows(16) + sliding,
        .onBack: emptyRows(15) + onBack,
    ]

    private static let stand = head + body + feet
    private static let sit = emptyRows(4) + head + sittingBody
    private static let sitNod = lowering(sit, columns: 9..<27, topRows: 13)
    private static let beam = smilingHead + body + feet
    private static let cheerUp = flappingUp(smilingHead)
    private static let footTapDown = stamping(akimboFlipper, onto: liddedHead + bareBody + feet, column: 2, row: 13)

    /// Both flippers held out level, on a body with the near flipper lifted
    /// off it.
    private static func flappingOut(_ head: [String], over body: [String]) -> [String] {
        let near = stamping(nearFlipperOut, onto: head + body, column: 0, row: 11)
        return stamping(farFlipperOut, onto: near, column: 23, row: 11)
    }

    /// Both flippers raised, over the standing body.
    private static func flappingUp(_ head: [String]) -> [String] {
        let near = stamping(nearFlipperUp, onto: head + bareBody + feet, column: 1, row: 7)
        return stamping(farFlipperUp, onto: near, column: 23, row: 8)
    }

    /// Flippers out and the head and shoulders thrown a pixel to one side,
    /// shaking the water off.
    private static func shaking(by columns: Int) -> [String] {
        let flapping = flappingOut(head, over: bareBody + feet)
        return shifting(head, by: columns) + shifting(Array(flapping[9..<15]), by: columns) + body.dropFirst(6)
            + feet
    }

    /// Leaning back as the feet go from under it: the higher a row, the
    /// further back.
    private static func leaningBack(_ rows: [String]) -> [String] {
        rows.prefix(22).enumerated().map { row, line in
            switch row {
            case ..<8: shifting([line], by: -3)[0]
            case ..<15: shifting([line], by: -2)[0]
            case ..<20: shifting([line], by: -1)[0]
            default: line
            }
        }
    }

    private static func wearingHeadset(_ rows: [String], headTop: Int) -> [String] {
        stamping(headset, onto: rows, column: 0, row: headTop - 1)
    }

    private static func typing(on rows: [String]) -> [String] {
        stamping(typingFlipper, onto: stamping(laptop, onto: rows, column: 20, row: 15), column: 22, row: 18)
    }

    private static func fishing(on rows: [String], rod: [String]) -> [String] {
        let holding = stamping(rodFlipper, onto: rows, column: 22, row: 16)
        return stamping(iceHole, onto: stamping(rod, onto: holding, column: 23, row: 10), column: 26, row: 22)
    }
}

extension PenguinArt: PetArtComposer {
    static let artWidth = 32
}

/// The head in each of its looks. The head is the same block in every
/// standing and sitting frame, so the eyes and the beak are always at these
/// pixels.
extension PenguinArt {
    static let head = [
        "..............HKKK..............",
        "...........HHKKKKKKK............",
        "..........HKKKKKKKKKK...........",
        ".........HKKKKWWKKWWWK..........",
        ".........HKKKWWkKWWWkK..........",
        ".........HKKKWWkKWWWkKK.........",
        ".........HKKKKWKKYYYYYYY........",
        ".........HKKKKKYYYYYYYYYY.......",
        ".........HKKKKKKyyyyyyyy........",
    ]

    /// The pupils gone behind a lid for a moment.
    static let blinkingHead = [
        "..............HKKK..............",
        "...........HHKKKKKKK............",
        "..........HKKKKKKKKKK...........",
        ".........HKKKKWWKKWWWK..........",
        ".........HKKKkkkKkkkkK..........",
        ".........HKKKWWWKWWWWKK.........",
        ".........HKKKKWKKYYYYYYY........",
        ".........HKKKKKYYYYYYYYYY.......",
        ".........HKKKKKKyyyyyyyy........",
    ]

    /// Eyes shut for longer: stretching, yawning.
    static let shutHead = [
        "..............HKKK..............",
        "...........HHKKKKKKK............",
        "..........HKKKKKKKKKK...........",
        ".........HKKKKKKKKKKKK..........",
        ".........HKKKkkkKkkkkK..........",
        ".........HKKKWWWKWWWWKK.........",
        ".........HKKKKWKKYYYYYYY........",
        ".........HKKKKKYYYYYYYYYY.......",
        ".........HKKKKKKyyyyyyyy........",
    ]

    /// Eyes curved shut with delight.
    static let smilingHead = [
        "..............HKKK..............",
        "...........HHKKKKKKK............",
        "..........HKKKKKKKKKK...........",
        ".........HKKKKWKKKWWKK..........",
        ".........HKKKWKWKWKKWK..........",
        ".........HKKKKKKKKKKKKK.........",
        ".........HKKKKKKKYYYYYYY........",
        ".........HKKKKKYYYYYYYYYY.......",
        ".........HKKKKKKyyyyyyyy........",
    ]

    /// The tops of the eyes lidded: impatient, or cooling off.
    static let liddedHead = [
        "..............HKKK..............",
        "...........HHKKKKKKK............",
        "..........HKKKKKKKKKK...........",
        ".........HKKKKKKKKKKKK..........",
        ".........HKKKWWkKWWWkK..........",
        ".........HKKKWWkKWWWkKK.........",
        ".........HKKKKWKKYYYYYYY........",
        ".........HKKKKKYYYYYYYYYY.......",
        ".........HKKKKKKyyyyyyyy........",
    ]

    /// Crossed-out eyes, seeing stars.
    static let dazedHead = [
        "..............HKKK..............",
        "...........HHKKKKKKK............",
        "..........HKKKKKKKKKK...........",
        ".........HKKKkWkKkWkWK..........",
        ".........HKKKWkWKWkWWK..........",
        ".........HKKKkWkKkWkWKK.........",
        ".........HKKKKWKKYYYYYYY........",
        ".........HKKKKKYYYYYYYYYY.......",
        ".........HKKKKKKyyyyyyyy........",
    ]

    /// Crown and eyes of a head looking up, over an open beak.
    static let lookingUpHead = [
        "..............HKKK..............",
        "...........HHKKKKKKK............",
        "..........HKKKKKKKKKK...........",
        ".........HKKKKWkKKWWkK..........",
        ".........HKKKWWWKWWWWK..........",
        ".........HKKKWWWKWWWWKK.........",
    ]

    /// The beak wide open, down over the chin.
    static let squawkingBeak = [
        ".........HKKKKWKKYYYYYYYYY......",
        ".........HKKKKKKMMMMMMMM........",
        ".........HKKKKKKMMMMYYY.........",
        ".........HKKKKKYYYYYYYK.........",
    ]

    /// The beak open as far as it goes, down to the chest.
    static let yawningBeak = [
        ".........HKKKKWKKYYYYYYYY.......",
        ".........HKKKKKKYMMMMMM.........",
        ".........HKKKKKKMMMMMMM.........",
        ".........HKKKKKKYMMMMY..........",
        ".........HKKKKKKYYYYYK..........",
    ]

    /// The head bent down with the beak in the chest feathers, the eyes shut:
    /// preening. Two rows lower than the head held up.
    static let preenHead = [
        "................................",
        "................................",
        "..............HKKK..............",
        "...........HHKKKKKKK............",
        "..........HKKKKKKKKKK...........",
        ".........HKKKKKKKKKKKK..........",
        ".........HKKKkkkKkkkkK..........",
        ".........HKKKWWWKWWWWKK.........",
        ".........HKKKKKKKKKKKK..........",
        ".........HKKKKKYYYYKK...........",
        "........HKKKKKWYYYYWWK..........",
        "........HKKKKWWWYYWWWK..........",
    ]
}
