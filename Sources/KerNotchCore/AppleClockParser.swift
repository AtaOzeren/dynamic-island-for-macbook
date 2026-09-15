import Foundation

/// Parses the strings Clock.app exposes on its accessibility elements.
///
/// Split from the reader so the two formats Clock actually emits can be
/// asserted in CI without Clock.app running: the stopwatch spells its value out
/// ("38 minutes, 31 seconds") while the timer uses a digital clock ("14:58").
public enum AppleClockParser {
    /// Digital `mm:ss` or `hh:mm:ss`, as the Timers tab draws it.
    public static func digitalDuration(from text: String) -> Duration? {
        let parts = text.split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }

        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }

        let seconds =
            numbers.count == 3
            ? numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
            : numbers[0] * 60 + numbers[1]
        return .seconds(seconds)
    }

    /// Spelled-out durations such as "38 minutes, 31 seconds" or "0 seconds",
    /// as the Stopwatch tab draws it.
    public static func spelledDuration(from text: String) -> Duration? {
        let units: [(String, Int)] = [("hour", 3600), ("minute", 60), ("second", 1)]
        var total = 0
        var matched = false

        for component in text.split(separator: ",") {
            let words = component.split(separator: " ")
            guard words.count >= 2, let value = Int(words[0]) else { continue }

            let noun = words[1].lowercased()
            guard let unit = units.first(where: { noun.hasPrefix($0.0) }) else { continue }

            total += value * unit.1
            matched = true
        }

        return matched ? .seconds(total) : nil
    }
}
