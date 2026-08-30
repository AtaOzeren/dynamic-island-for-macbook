#!/usr/bin/env swift

import AppKit
import Foundation

struct ScreenshotSpecification {
    let filename: String
    let eyebrow: String
    let headline: String
    let detail: String
    let symbol: String
    let islandTitle: String
    let islandDetail: String
    let accent: NSColor
    let progress: CGFloat?
}

let specifications = [
    ScreenshotSpecification(
        filename: "01-music.png",
        eyebrow: "NOW PLAYING",
        headline: "Your music, right where you look.",
        detail: "See the track and control playback without leaving your work.",
        symbol: "music.note",
        islandTitle: "Midnight Drive",
        islandDetail: "The Satellites  •  Playing",
        accent: NSColor(red: 0.48, green: 0.42, blue: 1, alpha: 1),
        progress: 0.64
    ),
    ScreenshotSpecification(
        filename: "02-timer.png",
        eyebrow: "FOCUS TIMER",
        headline: "Time stays in sight. Distractions don't.",
        detail: "Run a countdown or stopwatch from a calm, glanceable surface.",
        symbol: "timer",
        islandTitle: "18:42",
        islandDetail: "Focus session",
        accent: NSColor(red: 1, green: 0.57, blue: 0.27, alpha: 1),
        progress: 0.38
    ),
    ScreenshotSpecification(
        filename: "03-ai-agent.png",
        eyebrow: "AI AGENTS",
        headline: "Know when your coding agent needs you.",
        detail: "Follow Claude Code, Codex CLI, and OpenCode without watching a terminal.",
        symbol: "sparkles",
        islandTitle: "Claude Code  •  Working",
        islandDetail: "Running the test suite",
        accent: NSColor(red: 0.35, green: 0.84, blue: 0.75, alpha: 1),
        progress: 0.72
    ),
    ScreenshotSpecification(
        filename: "04-recording.png",
        eyebrow: "RECORDING AWARENESS",
        headline: "A clear signal when recording is active.",
        detail: "Keep screen and microphone recording status visible at a glance.",
        symbol: "record.circle.fill",
        islandTitle: "Screen recording",
        islandDetail: "00:12:48 elapsed",
        accent: NSColor(red: 1, green: 0.31, blue: 0.32, alpha: 1),
        progress: nil
    ),
    ScreenshotSpecification(
        filename: "05-settings.png",
        eyebrow: "MADE FOR YOUR MAC",
        headline: "Choose what appears. Keep everything else quiet.",
        detail: "Control activities, appearance, display placement, and AI integrations.",
        symbol: "gearshape.fill",
        islandTitle: "NotchFlow Settings",
        islandDetail: "General  •  Activities  •  AI Integrations  •  About",
        accent: NSColor(red: 0.38, green: 0.68, blue: 1, alpha: 1),
        progress: nil
    ),
]

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/store/screenshots/en-US")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byWordWrapping
    text.draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
    )
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawScreenshot(_ specification: ScreenshotSpecification) throws {
    let size = NSSize(width: 2560, height: 1600)
    let image = NSImage(size: size)
    image.lockFocus()

    let background = NSGradient(colors: [
        NSColor(red: 0.055, green: 0.063, blue: 0.09, alpha: 1),
        NSColor(red: 0.09, green: 0.075, blue: 0.16, alpha: 1),
    ])!
    background.draw(in: NSRect(origin: .zero, size: size), angle: -35)

    specification.accent.withAlphaComponent(0.16).setFill()
    NSBezierPath(ovalIn: NSRect(x: 1510, y: 260, width: 1080, height: 1080)).fill()

    drawText(specification.eyebrow, in: NSRect(x: 180, y: 1280, width: 850, height: 60), font: .systemFont(ofSize: 34, weight: .semibold), color: specification.accent)
    drawText(specification.headline, in: NSRect(x: 180, y: 830, width: 1050, height: 420), font: .systemFont(ofSize: 100, weight: .bold), color: .white)
    drawText(specification.detail, in: NSRect(x: 185, y: 640, width: 940, height: 160), font: .systemFont(ofSize: 40, weight: .regular), color: NSColor.white.withAlphaComponent(0.68))

    let desktop = NSRect(x: 1320, y: 210, width: 1080, height: 1180)
    drawRoundedRect(desktop, radius: 42, color: NSColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1))
    drawRoundedRect(NSRect(x: desktop.minX, y: desktop.maxY - 54, width: desktop.width, height: 54), radius: 38, color: NSColor.white.withAlphaComponent(0.08))
    drawRoundedRect(NSRect(x: 1690, y: 1310, width: 340, height: 80), radius: 28, color: .black)

    let panel = NSRect(x: 1475, y: 870, width: 770, height: 330)
    drawRoundedRect(panel, radius: 54, color: NSColor.black.withAlphaComponent(0.92))
    drawRoundedRect(NSRect(x: panel.minX + 38, y: panel.minY + 158, width: 112, height: 112), radius: 30, color: specification.accent.withAlphaComponent(0.22))

    if let symbol = NSImage(systemSymbolName: specification.symbol, accessibilityDescription: nil) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 54, weight: .medium)
        specification.accent.set()
        symbol.withSymbolConfiguration(configuration)?.draw(in: NSRect(x: panel.minX + 65, y: panel.minY + 185, width: 58, height: 58))
    }

    drawText(specification.islandTitle, in: NSRect(x: panel.minX + 180, y: panel.minY + 205, width: 520, height: 60), font: .systemFont(ofSize: 34, weight: .semibold), color: .white)
    drawText(specification.islandDetail, in: NSRect(x: panel.minX + 180, y: panel.minY + 152, width: 520, height: 50), font: .systemFont(ofSize: 25, weight: .regular), color: NSColor.white.withAlphaComponent(0.62))

    if let progress = specification.progress {
        let track = NSRect(x: panel.minX + 42, y: panel.minY + 76, width: panel.width - 84, height: 12)
        drawRoundedRect(track, radius: 6, color: NSColor.white.withAlphaComponent(0.12))
        drawRoundedRect(NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: track.height), radius: 6, color: specification.accent)
    } else {
        drawText("Live • On this Mac", in: NSRect(x: panel.minX + 42, y: panel.minY + 62, width: 400, height: 40), font: .systemFont(ofSize: 24, weight: .medium), color: specification.accent)
    }

    drawText("NotchFlow", in: NSRect(x: 180, y: 120, width: 400, height: 70), font: .systemFont(ofSize: 38, weight: .semibold), color: NSColor.white.withAlphaComponent(0.85))

    image.unlockFocus()
    guard
        let tiff = image.tiffRepresentation,
        let sourceBitmap = NSBitmapImageRep(data: tiff),
        let sourceImage = sourceBitmap.cgImage,
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.interpolationQuality = .high
    context.draw(sourceImage, in: CGRect(origin: .zero, size: size))
    guard let outputImage = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }
    let bitmap = NSBitmapImageRep(cgImage: outputImage)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: outputDirectory.appendingPathComponent(specification.filename))
}

for specification in specifications {
    try drawScreenshot(specification)
    print("Generated \(specification.filename)")
}
