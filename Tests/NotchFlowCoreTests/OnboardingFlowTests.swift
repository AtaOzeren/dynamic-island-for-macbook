import Foundation
import Testing

@testable import NotchFlowCore

@Suite("OnboardingFlow")
struct OnboardingFlowTests {
    @Test("the flow starts on welcome and walks the four documented steps in order")
    func stepsRunInDocumentedOrder() {
        var flow = OnboardingFlow()
        #expect(flow.step == .welcome)

        var visited: [OnboardingStep] = [flow.step]
        while !flow.isOnFinalStep {
            flow.advance()
            visited.append(flow.step)
        }

        #expect(visited == [.welcome, .permissions, .agents, .done])
        #expect(!flow.isComplete)
    }

    @Test("advancing past the last step completes the flow")
    func advancingPastDoneCompletes() {
        var flow = OnboardingFlow()
        for _ in OnboardingStep.allCases {
            flow.advance()
        }

        #expect(flow.isComplete)
        #expect(flow.step == .done)
    }

    @Test("a completed flow ignores further advances")
    func completedFlowIsTerminal() {
        var flow = OnboardingFlow()
        flow.skip()
        flow.advance()

        #expect(flow.isComplete)
        #expect(flow.step == .done)
    }

    @Test("the flow is skippable from every step")
    func skippableFromEveryStep() {
        for step in OnboardingStep.allCases {
            var flow = OnboardingFlow()
            while flow.step != step {
                flow.advance()
            }

            flow.skip()
            #expect(flow.isComplete)
        }
    }

    @Test("back moves to the previous step but never off the welcome screen")
    func backStopsAtWelcome() {
        var flow = OnboardingFlow()
        #expect(!flow.canGoBack)

        flow.goBack()
        #expect(flow.step == .welcome)

        flow.advance()
        flow.advance()
        #expect(flow.step == .agents)

        flow.goBack()
        #expect(flow.step == .permissions)
    }

    @Test("a flow clicked straight through accepts no hook offer")
    func clickingThroughAcceptsNothing() {
        var flow = OnboardingFlow(detectedAgents: [.claudeCode, .codex])
        for _ in OnboardingStep.allCases {
            flow.advance()
        }

        #expect(flow.acceptedHookOffers.isEmpty)
    }

    @Test("only an explicitly accepted offer is reported, in detection order")
    func acceptedOffersAreExplicitAndOrdered() {
        var flow = OnboardingFlow(detectedAgents: [.claudeCode, .codex, .opencode])
        flow.setHookOffer(.opencode, accepted: true)
        flow.setHookOffer(.claudeCode, accepted: true)

        #expect(flow.acceptedHookOffers == [.claudeCode, .opencode])
        #expect(flow.isAccepted(.claudeCode))
        #expect(!flow.isAccepted(.codex))
    }

    @Test("declining an offer withdraws an earlier acceptance")
    func decliningWithdrawsAcceptance() {
        var flow = OnboardingFlow(detectedAgents: [.codex])
        flow.setHookOffer(.codex, accepted: true)
        flow.setHookOffer(.codex, accepted: false)

        #expect(flow.acceptedHookOffers.isEmpty)
    }

    @Test("an undetected agent cannot be accepted")
    func undetectedAgentIsNotOfferable() {
        var flow = OnboardingFlow(detectedAgents: [.codex])
        flow.setHookOffer(.claudeCode, accepted: true)

        #expect(flow.acceptedHookOffers == [])
        #expect(!flow.isAccepted(.claudeCode))
    }

    @Test("skipping discards offers accepted before the user left")
    func skipDiscardsAcceptedOffers() {
        var flow = OnboardingFlow(detectedAgents: [.claudeCode])
        flow.setHookOffer(.claudeCode, accepted: true)
        flow.skip()

        #expect(flow.acceptedHookOffers.isEmpty)
    }

    @Test("a flow with no detected agent still reaches done")
    func emptyDetectionStillCompletes() {
        var flow = OnboardingFlow(detectedAgents: [])
        for _ in OnboardingStep.allCases {
            flow.advance()
        }

        #expect(flow.isComplete)
        #expect(flow.acceptedHookOffers.isEmpty)
    }
}
