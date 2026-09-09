import Testing

@testable import KerNotchCore

@Suite("Launch arguments")
struct LaunchArgumentsTests {
    @Test("parses a background drill with percent and seconds")
    func backgroundDrill() throws {
        let options = try #require(
            LaunchArguments.parseCPUDrill(["--cpu-drill=background:30:60"])
        )

        #expect(options.drill == .background(percent: 30, seconds: 60))
        #expect(!options.fastClock)
    }

    @Test("parses the main-thread drill")
    func mainThreadDrill() throws {
        let options = try #require(
            LaunchArguments.parseCPUDrill(["--cpu-drill=main:120"])
        )

        #expect(options.drill == .mainThread(seconds: 120))
        #expect(!options.fastClock)
    }

    @Test("parses --cpu-drill-fast-clock on its own")
    func fastClockAlone() throws {
        let options = try #require(
            LaunchArguments.parseCPUDrill(["--cpu-drill-fast-clock"])
        )

        #expect(options.drill == nil)
        #expect(options.fastClock)
    }

    @Test("combines a drill with --cpu-drill-fast-clock")
    func drillWithFastClock() throws {
        let options = try #require(
            LaunchArguments.parseCPUDrill([
                "--cpu-drill=background:60:120",
                "--cpu-drill-fast-clock",
            ])
        )

        #expect(options.drill == .background(percent: 60, seconds: 120))
        #expect(options.fastClock)
    }

    @Test("clamps huge seconds to 180")
    func clampsHugeSeconds() throws {
        let background = try #require(
            LaunchArguments.parseCPUDrill(["--cpu-drill=background:30:999999"])
        )
        let main = try #require(
            LaunchArguments.parseCPUDrill(["--cpu-drill=main:100000"])
        )

        #expect(background.drill == .background(percent: 30, seconds: 180))
        #expect(main.drill == .mainThread(seconds: 180))
    }

    @Test("clamps negative seconds to zero")
    func clampsNegativeSeconds() throws {
        let options = try #require(
            LaunchArguments.parseCPUDrill(["--cpu-drill=background:30:-5"])
        )

        #expect(options.drill == .background(percent: 30, seconds: 0))
    }

    @Test("zero seconds parse as an immediate no-op drill")
    func zeroSeconds() throws {
        let options = try #require(
            LaunchArguments.parseCPUDrill(["--cpu-drill=main:0"])
        )

        #expect(options.drill == .mainThread(seconds: 0))
    }

    @Test("last well-formed drill wins")
    func lastDrillWins() throws {
        let options = try #require(
            LaunchArguments.parseCPUDrill([
                "--cpu-drill=main:15",
                "--cpu-drill=background:40:30",
            ])
        )

        #expect(options.drill == .background(percent: 40, seconds: 30))
    }

    @Test("ignores unknown flags and other arguments")
    func ignoresUnknownFlags() throws {
        let options = try #require(
            LaunchArguments.parseCPUDrill([
                "--ui-testing",
                "--show-settings-after-restart",
                "--print-music-backend",
                "--cpu-drill=main:10",
            ])
        )

        #expect(options.drill == .mainThread(seconds: 10))
        #expect(!options.fastClock)
    }

    @Test("no drill flags yields no drill")
    func noDrillFlags() throws {
        let options = try #require(
            LaunchArguments.parseCPUDrill(["--ui-testing"])
        )

        #expect(options.drill == nil)
        #expect(!options.fastClock)
    }

    @Test("empty arguments yield no drill")
    func emptyArguments() throws {
        let options = try #require(LaunchArguments.parseCPUDrill([]))

        #expect(options.drill == nil)
        #expect(!options.fastClock)
    }

    @Test("rejects a missing seconds component")
    func missingSeconds() {
        #expect(LaunchArguments.parseCPUDrill(["--cpu-drill=background:30"]) == nil)
        #expect(LaunchArguments.parseCPUDrill(["--cpu-drill=main"]) == nil)
    }

    @Test("rejects non-numeric values")
    func nonNumericValues() {
        #expect(LaunchArguments.parseCPUDrill(["--cpu-drill=main:abc"]) == nil)
        #expect(
            LaunchArguments.parseCPUDrill(["--cpu-drill=background:thirty:60"]) == nil
        )
        #expect(
            LaunchArguments.parseCPUDrill(["--cpu-drill=background:30:sixty"]) == nil
        )
    }

    @Test("rejects an unknown drill kind")
    func unknownKind() {
        #expect(LaunchArguments.parseCPUDrill(["--cpu-drill=stall:60"]) == nil)
    }

    @Test("rejects extra components")
    func extraComponents() {
        #expect(
            LaunchArguments.parseCPUDrill(["--cpu-drill=background:30:60:90"]) == nil
        )
    }

    @Test("rejects an empty drill value")
    func emptyValue() {
        #expect(LaunchArguments.parseCPUDrill(["--cpu-drill="]) == nil)
        #expect(LaunchArguments.parseCPUDrill(["--cpu-drill"]) == nil)
    }

    @Test("rejects percent above 100")
    func percentAbove100() {
        #expect(LaunchArguments.parseCPUDrill(["--cpu-drill=background:101:60"]) == nil)
        #expect(LaunchArguments.parseCPUDrill(["--cpu-drill=background:250:60"]) == nil)
    }

    @Test("rejects zero percent")
    func zeroPercent() {
        #expect(LaunchArguments.parseCPUDrill(["--cpu-drill=background:0:60"]) == nil)
    }

    @Test("rejects negative percent")
    func negativePercent() {
        #expect(LaunchArguments.parseCPUDrill(["--cpu-drill=background:-30:60"]) == nil)
    }

    @Test("a malformed drill rejects the parse even beside a fast-clock flag")
    func malformedBesideFastClock() {
        #expect(
            LaunchArguments.parseCPUDrill(["--cpu-drill-fast-clock", "--cpu-drill=oops"])
            == nil
        )
    }

    /// The flag only earns its keep if it reaches `CPUWatchdog.Configuration`;
    /// parsed-but-unapplied is the state in which every long-horizon drill
    /// silently runs at real time and reports nothing.
    @Test("the fast-clock flag becomes the watchdog's time scale")
    func fastClockBecomesTimeScale() {
        #expect(LaunchArguments.watchdogTimeScale(["--cpu-drill-fast-clock"]) == 0.1)
        #expect(
            LaunchArguments.watchdogTimeScale(
                ["--cpu-drill=background:60:120", "--cpu-drill-fast-clock"]
            ) == 0.1
        )
    }

    @Test("a launch without the flag runs the watchdog at real time")
    func realTimeWithoutFastClock() {
        #expect(LaunchArguments.watchdogTimeScale([]) == 1)
        #expect(LaunchArguments.watchdogTimeScale(["--cpu-drill=main:120"]) == 1)
        #expect(LaunchArguments.watchdogTimeScale(["--cpu-drill=oops"]) == 1)
    }

    @Test("the fast clock shortens every watchdog duration by a factor of ten")
    func fastClockScalesConfiguration() {
        let configuration = CPUWatchdog.Configuration(
            timeScale: LaunchArguments.watchdogTimeScale(["--cpu-drill-fast-clock"])
        )

        #expect(configuration.startupGracePeriod == .seconds(6))
        #expect(configuration.degradeWindow == .seconds(3))
        #expect(configuration.minimumDegradedDwell == .seconds(30))
        #expect(configuration.degradeFailureTimeout == .seconds(90))
        #expect(configuration.restartLoopWindow == .seconds(360))
    }
}
