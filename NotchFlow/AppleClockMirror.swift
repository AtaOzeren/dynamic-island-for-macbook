import Foundation
import NotchFlowCore
import NotchFlowProviders

/// Mirrors Apple Clock.app's timer and stopwatch into NotchFlow's own
/// `TimerProvider`, so a countdown the user starts in Clock shows in the island.
///
/// Drives the existing provider through its public command API rather than
/// registering a second timer source: the island already draws exactly one
/// timer activity, and two sources writing it would race.
///
/// Polls, unlike every other provider. Clock.app posts no notification a third
/// party can observe — the empirical findings are recorded in
/// `AppleClockReader` — so the choice is a slow poll or no integration at all.
/// The interval is therefore only paid while Clock is actually counting: the
/// idle case costs one accessibility read per `idleInterval`, and the poll stops
/// outright the moment Accessibility access is refused.
@MainActor
final class AppleClockMirror {
    /// How often to re-read while Clock is counting. One second is the coarsest
    /// interval that still keeps a seconds-resolution countdown honest.
    static let activeInterval: TimeInterval = 1

    /// How often to check whether anything has started. Deliberately far slower
    /// than `activeInterval`: nothing is on screen, so nothing is waiting.
    static let idleInterval: TimeInterval = 5

    private let reader: AppleClockReader
    private let provider: TimerProvider
    private var timer: Timer?
    private var mirrored: AppleClockReading?

    init(reader: AppleClockReader = AppleClockReader(), provider: TimerProvider) {
        self.reader = reader
        self.provider = provider
    }

    var isPermitted: Bool { reader.isPermitted }

    func start() {
        guard reader.isPermitted else { return }

        reader.launchHiddenIfNeeded()
        schedule(after: Self.idleInterval)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func schedule(after interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
    }

    private func poll() {
        let reading = reader.read()
        apply(reading)
        mirrored = reading

        schedule(after: reading?.isRunning == true ? Self.activeInterval : Self.idleInterval)
    }

    /// Only transitions are sent. Re-issuing `.start` every second would reset
    /// the provider's own start timestamp on every poll, so a mirrored timer
    /// would never appear to advance.
    private func apply(_ reading: AppleClockReading?) {
        guard let reading else {
            if mirrored != nil { provider.handle(.stop) }
            return
        }

        guard let mirrored else {
            provider.handle(.start(reading.mode))
            if reading.isRunning == false { provider.handle(.pause) }
            return
        }

        if mirrored.mode != reading.mode {
            provider.handle(.stop)
            provider.handle(.start(reading.mode))
        }

        if mirrored.isRunning != reading.isRunning {
            provider.handle(reading.isRunning ? .resume : .pause)
        }
    }
}

extension AppleClockReading {
    /// Clock's stopwatch counts up and its timer counts down, which is exactly
    /// the distinction `TimerMode` already draws.
    var mode: TimerMode {
        switch kind {
        case .timer: .countdown(duration: elapsedOrRemaining)
        case .stopwatch: .stopwatch
        }
    }
}
