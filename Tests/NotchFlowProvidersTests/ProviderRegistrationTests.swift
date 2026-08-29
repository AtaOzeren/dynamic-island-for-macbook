import Foundation
import Testing
@testable import NotchFlowCore
@testable import NotchFlowProviders

/// The seam between the providers' optional emissions and the registry's
/// explicit ends. Every provider expresses teardown as `nil`, and every
/// assertion here is about that `nil` arriving at the registry as an end
/// carrying the identity the manager needs to remove the right activity.
@Suite("ProviderRegistration")
@MainActor
struct ProviderRegistrationTests {
    @Test("forwards an emitted activity as an active emission")
    func forwardsActivity() {
        let source = FakePowerSourceObserver()
        let registration = ActivityProviderRegistration.charging(ChargingProvider(source: source))
        var emissions: [ActivityEmission] = []

        registration.startObserving { emissions.append($0) }
        source.emit(.charging)

        #expect(emissions.count == 1)
        #expect(emissions.first?.isEnded == false)
        #expect(emissions.first?.identity == ActivityIdentity("notchflow.charging"))
    }

    /// The translation this type exists for: the provider says "nothing", and
    /// the registry hears "end the thing you had".
    @Test("turns a nil emission into an end carrying the last identity")
    func mapsNilToEnd() {
        let source = FakePowerSourceObserver()
        let registration = ActivityProviderRegistration.charging(ChargingProvider(source: source))
        var emissions: [ActivityEmission] = []

        registration.startObserving { emissions.append($0) }
        source.emit(.charging)
        emissions.removeAll()
        source.emit(.onBattery)

        #expect(emissions.count == 1)
        #expect(emissions.first?.isEnded == true)
        #expect(emissions.first?.identity == ActivityIdentity("notchflow.charging"))
    }

    /// You can only end what you started. A provider that opens by reporting
    /// absence — a machine launched on battery, nothing playing — must not
    /// manufacture an end for an activity the manager never registered.
    @Test("emits nothing for an absence that was never present")
    func ignoresLeadingAbsence() {
        let source = FakePowerSourceObserver()
        let registration = ActivityProviderRegistration.charging(ChargingProvider(source: source))
        var emissions: [ActivityEmission] = []

        registration.startObserving { emissions.append($0) }
        source.emit(.onBattery)

        #expect(emissions.isEmpty)
    }

    @Test("emits nothing after observation stops")
    func silentAfterStop() {
        let source = FakePowerSourceObserver()
        let registration = ActivityProviderRegistration.charging(ChargingProvider(source: source))
        var emissions: [ActivityEmission] = []

        registration.startObserving { emissions.append($0) }
        registration.stopObserving()
        source.emit(.charging)

        #expect(emissions.isEmpty)
        #expect(source.isObserving == false)
    }

    /// The identity is remembered per observation, not for the object's life:
    /// a restarted registration that opens with an absence is in the same
    /// position as a fresh one.
    @Test("forgets the live identity across a restart")
    func forgetsIdentityAcrossRestart() {
        let source = FakePowerSourceObserver()
        let registration = ActivityProviderRegistration.charging(ChargingProvider(source: source))
        var emissions: [ActivityEmission] = []

        registration.startObserving { _ in }
        source.emit(.charging)
        registration.stopObserving()

        registration.startObserving { emissions.append($0) }
        source.emit(.onBattery)

        #expect(emissions.isEmpty)
    }

    @Test("registers music under the music identifier")
    func musicIdentifier() {
        let provider = FakeMusicProvider()
        let registration = ActivityProviderRegistration.music(provider)
        var emissions: [ActivityEmission] = []

        registration.startObserving { emissions.append($0) }
        provider.emit(NowPlaying(
            title: "Nannou",
            artist: "Aphex Twin",
            playbackState: .playing,
            sourceApplicationName: "Spotify"
        ))

        #expect(registration.identifier == .music)
        #expect(emissions.first?.identity == MusicActivity.identity)
    }

    @Test("registers the timer under the timer identifier")
    func timerIdentifier() {
        let provider = TimerProvider(scheduler: FakeTickScheduler(), now: { Date(timeIntervalSince1970: 0) })
        let registration = ActivityProviderRegistration.timer(provider)
        var emissions: [ActivityEmission] = []

        registration.startObserving { emissions.append($0) }
        provider.handle(.start(.stopwatch))

        #expect(registration.identifier == .timer)
        #expect(emissions.last?.identity == TimerActivity.identity)
    }

    /// The two recording switches are separate settings rows, so a registration
    /// that read the wrong one would silently wire the microphone indicator to
    /// the screen-recording toggle.
    @Test("takes its recording identifier from the provider's source", arguments: [
        (RecordingSource.screen, ActivityProviderIdentifier.screenRecording),
        (RecordingSource.audio, ActivityProviderIdentifier.audioRecording)
    ])
    func recordingIdentifierFollowsSource(
        source: RecordingSource,
        expected: ActivityProviderIdentifier
    ) {
        let provider = RecordingProvider(
            source: source,
            sessions: FakeRecordingObserver(),
            scheduler: FakeTickScheduler()
        )

        #expect(ActivityProviderRegistration.recording(provider).identifier == expected)
    }

    @Test("ends the recording session when the capture stops")
    func recordingEndsOnStop() {
        let sessions = FakeRecordingObserver()
        let provider = RecordingProvider(
            source: .screen,
            sessions: sessions,
            scheduler: FakeTickScheduler(),
            now: { Date(timeIntervalSince1970: 0) }
        )
        let registration = ActivityProviderRegistration.recording(provider)
        var emissions: [ActivityEmission] = []

        registration.startObserving { emissions.append($0) }
        sessions.emit(RecordingSession(startedAt: Date(timeIntervalSince1970: 0)))
        emissions.removeAll()
        sessions.emit(nil)

        #expect(emissions.count == 1)
        #expect(emissions.first?.isEnded == true)
        #expect(emissions.first?.identity == RecordingActivity.identity(for: .screen))
    }
}

private extension ActivityEmission {
    var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }
}

@MainActor
private final class FakePowerSourceObserver: PowerSourceObserving {
    private var observer: PowerSourceStateObserver?

    var isObserving: Bool { observer != nil }

    func startObserving(_ observer: @escaping PowerSourceStateObserver) {
        self.observer = observer
    }

    func stopObserving() {
        observer = nil
    }

    func emit(_ state: PowerSourceState) {
        observer?(state)
    }
}

@MainActor
private final class FakeRecordingObserver: RecordingObserving {
    private var observer: RecordingSessionObserver?

    func startObserving(_ observer: @escaping RecordingSessionObserver) {
        self.observer = observer
    }

    func stopObserving() {
        observer = nil
    }

    func emit(_ session: RecordingSession?) {
        observer?(session)
    }
}

@MainActor
private final class FakeMusicProvider: MusicProvider {
    private var observer: NowPlayingObserver?
    let backendName = "Fake"

    func startObserving(_ observer: @escaping NowPlayingObserver) {
        self.observer = observer
    }

    func stopObserving() {
        observer = nil
    }

    func send(_ command: MusicTransportCommand) {}

    func emit(_ nowPlaying: NowPlaying?) {
        observer?(nowPlaying)
    }
}

@MainActor
private final class FakeTickScheduler: TickScheduling {
    private var tick: (@MainActor () -> Void)?

    var isScheduled: Bool { tick != nil }

    func schedule(_ tick: @escaping @MainActor () -> Void) {
        self.tick = tick
    }

    func cancel() {
        tick = nil
    }
}
