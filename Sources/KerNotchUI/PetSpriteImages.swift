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

/// Every sheet's images, drawn the first time a pet is shown and kept for the
/// app's lifetime, so a routine starting over never redraws a pixel.
@MainActor
enum PetSpriteImages {
    private static var sets: [PetSpriteSheet: PetSpriteImageSet] = [:]

    static func images(for sheet: PetSpriteSheet) -> PetSpriteImageSet {
        if let cached = sets[sheet] {
            return cached
        }
        let images = PetSpriteImageSet(sheet: sheet)
        sets[sheet] = images
        return images
    }
}

/// One frame of `sheet` as an sRGB image, a pixel per art pixel, rows from the
/// top. `nil` only if Core Graphics cannot make an image at all.
func petSpriteImage(of sheet: PetSpriteSheet, frame: PetFrame, facing: PetFacing) -> CGImage? {
    let bytesPerPixel = 4
    var bytes = [UInt8](repeating: 0, count: sheet.width * sheet.height * bytesPerPixel)
    for row in 0..<sheet.height {
        for column in 0..<sheet.width {
            guard let color = sheet.color(of: frame, facing: facing, column: column, row: row) else { continue }
            let offset = (row * sheet.width + column) * bytesPerPixel
            bytes[offset] = color.red
            bytes[offset + 1] = color.green
            bytes[offset + 2] = color.blue
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
        width: sheet.width,
        height: sheet.height,
        bitsPerComponent: 8,
        bitsPerPixel: 8 * bytesPerPixel,
        bytesPerRow: sheet.width * bytesPerPixel,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}
