import Foundation

/// The synthetic CPU loads `--cpu-drill*` launch arguments asked for. Pure
/// data: parsing never starts threads and never touches AppKit, so the same
/// grammar is testable in `NotchFlowCore` and usable only where a DEBUG build
/// chooses to execute it.
public struct CPUDrillOptions: Equatable, Sendable {
    /// The upper bound every drill duration is clamped to, so a typo cannot
    /// pin a core for an afternoon. The Phase 2 verification drills never need
    /// more than 120 s.
    public static let maximumDrillSeconds = 180

    public enum Drill: Equatable, Sendable {
        /// A duty-cycled busy loop on a background thread, holding roughly
        /// `percent` of one core for `seconds`.
        case background(percent: Int, seconds: Int)
        /// A busy loop on the main thread that starts after a 10 s delay.
        case mainThread(seconds: Int)
    }

    /// `nil` when no `--cpu-drill=` flag was given at all.
    public let drill: Drill?
    /// What `--cpu-drill-fast-clock` multiplies every watchdog duration by, so
    /// the long-horizon drills (the 15 min degrade-failure timeout, the 1 h
    /// restart-loop window) fit inside one verification session.
    public static let fastClockTimeScale = 0.1

    /// `--cpu-drill-fast-clock`: scale every watchdog duration by 1/10.
    public let fastClock: Bool

    public init(drill: Drill? = nil, fastClock: Bool = false) {
        self.drill = drill
        self.fastClock = fastClock
    }
}

/// Reads NotchFlow's launch arguments. Only the `--cpu-drill*` grammar lives
/// here; flags the app handles inline (`--ui-testing`,
/// `--print-music-backend`) stay where they are used.
public enum LaunchArguments {
    private static let drillFlag = "--cpu-drill"
    private static let fastClockFlag = "--cpu-drill-fast-clock"
    private static let validPercentRange = 1...100

    /// Parses `--cpu-drill=background:<percent>:<seconds>`,
    /// `--cpu-drill=main:<seconds>` and `--cpu-drill-fast-clock`.
    ///
    /// Unknown flags are ignored. `seconds` is clamped to
    /// `0 ... CPUDrillOptions.maximumDrillSeconds`; `percent` must be
    /// `1...100`. Any malformed `--cpu-drill` value returns `nil` — a typo in
    /// an explicit drill request should surface as "no options", not trap and
    /// not a silently different drill. When several drills are given, the last
    /// well-formed one wins.
    public static func parseCPUDrill(_ arguments: [String]) -> CPUDrillOptions? {
        var drill: CPUDrillOptions.Drill?
        var fastClock = false

        for argument in arguments {
            if argument == fastClockFlag {
                fastClock = true
                continue
            }
            if argument == drillFlag {
                return nil
            }
            guard argument.hasPrefix(drillFlag + "=") else { continue }
            guard let parsed = parseDrill(
                String(argument.dropFirst(drillFlag.count + 1))
            )
            else { return nil }
            drill = parsed
        }

        return CPUDrillOptions(drill: drill, fastClock: fastClock)
    }

    private static func parseDrill(_ value: String) -> CPUDrillOptions.Drill? {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        switch components.first {
        case "background":
            guard components.count == 3,
                let percent = Int(components[1]),
                let seconds = Int(components[2]),
                validPercentRange.contains(percent)
            else { return nil }
            return .background(percent: percent, seconds: clamped(seconds))
        case "main":
            guard components.count == 2, let seconds = Int(components[1])
            else { return nil }
            return .mainThread(seconds: clamped(seconds))
        default:
            return nil
        }
    }

    /// The scale `CPUWatchdog.Configuration` is built with on this launch.
    ///
    /// The plan puts the scaling in `Configuration`'s construction and nowhere
    /// else, so this is the one place that turns the flag into a number; a
    /// malformed `--cpu-drill` value leaves the watchdog at real time rather
    /// than guessing which drill was meant.
    public static func watchdogTimeScale(_ arguments: [String]) -> Double {
        parseCPUDrill(arguments)?.fastClock == true
            ? CPUDrillOptions.fastClockTimeScale
            : 1
    }

    private static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, 0), CPUDrillOptions.maximumDrillSeconds)
    }
}
