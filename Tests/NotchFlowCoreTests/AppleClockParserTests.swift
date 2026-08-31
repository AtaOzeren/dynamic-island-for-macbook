import Foundation
import Testing

@testable import NotchFlowCore

/// Every input below is a string Clock.app actually emitted on this machine,
/// captured while driving the Timers and Stopwatch tabs through the
/// Accessibility API — including the negatives, which are the tree's other
/// labels ("15 min", "Radial (Default)") rather than invented inputs.
@Suite("AppleClockParser")
struct AppleClockParserTests {
    @Test("digital values parse as durations")
    func digitalValues() {
        #expect(AppleClockParser.digitalDuration(from: "14:58") == .seconds(898))
        #expect(AppleClockParser.digitalDuration(from: "15:00") == .seconds(900))
        #expect(AppleClockParser.digitalDuration(from: "1:02:03") == .seconds(3723))
        #expect(AppleClockParser.digitalDuration(from: "0:05") == .seconds(5))
    }

    @Test("non-digital labels the Timers tree also contains are rejected")
    func digitalNegatives() {
        #expect(AppleClockParser.digitalDuration(from: "15 min") == nil)
        #expect(AppleClockParser.digitalDuration(from: "Radial (Default)") == nil)
        #expect(AppleClockParser.digitalDuration(from: "Recent") == nil)
        #expect(AppleClockParser.digitalDuration(from: "") == nil)
    }

    @Test("spelled-out stopwatch values parse as durations")
    func spelledValues() {
        #expect(AppleClockParser.spelledDuration(from: "0 seconds") == .seconds(0))
        #expect(AppleClockParser.spelledDuration(from: "2 seconds") == .seconds(2))
        #expect(AppleClockParser.spelledDuration(from: "38 minutes, 31 seconds") == .seconds(2311))
    }

    @Test("non-duration labels the Stopwatch tree also contains are rejected")
    func spelledNegatives() {
        #expect(AppleClockParser.spelledDuration(from: "Lap No.") == nil)
        #expect(AppleClockParser.spelledDuration(from: "Split") == nil)
        #expect(AppleClockParser.spelledDuration(from: "Total") == nil)
        #expect(AppleClockParser.spelledDuration(from: "Start") == nil)
    }

    @Test("hour components parse")
    func spelledHours() {
        #expect(AppleClockParser.spelledDuration(from: "1 hour, 2 minutes, 3 seconds") == .seconds(3723))
    }
}
