#!/usr/bin/env swift

// Renders every KerNotch image asset from vector drawing code.
//
// The icons are generated rather than hand-exported so the design is reviewable
// as source: a change to the palette or the island proportions below is a diff,
// not an opaque binary swap. Run `./scripts/generate-icons.swift` after editing
// and commit the PNGs it rewrites; `scripts/check-assets.sh` asserts that every
// size the asset catalog declares is present and correctly sized.

import AppKit
import Foundation

// MARK: - Design tokens

/// Apple system colours, so the icon sits among the system's own apps: a light
/// face, the island in the notch's black, and one saturated accent that says
/// "something is live".
private enum Palette {
    /// White easing into light-appearance `systemGray5`.
    static let bodyFace = gradient([(srgb(0xFFFFFF), 0), (srgb(0xE5E5EA), 1)])
    static let bodyShadow = srgb(0x000000, alpha: 0.30)
    static let bodyRim = gradient([(srgb(0xFFFFFF, alpha: 0.90), 0), (srgb(0x000000, alpha: 0.10), 1)])
    /// Dark-appearance `systemGray5` settling into black by the lower third, so
    /// the island reads as a glossy surface rather than a flat hole.
    static let islandFace = gradient([(srgb(0x2C2C2E), 0), (srgb(0x000000), 0.7)])
    static let islandShadow = srgb(0x000000, alpha: 0.30)
    static let islandRim = gradient([(srgb(0xFFFFFF, alpha: 0.22), 0), (srgb(0xFFFFFF, alpha: 0), 1)])
    /// Dark-appearance `systemGreen`, the green macOS shows while the camera is
    /// in use, so the dot reads as "live" without explanation.
    static let liveDot = srgb(0x30D158)
    static let liveGlow = srgb(0x30D158, alpha: 0.75)
    static let menuBarInk = srgb(0x000000)
}

/// The 1024pt design's measurements over the canvas side, so every pixel size
/// is the same drawing rather than seven separately-tuned ones.
private enum Proportion {
    /// Apple's macOS icon grid centres an 824pt body in the 1024pt canvas.
    static let bodyInset: CGFloat = 100 / 1024
    /// The grid's corner radius, drawn as a continuous corner.
    static let bodyCornerRadius: CGFloat = 185.4 / 1024
    static let bodyShadowOffset: CGFloat = 10 / 1024
    static let bodyShadowBlur: CGFloat = 24 / 1024
    static let rimWidth: CGFloat = 3 / 1024
    static let islandWidth: CGFloat = 560 / 1024
    static let islandHeight: CGFloat = 196 / 1024
    static let islandShadowOffset: CGFloat = 14 / 1024
    static let islandShadowBlur: CGFloat = 34 / 1024
    static let liveDotDiameter: CGFloat = 76 / 1024
    static let liveGlowBlur: CGFloat = 30 / 1024
}

/// The status item glyph in points of the 18pt box the status item sizes its
/// image to. Whole-point edges keep the island crisp at 1x, 2x, and 3x, and the
/// dot is proportionally larger than the app icon's so the knockout stays
/// visible at menu bar size.
private enum MenuBarProportion {
    static let box: CGFloat = 18
    static let island = CGRect(x: 1, y: 6, width: 16, height: 6)
    static let liveDotDiameter: CGFloat = 2.6
}

/// The widely used approximation of Apple's continuous corner, in multiples of
/// the corner radius. `x` runs from the corner back along the incoming edge and
/// `y` inward along the outgoing edge. A circular arc leaves its edge one radius
/// from the corner; this curve leaves it `reach` radii out and eases its
/// curvature in, which is what separates a system icon's silhouette from a plain
/// rounded rectangle.
private enum ContinuousCorner {
    static let reach: CGFloat = 1.52866483
    /// Three cubic segments from the incoming edge to the outgoing edge, each as
    /// its two control points followed by its end point.
    static let segments: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 1.08849323, y: 0), CGPoint(x: 0.86840689, y: 0), CGPoint(x: 0.63149399, y: 0.07491100)),
        (CGPoint(x: 0.37282392, y: 0.16905899), CGPoint(x: 0.16905899, y: 0.37282392), CGPoint(x: 0.07491100, y: 0.63149399)),
        (CGPoint(x: 0, y: 0.86840689), CGPoint(x: 0, y: 1.08849323), CGPoint(x: 0, y: reach)),
    ]
}

