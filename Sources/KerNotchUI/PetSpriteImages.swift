import CoreGraphics
import Foundation
import KerNotchCore

/// A sprite sheet's frames as images, facing both ways.
///
/// Each image is the art at one pixel per art pixel — 32 by 24 for the Shiba,
/// three kilobytes — shown at its own size on a Retina panel, so the whole pet
/// costs less memory than a single artwork thumbnail.
struct PetSpriteImageSet {
    private let images: [Key: CGImage]

    init(sheet: PetSpriteSheet) {
        var images: [Key: CGImage] = [:]
        for frame in PetFrame.allCases {
            for facing in [PetFacing.left, .right] {
                images[Key(frame: frame, facing: facing)] = petSpriteImage(of: sheet, frame: frame, facing: facing)
            }
        }
        self.images = images
    }

    func image(for frame: PetFrame, facing: PetFacing) -> CGImage? {
        images[Key(frame: frame, facing: facing)]
    }

    private struct Key: Hashable {
        let frame: PetFrame
        let facing: PetFacing
    }
}

/// The effects as images, as drawn and mirrored.
struct PetEffectImageSet {
    private let images: [Key: CGImage]

    init(art: PetEffectArt) {
        var images: [Key: CGImage] = [:]
        for effect in PetEffect.allCases {
            for mirrored in [false, true] {
                images[Key(effect: effect, mirrored: mirrored)] = petEffectImage(
                    of: art, effect: effect, mirrored: mirrored)
            }
        }
        self.images = images
    }

    func image(for effect: PetEffect, mirrored: Bool) -> CGImage? {
        images[Key(effect: effect, mirrored: mirrored)]
    }

    private struct Key: Hashable {
        let effect: PetEffect
        let mirrored: Bool
    }
}

/// Every sheet's images, drawn the first time a pet is shown and kept for the
/// app's lifetime, so a routine starting over never redraws a pixel.
@MainActor
enum PetSpriteImages {
    private static var sets: [PetSpriteSheet: PetSpriteImageSet] = [:]
    private static var effectSets: [PetEffectArt: PetEffectImageSet] = [:]

    static func images(for sheet: PetSpriteSheet) -> PetSpriteImageSet {
        if let cached = sets[sheet] {
            return cached
        }
        let images = PetSpriteImageSet(sheet: sheet)
        sets[sheet] = images
        return images
    }

    static func images(for art: PetEffectArt) -> PetEffectImageSet {
        if let cached = effectSets[art] {
            return cached
        }
        let images = PetEffectImageSet(art: art)
        effectSets[art] = images
        return images
    }
}

/// One frame of `sheet` as an sRGB image, a pixel per art pixel, rows from the
/// top. `nil` only if Core Graphics cannot make an image at all.
func petSpriteImage(of sheet: PetSpriteSheet, frame: PetFrame, facing: PetFacing) -> CGImage? {
    pixelArtImage(width: sheet.width, height: sheet.height) { column, row in
        sheet.color(of: frame, facing: facing, column: column, row: row)
    }
}

/// One effect of `art` as an sRGB image, a pixel per art pixel.
func petEffectImage(of art: PetEffectArt, effect: PetEffect, mirrored: Bool) -> CGImage? {
    pixelArtImage(width: art.pixelWidth(of: effect), height: art.pixelHeight(of: effect)) { column, row in
        art.color(of: effect, mirrored: mirrored, column: column, row: row)
    }
}

private func pixelArtImage(width: Int, height: Int, color: (Int, Int) -> PetColor?) -> CGImage? {
    guard width > 0, height > 0 else { return nil }
    let bytesPerPixel = 4
    var bytes = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
    for row in 0..<height {
        for column in 0..<width {
            guard let pixel = color(column, row) else { continue }
            let offset = (row * width + column) * bytesPerPixel
            bytes[offset] = pixel.red
            bytes[offset + 1] = pixel.green
            bytes[offset + 2] = pixel.blue
            bytes[offset + 3] = UInt8.max
        }
    }

    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let provider = CGDataProvider(data: Data(bytes) as CFData)
    else {
        return nil
    }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8 * bytesPerPixel,
        bytesPerRow: width * bytesPerPixel,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}
