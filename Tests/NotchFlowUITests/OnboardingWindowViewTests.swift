import Foundation
import SwiftUI
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// The UI half of todo 61: onboarding must be walkable to the end, skippable
/// from anywhere, and incapable of reporting a hook install the user did not
/// switch on.
@Suite("OnboardingWindowView")
@MainActor
struct OnboardingWindowViewTests {
    /// Stands in for the window that owns the flow value, so a test drives the
    /// same binding a hosted `OnboardingRoot` would hand the view.
    private final class Recorder: @unchecked Sendable {
        var flow = OnboardingFlow()
        var outcomes: [OnboardingOutcome] = []
        var settingsOpenCount = 0

        var binding: Binding<OnboardingFlow> {
            Binding(get: { self.flow }, set: { self.flow = $0 })
        }
    }

    private func makeView(
        detectedAgents: [IPCAgentID] = [],
        recorder: Recorder
    ) -> OnboardingWindowView {
        recorder.flow = OnboardingFlow(detectedAgents: detectedAgents)
        return OnboardingWindowView(
            flow: recorder.binding,
            onOpenSettings: { recorder.settingsOpenCount += 1 },
            onFinish: { recorder.outcomes.append($0) }
        )
    }

    @Test("the primary button reads Continue until the final step, then Done")
    func primaryButtonTitleTracksTheStep() {
        let recorder = Recorder()
        let view = makeView(recorder: recorder)

        #expect(view.currentStep == .welcome)
        #expect(view.primaryButtonTitle == "Continue")
        #expect(view.isSkippable)

        view.advance()
        view.advance()
        #expect(view.currentStep == .agents)
        #expect(view.primaryButtonTitle == "Continue")

        view.advance()
        #expect(view.currentStep == .done)
        #expect(view.primaryButtonTitle == "Done")
        #expect(!view.isSkippable)
    }

    @Test("finishing the last step reports the outcome exactly once")
    func finishReportsOnce() {
        let recorder = Recorder()
        let view = makeView(recorder: recorder)

        for _ in OnboardingStep.allCases {
            view.advance()
        }
        view.advance()

        #expect(recorder.outcomes.count == 1)
        #expect(recorder.outcomes.first?.wasSkipped == false)
    }

    @Test("skipping reports a skipped outcome with nothing to install")
    func skipReportsSkippedOutcome() {
        let recorder = Recorder()
        let view = makeView(detectedAgents: [.claudeCode], recorder: recorder)

        view.hookOffer(for: .claudeCode).wrappedValue = true
        view.skip()

        #expect(recorder.outcomes.count == 1)
        #expect(recorder.outcomes.first?.wasSkipped == true)
        #expect(recorder.outcomes.first?.acceptedHookOffers.isEmpty == true)
    }

    @Test("a hook switch writes through to the reported outcome")
    func hookToggleWritesThrough() {
        let recorder = Recorder()
        let view = makeView(detectedAgents: [.claudeCode, .codex], recorder: recorder)

        view.hookOffer(for: .codex).wrappedValue = true
        #expect(view.hookOffer(for: .codex).wrappedValue)
        #expect(!view.hookOffer(for: .claudeCode).wrappedValue)

        for _ in OnboardingStep.allCases {
            view.advance()
        }

        #expect(recorder.outcomes.first?.acceptedHookOffers == [.codex])
    }

    @Test("walking through without touching a switch installs nothing")
    func clickingThroughInstallsNothing() {
        let recorder = Recorder()
        let view = makeView(detectedAgents: [.claudeCode, .codex, .opencode], recorder: recorder)

        for _ in OnboardingStep.allCases {
            view.advance()
        }

        #expect(recorder.outcomes.first?.acceptedHookOffers.isEmpty == true)
    }

    @Test("the view offers exactly the detected agents")
    func offersOnlyDetectedAgents() {
        let recorder = Recorder()
        let view = makeView(detectedAgents: [.opencode], recorder: recorder)

        #expect(view.detectedAgents == [.opencode])
    }

    @Test("the closing step's button opens settings without ending the flow again")
    func openSettingsIsSeparateFromFinishing() {
        let recorder = Recorder()
        let view = makeView(recorder: recorder)

        for _ in OnboardingStep.allCases.dropLast() {
            view.advance()
        }
        #expect(view.currentStep == .done)

        view.advance()
        #expect(recorder.outcomes.count == 1)
        #expect(recorder.settingsOpenCount == 0)
    }
}
