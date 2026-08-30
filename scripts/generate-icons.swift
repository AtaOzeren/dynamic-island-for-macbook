#!/usr/bin/env swift

// Renders every NotchFlow image asset from vector drawing code.
//
// The icons are generated rather than hand-exported so the design is reviewable
// as source: a change to the palette or the notch proportions below is a diff,
// not an opaque binary swap. Run `./scripts/generate-icons.swift` after editing;
// `scripts/check-assets.sh` asserts the committed PNGs match what this emits.

import AppKit
import Foundation

// MARK: - Design tokens

/// The island's own palette, mirroring `IslandSurface` in `NotchFlowUI`: the
/// notch reads as the physical cutout's black, and the activity accent is the
/// one saturated colour the product uses to say "something is happening".
private enum Palette {
    static let backdropTop = NSColor(srgbRed: 0.16, green: 0.14, blue: 0.24, alpha: 1)
    static let backdropBottom = NSColor(srgbRed: 0.04, green: 0.04, blue: 0.06, alpha: 1)
    static let notchBlack = NSColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1)
    static let accentLeading = NSColor(srgbRed: 0.35, green: 0.83, blue: 0.98, alpha: 1)
    static let accentTrailing = NSColor(srgbRed: 0.62, green: 0.44, blue: 0.98, alpha: 1)
    static let accentGlow = NSColor(srgbRed: 0.45, green: 0.60, blue: 1, alpha: 0.42)
    static let rimHighlight = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16)
}

/// Proportions expressed as fractions of the icon's content box so every size
/// is the same drawing rather than ten separately-tuned ones.
///
/// The notch is flush with the top edge because that is the product's whole
/// premise — it hangs from the screen's edge. Floating it inward reads as an
/// abstract bar and loses the metaphor at small sizes.
private enum Proportion {
    /// Apple's macOS app icons inset their artwork inside the 1024pt canvas.
    static let contentInset: CGFloat = 0.100
    /// The squircle radius Apple's macOS icon grid uses, as a fraction of the
    /// content box.
    static let cornerRadius: CGFloat = 0.225
    static let notchWidth: CGFloat = 0.440
    static let notchHeight: CGFloat = 0.150
    static let islandWidth: CGFloat = 0.720
    static let islandHeight: CGFloat = 0.185
    static let islandGap: CGFloat = 0.105
    /// The island's glow, which gives the icon depth at large sizes and is what
    /// keeps the lower half from reading as dead space.
    static let glowSpread: CGFloat = 0.140
}

// MARK: - Drawing

