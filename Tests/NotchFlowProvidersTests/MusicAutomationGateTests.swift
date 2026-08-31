import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

/// Stands in for the Apple Events consent database, which a test cannot reset.
///
/// It records every call so the sequencing rules of
/// `docs/09-security-privacy-permissions.md` can be asserted as counts: "asks
/// once" and "never asks without explaining" are both statements about how many
/// times `request` ran, and nothing else observes that.
@MainActor
private final class FakeAutomationAuthority: MusicAutomationAuthorizing {
    var statuses: [MusicPlayerTarget: AutomationPermissionStatus] = [:]
    /// What the system decides once the prompt is shown, per target.
    var outcomes: [MusicPlayerTarget: AutomationPermissionStatus] = [:]
    private(set) var requestedTargets: [MusicPlayerTarget] = []

    func status(for target: MusicPlayerTarget) -> AutomationPermissionStatus {
        statuses[target] ?? .notDetermined
    }

    func request(for target: MusicPlayerTarget) -> AutomationPermissionStatus {
        requestedTargets.append(target)
        let outcome = outcomes[target] ?? statuses[target] ?? .notDetermined
        statuses[target] = outcome
        return outcome
    }
}

/// The sequencing half of todo 64. Every rule the permission flow states as
/// prose is asserted here as a count of prompts.
@Suite("MusicAutomationGate")
@MainActor
struct MusicAutomationGateTests {
    private static func make(
        explainerAnswers accepted: Bool = true
    ) -> (MusicAutomationGate, FakeAutomationAuthority, Box<[MusicAutomationAccess]>) {
        let authority = FakeAutomationAuthority()
        let explained = Box<[MusicAutomationAccess]>([])
        let gate = MusicAutomationGate(authority: authority) { access in
            explained.value.append(access)
            return accepted
        }
        return (gate, authority, explained)
    }

    /// A mutable capture the escaping explainer can append to.
    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    // MARK: - Nothing at launch

    /// The acceptance criterion, stated directly: reading the state the settings
    /// pane renders must not raise a prompt.
    @Test("reading access never asks the system")
    func readingAccessNeverPrompts() {
        let (gate, authority, explained) = Self.make()

        _ = gate.access()

        #expect(authority.requestedTargets.isEmpty)
        #expect(explained.value.isEmpty)
    }

    @Test("access is reported for both targets")
    func accessCoversBothTargets() {
        let (gate, authority, _) = Self.make()
        authority.statuses[.spotify] = .granted
        authority.statuses[.appleMusic] = .denied

        #expect(gate.access().map(\.target) == MusicPlayerTarget.allCases)
        #expect(gate.access(for: .spotify).status == .granted)
        #expect(gate.access(for: .appleMusic).status == .denied)
    }

    // MARK: - Explain before asking

    @Test("an undecided target is explained before the system is asked")
    func explanationPrecedesThePrompt() {
        let (gate, authority, explained) = Self.make(explainerAnswers: true)
        authority.outcomes[.spotify] = .granted

        #expect(gate.canQuery(.spotify))
        #expect(explained.value.map(\.target) == [.spotify])
        #expect(authority.requestedTargets == [.spotify])
    }

    /// Declining NotchFlow's own explanation has to stop the flow before the
    /// system prompt — otherwise step 2 would be a notice, not a gate.
    @Test("declining the explanation means the system is never asked")
    func decliningTheExplanationSkipsThePrompt() {
        let (gate, authority, explained) = Self.make(explainerAnswers: false)

        #expect(gate.canQuery(.spotify) == false)
        #expect(explained.value.map(\.target) == [.spotify])
        #expect(authority.requestedTargets.isEmpty)
    }

    // MARK: - Ask once

    /// Music apps post their wake-up notification on every track change, so
    /// without this the explanation would reappear on a beat.
    @Test("a target is explained at most once, however often it is polled")
    func explanationIsOfferedOnlyOnce() {
        let (gate, authority, explained) = Self.make(explainerAnswers: false)

        for _ in 0..<5 {
            _ = gate.canQuery(.spotify)
        }

        #expect(explained.value.count == 1)
        #expect(authority.requestedTargets.isEmpty)
    }

    @Test("a granted target is queried without ever being explained again")
    func grantedTargetsSkipTheExplainer() {
        let (gate, authority, explained) = Self.make()
        authority.statuses[.spotify] = .granted

        #expect(gate.canQuery(.spotify))
        #expect(gate.canQuery(.spotify))
        #expect(explained.value.isEmpty)
        #expect(authority.requestedTargets.isEmpty)
    }

    /// Re-prompting a denied target is the nagging the flow forbids, and the
    /// system would swallow it anyway.
    @Test("a denied target is never explained and never re-prompted")
    func deniedTargetsAreNeverAskedAgain() {
        let (gate, authority, explained) = Self.make()
        authority.statuses[.appleMusic] = .denied

        #expect(gate.canQuery(.appleMusic) == false)
        #expect(gate.canQuery(.appleMusic) == false)
        #expect(explained.value.isEmpty)
        #expect(authority.requestedTargets.isEmpty)
    }

    // MARK: - Graceful degradation

    /// "A denied Apple Events prompt for one music app disables control of that
    /// app only" — the acceptance criterion, as a test.
    @Test("denying one player leaves the other one working")
    func denialIsScopedToOneTarget() {
        let (gate, authority, _) = Self.make()
        authority.statuses[.spotify] = .granted
        authority.statuses[.appleMusic] = .denied

        #expect(gate.canQuery(.spotify))
        #expect(gate.canQuery(.appleMusic) == false)
    }

    @Test("a refused system prompt leaves the target unqueryable")
    func refusedPromptDisablesTheTarget() {
        let (gate, authority, _) = Self.make(explainerAnswers: true)
        authority.outcomes[.spotify] = .denied

        #expect(gate.canQuery(.spotify) == false)
        #expect(gate.access(for: .spotify).status == .denied)
    }

    // MARK: - The settings button

    /// The pane already shows the explanation in place, so its button goes
    /// straight to the system — and a prompt the user pressed for is not a nag,
    /// which is why it does not consume the ask-once record.
    @Test("the settings button prompts without going through the explainer")
    func settingsRequestSkipsTheExplainer() {
        let (gate, authority, explained) = Self.make()
        authority.outcomes[.appleMusic] = .granted

        let access = gate.requestAccess(for: .appleMusic)

        #expect(access.status == .granted)
        #expect(explained.value.isEmpty)
        #expect(authority.requestedTargets == [.appleMusic])
    }

    /// Once the pane has asked, the observation path must not ask again behind
    /// the user's back on the next track change.
    @Test("a target asked about from settings is not explained later")
    func settingsRequestConsumesTheOneOffer() {
        let (gate, authority, explained) = Self.make(explainerAnswers: true)
        authority.outcomes[.spotify] = .denied

        _ = gate.requestAccess(for: .spotify)
        authority.statuses[.spotify] = .notDetermined

        #expect(gate.canQuery(.spotify) == false)
        #expect(explained.value.isEmpty)
        #expect(authority.requestedTargets == [.spotify])
    }
}
