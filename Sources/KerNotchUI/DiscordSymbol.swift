import CoreGraphics
import Foundation
import SwiftUI

/// Discord's symbol, drawn from the official `DiscordSymbol.svg` in this
/// module's resources, per the Discord brand guidelines: unmodified, in white or
/// on Discord's blurple.
enum DiscordSymbolArtwork {
    static let blurple = Color(red: 88 / 255, green: 101 / 255, blue: 242 / 255)

    /// Read and parsed once. `nil` only if the resource is missing or
    /// unreadable, in which case the views fall back to a plain glyph rather
    /// than a partial mark.
    static let artwork: (path: Path, viewBox: CGRect)? = {
        guard
            let url = Bundle.module.url(forResource: "DiscordSymbol", withExtension: "svg"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return parse(source)
    }()

    static func parse(_ source: String) -> (path: Path, viewBox: CGRect)? {
        guard
            let pathData = source.firstMatch(of: /\sd="([^"]+)"/)?.output.1,
            let viewBox = source.firstMatch(of: /viewBox="([^"]+)"/)?.output.1,
            let path = SVGPathData.path(from: String(pathData))
        else { return nil }

        let numbers = viewBox.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }

        return (path, CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
    }
}

/// The symbol, scaled to fit its frame without distortion and centred.
struct DiscordSymbolShape: Shape {
    func path(in rect: CGRect) -> Path {
        guard let artwork = DiscordSymbolArtwork.artwork else { return Path() }

        let viewBox = artwork.viewBox
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let offsetX = rect.midX - viewBox.midX * scale
        let offsetY = rect.midY - viewBox.midY * scale
        let transform = CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
        return artwork.path.applying(transform)
    }
}

/// The white symbol on a blurple disc — the form the mark takes as a badge on
/// another glyph.
struct DiscordBadge: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(DiscordSymbolArtwork.blurple)
            .overlay {
                DiscordSymbolShape()
                    .fill(.white)
                    .padding(diameter * 0.22)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}