private func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// A gradient whose stop locations run from the top (0) to the bottom (1).
private func gradient(_ stops: [(color: CGColor, location: CGFloat)]) -> CGGradient {
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: stops.map(\.color) as CFArray,
            locations: stops.map(\.location)
        )
    else {
        fatalError("Could not build a gradient from \(stops).")
    }
    return gradient
}

// MARK: - Shapes

private func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let radius = min(radius, min(rect.width, rect.height) / 2 / ContinuousCorner.reach)
    // Clockwise from the top edge; each corner is its vertex plus the directions
    // travelled into and out of it.
    let corners: [(vertex: CGPoint, incoming: CGVector, outgoing: CGVector)] = [
        (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1)),
        (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0)),
        (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1)),
        (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0)),
    ]

    let path = CGMutablePath()
    for corner in corners {
        func point(_ offset: CGPoint) -> CGPoint {
            CGPoint(
                x: corner.vertex.x + radius * (offset.y * corner.outgoing.dx - offset.x * corner.incoming.dx),
                y: corner.vertex.y + radius * (offset.y * corner.outgoing.dy - offset.x * corner.incoming.dy)
            )
        }
        let edgeStart = point(CGPoint(x: ContinuousCorner.reach, y: 0))
        if path.isEmpty {
            path.move(to: edgeStart)
        } else {
            path.addLine(to: edgeStart)
        }
        for (control1, control2, end) in ContinuousCorner.segments {
            path.addCurve(to: point(end), control1: point(control1), control2: point(control2))
        }
    }
    path.closeSubpath()
    return path
}