/// A rectangle with only its bottom two corners rounded, the shape of the
/// physical notch cutout.
private func notchPath(in rect: CGRect, radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.line(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    path.appendArc(
        withCenter: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
        radius: radius,
        startAngle: 180,
        endAngle: 270
    )
    path.line(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
    path.appendArc(
        withCenter: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
        radius: radius,
        startAngle: 270,
        endAngle: 360
    )
    path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.close()
    return path
}

/// The app icon: the notch cutout with the island expanding beneath it, which is
/// the one thing the product does, drawn so it survives being scaled to 16pt.
private func drawAppIcon(side: CGFloat) {
    let inset = side * Proportion.contentInset
    let content = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)

    let backdrop = NSBezierPath(
        roundedRect: content,
        xRadius: content.width * Proportion.cornerRadius,
        yRadius: content.width * Proportion.cornerRadius
    )
    backdrop.addClip()
    let gradient = NSGradient(starting: Palette.backdropTop, ending: Palette.backdropBottom)
    gradient?.draw(in: content, angle: -90)

    let notchWidth = content.width * Proportion.notchWidth
    let notchHeight = content.height * Proportion.notchHeight
    let notch = CGRect(
        x: content.midX - notchWidth / 2,
        y: content.maxY - notchHeight,
        width: notchWidth,
        height: notchHeight
    )
    Palette.notchBlack.setFill()
    notchPath(in: notch, radius: notchHeight * 0.44).fill()

    let islandWidth = content.width * Proportion.islandWidth
    let islandHeight = content.height * Proportion.islandHeight
    let island = CGRect(
        x: content.midX - islandWidth / 2,
        y: notch.minY - content.height * Proportion.islandGap - islandHeight,
        width: islandWidth,
        height: islandHeight
    )

    let capsule = NSBezierPath(
        roundedRect: island,
        xRadius: islandHeight / 2,
        yRadius: islandHeight / 2
    )

    // A blurred shadow rather than a clipped radial gradient: a gradient reaches
    // its clip boundary before its alpha reaches zero, leaving a visible rim.
    NSGraphicsContext.saveGraphicsState()
    let bloom = NSShadow()
    bloom.shadowColor = Palette.accentGlow
    bloom.shadowBlurRadius = content.height * Proportion.glowSpread
    bloom.shadowOffset = .zero
    bloom.set()
    Palette.accentLeading.setFill()
    capsule.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    capsule.addClip()
    NSGradient(starting: Palette.accentLeading, ending: Palette.accentTrailing)?
        .draw(in: island, angle: 0)
    NSGradient(
        colors: [NSColor.white.withAlphaComponent(0.34), NSColor.white.withAlphaComponent(0)],
        atLocations: [0, 1],
        colorSpace: .sRGB
    )?.draw(in: CGRect(
        x: island.minX,
        y: island.midY,
        width: island.width,
        height: island.height / 2
    ), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    let rim = NSBezierPath(
        roundedRect: content.insetBy(dx: side * 0.006, dy: side * 0.006),
        xRadius: content.width * Proportion.cornerRadius,
        yRadius: content.width * Proportion.cornerRadius
    )
    Palette.rimHighlight.setStroke()
    rim.lineWidth = side * 0.008
    rim.stroke()
}

/// The status item glyph, drawn as a pure alpha mask so AppKit can treat it as a
/// template image and tint it for the light, dark, and reduced-contrast menu
/// bars instead of the app shipping a bitmap per appearance.
private func drawMenuBarIcon(side: CGFloat) {
    let content = CGRect(x: 0, y: 0, width: side, height: side).insetBy(
        dx: side * 0.06,
        dy: side * 0.16
    )
    NSColor.black.setFill()

    let notchWidth = content.width * 0.62
    let notchHeight = content.height * 0.42
    let notch = CGRect(
        x: content.midX - notchWidth / 2,
        y: content.maxY - notchHeight,
        width: notchWidth,
        height: notchHeight
    )
    notchPath(in: notch, radius: notchHeight * 0.42).fill()

    let islandHeight = content.height * 0.34
    let island = CGRect(
        x: content.minX,
        y: content.minY,
        width: content.width,
        height: islandHeight
    )
    NSBezierPath(roundedRect: island, xRadius: islandHeight / 2, yRadius: islandHeight / 2).fill()
}

// MARK: - Emission

private func writePNG(pixels: Int, at url: URL, draw: (CGFloat) -> Void) throws {
    guard
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        throw IconError.allocationFailed(pixels)
    }
    representation.size = CGSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw IconError.encodingFailed(url)
    }
    try data.write(to: url)
}

private enum IconError: Error, CustomStringConvertible {
    case allocationFailed(Int)
    case encodingFailed(URL)

    var description: String {
        switch self {
        case let .allocationFailed(pixels): "Could not allocate a \(pixels)px bitmap."
        case let .encodingFailed(url): "Could not encode PNG data for \(url.lastPathComponent)."
        }
    }
}

/// Every pixel size macOS requires of an app icon, keyed by the filename the
/// asset catalog's `Contents.json` refers to.
private let appIconPixelSizes = [16, 32, 64, 128, 256, 512, 1024]
private let menuBarPixelSizes = [18, 36, 54]

let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let catalog = repositoryRoot.appending(path: "NotchFlow/Assets.xcassets")
let appIconSet = catalog.appending(path: "AppIcon.appiconset")
let menuBarSet = catalog.appending(path: "MenuBarIcon.imageset")

do {
    try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: menuBarSet, withIntermediateDirectories: true)

    for pixels in appIconPixelSizes {
        let url = appIconSet.appending(path: "AppIcon-\(pixels).png")
        try writePNG(pixels: pixels, at: url, draw: drawAppIcon)
        print("wrote \(url.lastPathComponent)")
    }
    for pixels in menuBarPixelSizes {
        let url = menuBarSet.appending(path: "MenuBarIcon-\(pixels).png")
        try writePNG(pixels: pixels, at: url, draw: drawMenuBarIcon)
        print("wrote \(url.lastPathComponent)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
