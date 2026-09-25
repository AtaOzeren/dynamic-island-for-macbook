/// One pose a pet can be drawn in.
///
/// Every frame is drawn facing right. Facing left is the same art mirrored,
/// which is why it is a separate value rather than a second set of frames that
/// would have to be kept in step with the first.
///
/// One catalogue for every pet: the poses they share — standing, the walk, the
/// crouch, sitting, lying, asleep — carry the same name, so moving from one to
/// another works the same for all of them, and each pet's sheet draws the
/// poses of its own on top.
public enum PetFrame: String, CaseIterable, Sendable {
    case stand
    case standBlink
    case strideA
    case strideB
    /// Shaking itself dry: the head and tail thrown to one side, then the other.
    case shakeLeft
    case shakeRight
    case crouch
    /// In the air, legs tucked under — drawn raised by the pose's lift.
    case hop
    case sit
    case sitBlink
    case sitPant
    case sitWag
    /// The head dipped a row, for nodding along to music.
    case sitNod
    case bark
    case yawn
    /// One ear flopped forward and the eye turned up: asking something.
    case curious
    case curiousLow
    /// Ears flattened back and the head low: sorry about something.
    case earsBack
    case pawUp
    /// Crossed-out eye, seeing stars.
    case dazed
    case holdBone
    case holdBoneWag
    case headset
    case headsetBlink
    case headsetNod
    case lie
    case lieBlink
    case sleep
    /// Lying with the chin on the paws and the ears back.
    case lieSad
    /// Flat out, crossed-out eye, tongue out.
    case lieDazed
    /// Front down, rear up: the stretch dogs make on waking, and the start of
    /// digging.
    case playBow
    case digA
    case digB
    /// Flippers held out level, and raised: the two strokes of a flap.
    case flippersOut
    case flippersUp
    /// The same, beaming: flapping for joy.
    case cheerOut
    case cheerUp
    /// Standing with the eyes curved shut with delight.
    case beam
    /// A flipper up and waving, beaming: hello.
    case waveLow
    case waveHigh
    /// A flipper raised high, like a hand: asking something.
    case flipperRaised
    /// A flipper on the hip and a foot tapping: waiting, impatiently.
    case footTapUp
    case footTapDown
    /// Beak wide open, calling out.
    case squawk
    /// Standing with the beak open as far as it goes and the eyes shut.
    case standYawn
    /// Flippers swept back and eyes shut: the stretch on waking.
    case stretch
    /// A flipper fanning the face, up and down.
    case fanUp
    case fanDown
    /// The beak in the chest feathers, combing them.
    case preenA
    case preenB
    /// Looking up with the beak open, ready to catch something.
    case lookUp
    case holdFish
    /// Swallowing, beaming.
    case gulp
    /// Leaning one way and the other with the flippers up: dancing.
    case danceLeft
    case danceRight
    /// Leaning one way and the other, beaming: swaying to music.
    case swayLeft
    case swayRight
    /// Leaning back as the feet go from under it: the start of a fall.
    case slip
    /// Sitting, beaming.
    case sitBeam
    /// At a tiny laptop: a flipper on the keys with the cursor lit, the
    /// flipper lifted with the cursor out, and a blink.
    case typing
    case typingLift
    case typingBlink
    /// Sitting with a rod over a hole in the ice, the rod bent by a bite, and
    /// a blink.
    case fishing
    case fishingBite
    case fishingBlink
    /// Flat on its belly, head forward: sliding.
    case slide
    /// On its back with its feet in the air: the end of a fall.
    case onBack

    /// How the pet holds itself in this frame, which decides how it gets from
    /// here to any other frame.
    public var posture: PetPosture {
        switch self {
        case .stand, .standBlink, .strideA, .strideB, .shakeLeft, .shakeRight, .flippersOut, .flippersUp,
            .cheerOut, .cheerUp, .beam, .waveLow, .waveHigh, .flipperRaised, .footTapUp, .footTapDown, .squawk,
            .standYawn, .stretch, .fanUp, .fanDown, .preenA, .preenB, .lookUp, .holdFish, .gulp, .danceLeft,
            .danceRight, .swayLeft, .swayRight, .slip:
            .standing
        case .crouch:
            .crouching
        case .hop:
            .airborne
        case .sit, .sitBlink, .sitPant, .sitWag, .sitNod, .bark, .yawn, .curious, .curiousLow, .earsBack,
            .pawUp, .dazed, .holdBone, .holdBoneWag, .headset, .headsetBlink, .headsetNod, .sitBeam, .typing,
            .typingLift, .typingBlink, .fishing, .fishingBite, .fishingBlink:
            .sitting
        case .lie, .lieBlink, .sleep, .lieSad, .lieDazed, .slide, .onBack:
            .lying
        case .playBow, .digA, .digB:
            .bowing
        }
    }

    /// On its haunches. `crouch` is the step between standing and sitting and
    /// counts as neither.
    public var isSitting: Bool {
        posture == .sitting
    }
}

/// How the pet holds itself.
///
/// Each posture has one way into it and out of it — sitting and lying pass
/// through the crouch, a pet in the air lands before anything else — so a
/// routine can start from whatever frame the pet was caught in and still move
/// the way an animal does.
public enum PetPosture: Sendable {
    case standing
    case crouching
    case airborne
    case sitting
    case lying
    case bowing
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
    public static let shiba = PetSpriteSheet(
        width: 32,
        height: 24,
        pixelsPerPoint: 2,
        palette: ShibaArt.palette,
        frames: ShibaArt.frames
    )
}

extension PetSpriteSheet {
    /// A penguin in the likeness of Tux: slate coat, white front, yellow beak
    /// and feet — 32 × 24 pixels, drawn in 16 × 12 points like the Shiba.
    public static let penguin = PetSpriteSheet(
        width: 32,
        height: 24,
        pixelsPerPoint: 2,
        palette: PenguinArt.palette,
        frames: PenguinArt.frames
    )
}