private func capsule(_ rect: CGRect) -> CGPath {
    let radius = min(rect.width, rect.height) / 2
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// The live dot sits concentric with the island's trailing end cap, where the
/// hardware notch's camera indicator would be.
private func liveDotRect(on island: CGRect, diameter: CGFloat) -> CGRect {
    CGRect(
        x: island.maxX - island.height / 2 - diameter / 2,
        y: island.midY - diameter / 2,
        width: diameter,
        height: diameter
    )
}

// MARK: - Drawing

/// A shape lifted off what lies behind it: a drop shadow, a top-to-bottom face
/// gradient, and a lit inner rim.
private struct RaisedSurface {
    let face: CGGradient
    let rim: CGGradient
    let shadow: CGColor
    /// Downward shadow offset and blur, as fractions of the canvas side.
    let shadowOffset: CGFloat
    let shadowBlur: CGFloat

    static let body = RaisedSurface(
        face: Palette.bodyFace,
        rim: Palette.bodyRim,
        shadow: Palette.bodyShadow,
        shadowOffset: Proportion.bodyShadowOffset,
        shadowBlur: Proportion.bodyShadowBlur
    )
    static let island = RaisedSurface(
        face: Palette.islandFace,
        rim: Palette.islandRim,
        shadow: Palette.islandShadow,
        shadowOffset: Proportion.islandShadowOffset,
        shadowBlur: Proportion.islandShadowBlur
    )
}

/// The app icon: the island with its live dot on a light face, the one thing the
/// product does, drawn so it survives being scaled to 16pt.
private struct AppIconArtwork {
    let context: CGContext
    let side: CGFloat

    func draw() {
        let inset = side * Proportion.bodyInset
        let body = continuousRoundedRect(
            CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset, dy: inset),
            radius: side * Proportion.bodyCornerRadius
        )
        drawRaised(body, as: .body)

        let islandWidth = side * Proportion.islandWidth
        let islandHeight = side * Proportion.islandHeight
        let island = CGRect(
            x: (side - islandWidth) / 2,
            y: (side - islandHeight) / 2,
            width: islandWidth,
            height: islandHeight
        )
        drawRaised(capsule(island), as: .island)
        drawLiveDot(on: island)
    }

    /// Filled opaque first to cast the drop shadow, then painted with the face
    /// gradient so the shadow never tints the face.
    private func drawRaised(_ path: CGPath, as surface: RaisedSurface) {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -side * surface.shadowOffset),
            blur: side * surface.shadowBlur,
            color: surface.shadow
        )
        context.addPath(path)
        context.setFillColor(CGColor.black)
        context.fillPath()
        context.restoreGState()

        fill(path, with: surface.face)
        strokeInnerRim(of: path, with: surface.rim)
    }

    private func drawLiveDot(on island: CGRect) {
        context.saveGState()
        context.setShadow(offset: .zero, blur: side * Proportion.liveGlowBlur, color: Palette.liveGlow)
        context.setFillColor(Palette.liveDot)
        context.fillEllipse(in: liveDotRect(on: island, diameter: side * Proportion.liveDotDiameter))
        context.restoreGState()
    }

    private func fill(_ path: CGPath, with gradient: CGGradient) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        drawTopToBottom(gradient, over: path.boundingBoxOfPath)
        context.restoreGState()
    }

    /// A hairline just inside the shape's edge, lit at the top and falling off
    /// toward the bottom. It separates the light face from a light Dock and
    /// gives the black island a glassy edge.
    private func strokeInnerRim(of path: CGPath, with gradient: CGGradient) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.addPath(path)
        // The outer half of the stroke falls outside the clip above.
        context.setLineWidth(side * Proportion.rimWidth * 2)
        context.replacePathWithStrokedPath()
        context.clip()
        drawTopToBottom(gradient, over: path.boundingBoxOfPath)
        context.restoreGState()
    }

    private func drawTopToBottom(_ gradient: CGGradient, over rect: CGRect) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
}

/// The status item glyph: the app icon's island with the live dot knocked out,
/// drawn as a pure alpha mask so AppKit can treat it as a template image and tint
/// it for the light, dark, and reduced-contrast menu bars instead of the app
/// shipping a bitmap per appearance.
private func drawMenuBarIcon(in context: CGContext, side: CGFloat) {
    let scale = side / MenuBarProportion.box
    let island = MenuBarProportion.island.applying(CGAffineTransform(scaleX: scale, y: scale))

    let glyph = CGMutablePath()
    glyph.addPath(capsule(island))
    glyph.addEllipse(in: liveDotRect(on: island, diameter: MenuBarProportion.liveDotDiameter * scale))
    context.addPath(glyph)
    context.setFillColor(Palette.menuBarInk)
    context.fillPath(using: .evenOdd)
}

// MARK: - Emission

/// Draws into an sRGB bitmap rather than a device-RGB one so the committed PNGs
/// carry Apple's documented colour values regardless of the display profile of
/// the Mac that generated them.
private func writePNG(pixels: Int, at url: URL, draw: (CGContext, CGFloat) -> Void) throws {
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw IconError.allocationFailed(pixels)
    }
    context.interpolationQuality = .high
    draw(context, CGFloat(pixels))

    guard
        let image = context.makeImage(),
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else {
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
let catalog = repositoryRoot.appending(path: "KerNotch/Assets.xcassets")
let appIconSet = catalog.appending(path: "AppIcon.appiconset")
let menuBarSet = catalog.appending(path: "MenuBarIcon.imageset")

do {
    try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: menuBarSet, withIntermediateDirectories: true)

    for pixels in appIconPixelSizes {
        let url = appIconSet.appending(path: "AppIcon-\(pixels).png")
        try writePNG(pixels: pixels, at: url) { AppIconArtwork(context: $0, side: $1).draw() }
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
