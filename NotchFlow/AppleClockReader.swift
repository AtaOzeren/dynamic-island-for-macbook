import AppKit
import ApplicationServices
import Foundation
import NotchFlowCore

/// What Apple's Clock.app is currently counting, as read through the
/// Accessibility API.
///
/// Clock.app ships no scripting dictionary, its `mobiletimerd` XPC services are
/// entitlement-gated, and it writes no live state to disk — the accessibility
/// tree is the only channel a third-party app can read. That makes this a
/// best-effort integration: `nil` means "nothing readable", never "nothing
/// running".
struct AppleClockReading: Equatable {
    enum Kind: Equatable {
        case timer
        case stopwatch
    }

    let kind: Kind
    let elapsedOrRemaining: Duration
    let isRunning: Bool
}

/// Reads Clock.app's timer or stopwatch through the accessibility tree.
///
/// Never launches Clock.app visibly: when Clock is not running it is started
/// with `open -gj`, which brings up the process hidden and without stealing
/// focus, because closing Clock's window terminates the app while
/// `mobiletimerd` keeps counting — the state would otherwise be unreadable for
/// exactly the case this integration exists to cover.
@MainActor
final class AppleClockReader {
    private static let bundleIdentifier = "com.apple.clock"
    private static let maximumTreeDepth = 12

    /// `true` once the user has granted Accessibility access. Never prompts:
    /// the reader degrades to reading nothing, the same way every other
    /// provider degrades when its permission is refused.
    var isPermitted: Bool { AXIsProcessTrusted() }

    func read() -> AppleClockReading? {
        guard isPermitted, let application = runningClock() else { return nil }

        let root = AXUIElementCreateApplication(application.processIdentifier)
        let descriptions = descriptions(of: root)
        guard descriptions.isEmpty == false else { return nil }

        return timerReading(from: descriptions) ?? stopwatchReading(from: descriptions)
    }

    /// Starts Clock.app hidden if it is not already running, so a later `read()`
    /// has a tree to walk. Separate from `read()` because launching an app is a
    /// side effect a pure read must not have.
    func launchHiddenIfNeeded() {
        guard isPermitted, runningClock() == nil else { return }

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-gj", "-a", "Clock"]
        try? open.run()
    }

    private func runningClock() -> NSRunningApplication? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.bundleIdentifier)
            .first
    }

    /// A timer is showing when a digital value is on screen. Clock labels the
    /// transport "Pause" while counting and "Resume" once halted, so either
    /// label means a timer is up; the running/paused split rides on which one
    /// is drawn. This matters because a paused timer is exactly the state a
    /// user leaves on screen for minutes — the reading must not vanish.
    private func timerReading(from descriptions: [String]) -> AppleClockReading? {
        let isRunning = descriptions.contains("Pause")
        guard isRunning || descriptions.contains("Resume") else { return nil }
        guard let remaining = descriptions.lazy.compactMap(AppleClockParser.digitalDuration).first
        else { return nil }

        return AppleClockReading(kind: .timer, elapsedOrRemaining: remaining, isRunning: isRunning)
    }

    /// The stopwatch always draws its value, so the transport label is what
    /// says whether it is moving: "Stop" while running, "Start" once halted.
    ///
    /// Lap rows are skipped rather than merely out-ranked: each one repeats its
    /// split and total in a single string, so parsing it sums the same time
    /// twice. Relying on the running total appearing first in the tree would
    /// make the reading depend on Clock's own child ordering.
    private func stopwatchReading(from descriptions: [String]) -> AppleClockReading? {
        guard descriptions.contains("Lap") else { return nil }

        let elapsed =
            descriptions
            .filter { $0.hasPrefix("Lap ") == false }
            .lazy
            .compactMap(AppleClockParser.spelledDuration)
            .first
        guard let elapsed, elapsed > .zero else { return nil }

        return AppleClockReading(
            kind: .stopwatch,
            elapsedOrRemaining: elapsed,
            isRunning: descriptions.contains("Stop")
        )
    }

    private func descriptions(of root: AXUIElement) -> [String] {
        var found: [String] = []

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= Self.maximumTreeDepth else { return }

            let role = attribute(element, kAXRoleAttribute) as? String
            // The menu bar is every app's largest subtree and holds nothing the
            // timer needs, so skipping it is most of this walk's cost.
            guard role?.hasPrefix("AXMenu") != true else { return }

            if let description = attribute(element, kAXDescriptionAttribute) as? String,
                description.isEmpty == false
            {
                found.append(description)
            }

            for child in children(of: element) {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return found
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}
