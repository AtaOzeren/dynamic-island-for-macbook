import Foundation
import Testing

@testable import NotchFlowCore

@Suite("AIAgentStateMachine")
struct AIAgentStateMachineTests {
    @Test("defines the seven documented agent states")
    func states() {
        #expect(
            AIAgentState.allCases == [
                .idle,
                .thinking,
                .working,
                .usingTool,
                .waitingForUser,
                .completed,
                .error,
            ])
    }

    @Test("accepts every legal state transition")
    func legalTransitions() {
        for transition in Self.legalTransitions {
            var stateMachine = AIAgentStateMachine(initialState: transition.source)

            let outcome = stateMachine.transition(to: transition.destination, at: date(1))

            #expect(outcome == .applied)
            #expect(stateMachine.state == transition.destination)
        }
    }

    @Test("rejects every undocumented state transition")
    func illegalTransitions() {
        for source in AIAgentState.allCases {
            for destination in AIAgentState.allCases where source != destination {
                guard !Self.legalTransitions.contains(Transition(source, destination)) else {
                    continue
                }
                var stateMachine = AIAgentStateMachine(initialState: source)

                let outcome = stateMachine.transition(to: destination, at: date(1))

                #expect(outcome == .rejected)
                #expect(stateMachine.state == source)
                #expect(stateMachine.lastTransitionAt == nil)
            }
        }
    }

    @Test("coalesces rapid duplicate updates without extending their timestamp")
    func rapidDuplicateUpdates() {
        var stateMachine = AIAgentStateMachine(duplicateCoalescingInterval: 1)
        let firstUpdate = date(1)

        #expect(stateMachine.transition(to: .thinking, at: firstUpdate) == .applied)
        #expect(stateMachine.transition(to: .thinking, at: date(1.5)) == .coalesced)
        #expect(stateMachine.lastTransitionAt == firstUpdate)
    }

    @Test("accepts a duplicate update after the coalescing interval")
    func duplicateAfterCoalescingInterval() {
        var stateMachine = AIAgentStateMachine(duplicateCoalescingInterval: 1)
        let laterUpdate = date(2)

        #expect(stateMachine.transition(to: .thinking, at: date(1)) == .applied)
        #expect(stateMachine.transition(to: .thinking, at: laterUpdate) == .applied)
        #expect(stateMachine.lastTransitionAt == laterUpdate)
    }

    @Test("auto-dismisses completed tasks exactly at their deadline")
    func completedAutoDismissTiming() {
        var stateMachine = AIAgentStateMachine(completedAutoDismissAfter: 5)

        #expect(stateMachine.transition(to: .thinking, at: date(1)) == .applied)
        #expect(stateMachine.transition(to: .completed, at: date(2)) == .applied)
        #expect(stateMachine.autoDismissAt == date(7))
        let didExpireBeforeDeadline = stateMachine.expire(at: date(6.999))
        #expect(!didExpireBeforeDeadline)
        #expect(stateMachine.state == .completed)
        let didExpireAtDeadline = stateMachine.expire(at: date(7))
        #expect(didExpireAtDeadline)
        #expect(stateMachine.state == .idle)
        #expect(stateMachine.autoDismissAt == nil)
    }

    @Test("does not auto-dismiss errors")
    func errorRequiresDismissal() {
        var stateMachine = AIAgentStateMachine(completedAutoDismissAfter: 5)

        #expect(stateMachine.transition(to: .thinking, at: date(1)) == .applied)
        #expect(stateMachine.transition(to: .error, at: date(2)) == .applied)
        #expect(stateMachine.autoDismissAt == nil)
        let didExpire = stateMachine.expire(at: date(100))
        #expect(!didExpire)
        #expect(stateMachine.state == .error)
    }

    @Test("starts a fresh task from either terminal state")
    func terminalStateStartsFreshTask() {
        for terminalState in [AIAgentState.completed, .error] {
            var stateMachine = AIAgentStateMachine(initialState: terminalState)

            #expect(stateMachine.transition(to: .thinking, at: date(1)) == .applied)
            #expect(stateMachine.state == .thinking)
            #expect(stateMachine.autoDismissAt == nil)
        }
    }

    private static let legalTransitions: Set<Transition> = [
        Transition(.idle, .thinking),
        Transition(.thinking, .working),
        Transition(.thinking, .usingTool),
        Transition(.thinking, .waitingForUser),
        Transition(.thinking, .completed),
        Transition(.thinking, .error),
        Transition(.working, .thinking),
        Transition(.working, .usingTool),
        Transition(.working, .waitingForUser),
        Transition(.working, .completed),
        Transition(.working, .error),
        Transition(.usingTool, .thinking),
        Transition(.usingTool, .working),
        Transition(.usingTool, .waitingForUser),
        Transition(.usingTool, .completed),
        Transition(.usingTool, .error),
        Transition(.waitingForUser, .thinking),
        Transition(.waitingForUser, .completed),
        Transition(.waitingForUser, .error),
        Transition(.completed, .idle),
        Transition(.completed, .thinking),
        Transition(.error, .idle),
        Transition(.error, .thinking),
    ]

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }
}

private struct Transition: Hashable {
    let source: AIAgentState
    let destination: AIAgentState

    init(_ source: AIAgentState, _ destination: AIAgentState) {
        self.source = source
        self.destination = destination
    }
}
