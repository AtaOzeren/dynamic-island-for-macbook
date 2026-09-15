import CoreGraphics
import Foundation
import SwiftUI

/// Reads SVG path data into a `Path`, for brand marks that ship as the owner's
/// own SVG file.
///
/// Drawing the mark from its source file, rather than from a re-traced copy or
/// a raster, is what keeps it unmodified — brand guidelines forbid editing the
/// mark — and sharp at every island size. The supported commands are the ones
/// vector exports produce: move, line, horizontal and vertical line, cubic and
/// smooth cubic curves, and close, each in absolute and relative form.
enum SVGPathData {
    /// `nil` for data using a command outside the supported set, or with a
    /// command missing its numbers — a mark drawn half-parsed would be a
    /// modified mark.
    static func path(from data: String) -> Path? {
        let numberPattern = /[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/
        var parser = Parser()
        var index = data.startIndex

        while index < data.endIndex {
            let character = data[index]
            if character.isLetter {
                guard parser.begin(command: character) else { return nil }
                index = data.index(after: index)
            } else if let match = data[index...].prefixMatch(of: numberPattern) {
                guard let value = Double(match.output) else { return nil }
                guard parser.accept(CGFloat(value)) else { return nil }
                index = match.range.upperBound
            } else {
                index = data.index(after: index)
            }
        }
        return parser.finish()
    }

    private struct Parser {
        private static let argumentCounts: [Character: Int] = [
            "M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Z": 0,
        ]

        private var path = Path()
        private var command: Character?
        private var isRelative = false
        private var arguments: [CGFloat] = []
        private var current = CGPoint.zero
        private var subpathStart = CGPoint.zero
        private var lastControl: CGPoint?

        mutating func begin(command letter: Character) -> Bool {
            guard arguments.isEmpty else { return false }
            let upper = Character(letter.uppercased())
            guard let count = Self.argumentCounts[upper] else { return false }

            command = upper
            isRelative = letter.isLowercase
            if count == 0 {
                closeSubpath()
            }
            return true
        }

        mutating func accept(_ value: CGFloat) -> Bool {
            guard let command, let count = Self.argumentCounts[command], count > 0 else { return false }

            arguments.append(value)
            guard arguments.count == count else { return true }

            apply(command, arguments)
            arguments.removeAll(keepingCapacity: true)
            // Numbers after a move's first pair are implicit line-tos.
            if command == "M" {
                self.command = "L"
            }
            return true
        }

        func finish() -> Path? {
            arguments.isEmpty ? path : nil
        }

        private mutating func apply(_ command: Character, _ values: [CGFloat]) {
            switch command {
            case "M":
                let point = resolve(values[0], values[1])
                path.move(to: point)
                current = point
                subpathStart = point
                lastControl = nil
            case "L":
                lineTo(resolve(values[0], values[1]))
            case "H":
                lineTo(CGPoint(x: isRelative ? current.x + values[0] : values[0], y: current.y))
            case "V":
                lineTo(CGPoint(x: current.x, y: isRelative ? current.y + values[0] : values[0]))
            case "C":
                curve(
                    control1: resolve(values[0], values[1]),
                    control2: resolve(values[2], values[3]),
                    to: resolve(values[4], values[5])
                )
            case "S":
                let reflected = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                curve(control1: reflected, control2: resolve(values[0], values[1]), to: resolve(values[2], values[3]))
            default:
                break
            }
        }

        private func resolve(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            isRelative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        private mutating func lineTo(_ point: CGPoint) {
            path.addLine(to: point)
            current = point
            lastControl = nil
        }

        private mutating func curve(control1: CGPoint, control2: CGPoint, to point: CGPoint) {
            path.addCurve(to: point, control1: control1, control2: control2)
            current = point
            lastControl = control2
        }

        private mutating func closeSubpath() {
            path.closeSubpath()
            current = subpathStart
            lastControl = nil
        }
    }
}
