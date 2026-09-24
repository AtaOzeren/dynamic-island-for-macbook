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

    /// How the pet holds itself in this frame, which decides how it gets from
    /// here to any other frame.
    public var posture: PetPosture {
        switch self {
        case .stand, .standBlink, .strideA, .strideB, .shakeLeft, .shakeRight:
            .standing
        case .crouch:
            .crouching
        case .hop:
            .airborne
        case .sit, .sitBlink, .sitPant, .sitWag, .sitNod, .bark, .yawn, .curious, .curiousLow, .earsBack,
            .pawUp, .dazed, .holdBone, .holdBoneWag, .headset, .headsetBlink, .headsetNod:
            .sitting
        case .lie, .lieBlink, .sleep, .lieSad, .lieDazed:
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
/// the way a dog does.
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
