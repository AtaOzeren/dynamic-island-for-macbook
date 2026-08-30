import Testing

@testable import NotchFlowUI

@Suite("IslandAnimation")
@MainActor
struct IslandAnimationTests {
    private static let motion = IslandMotion.default

    @Test("expanding from compact runs the primary spring")
    func expandUsesTheSpring() {
        let curve = islandAnimationCurve(from: .compact, to: .expanded)

        #expect(curve == .spring(response: 0.35, dampingFraction: 0.8))
    }

    @Test("collapsing runs the same spring as expanding, so the pair feels symmetric")
    func collapseMatchesExpand() {
        let expand = islandAnimationCurve(from: .compact, to: .expanded)
        let collapse = islandAnimationCurve(from: .expanded, to: .compact)

        #expect(collapse == expand)
    }

    @Test("ordering in from hidden animates nothing")
    func orderingInIsUnanimated() {
        #expect(islandAnimationCurve(from: .hidden, to: .compact) == .none)
        #expect(islandAnimationCurve(from: .hidden, to: .expanded) == .none)
    }

    @Test("ordering out to hidden animates nothing")
    func orderingOutIsUnanimated() {
        #expect(islandAnimationCurve(from: .compact, to: .hidden) == .none)
        #expect(islandAnimationCurve(from: .expanded, to: .hidden) == .none)
    }

    @Test("a state that did not change animates nothing")
    func unchangedStateIsUnanimated() {
        #expect(islandAnimationCurve(from: .compact, to: .compact) == .none)
        #expect(islandAnimationCurve(from: .expanded, to: .expanded) == .none)
        #expect(islandAnimationCurve(from: .hidden, to: .hidden) == .none)
    }

    @Test("Reduce Motion replaces the spring with a cross-fade rather than skipping the change")
    func reduceMotionCrossFades() {
        let curve = islandAnimationCurve(from: .compact, to: .expanded, reduceMotion: true)

        #expect(curve == .crossFade(duration: Self.motion.reducedMotionCrossFadeDuration))
        #expect(curve.movesGeometry == false)
        #expect(curve != .none)
    }

    @Test("Reduce Motion never revives an animation the hidden state suppressed")
    func reduceMotionKeepsHiddenSilent() {
        #expect(islandAnimationCurve(from: .hidden, to: .compact, reduceMotion: true) == .none)
        #expect(islandAnimationCurve(from: .compact, to: .hidden, reduceMotion: true) == .none)
    }

    @Test("peeking eases out over the hover duration")
    func peekUsesEaseOut() {
        #expect(islandPeekCurve(in: .compact) == .easeOut(duration: 0.15))
    }

    @Test("peeking is shorter than expanding, so hover never reads as a state change")
    func peekIsShorterThanExpand() {
        #expect(Self.motion.peekDuration < Self.motion.springResponse)
    }

    @Test("nothing peeks while hidden or already expanded")
    func peekOnlyAppliesToCompact() {
        #expect(islandPeekCurve(in: .hidden) == .none)
        #expect(islandPeekCurve(in: .expanded) == .none)
    }

    @Test("Reduce Motion cross-fades the peek too")
    func reduceMotionPeek() {
        let curve = islandPeekCurve(in: .compact, reduceMotion: true)

        #expect(curve == .crossFade(duration: Self.motion.reducedMotionCrossFadeDuration))
        #expect(curve.movesGeometry == false)
    }

    @Test("an unanimated curve hands SwiftUI no animation at all")
    func noneCarriesNoAnimation() {
        #expect(IslandAnimationCurve.none.animation == nil)
    }

    @Test("every animated curve hands SwiftUI an animation")
    func animatedCurvesCarryAnAnimation() {
        #expect(IslandAnimationCurve.spring(response: 0.35, dampingFraction: 0.8).animation != nil)
        #expect(IslandAnimationCurve.easeOut(duration: 0.15).animation != nil)
        #expect(IslandAnimationCurve.crossFade(duration: 0.1).animation != nil)
    }

    @Test("only the travelling curves move geometry")
    func geometryMovingCurves() {
        #expect(IslandAnimationCurve.spring(response: 0.35, dampingFraction: 0.8).movesGeometry)
        #expect(IslandAnimationCurve.easeOut(duration: 0.15).movesGeometry)
        #expect(IslandAnimationCurve.crossFade(duration: 0.1).movesGeometry == false)
        #expect(IslandAnimationCurve.none.movesGeometry == false)
    }

    @Test("a retuned motion budget reaches the curves")
    func motionBudgetIsHonoured() {
        let slow = IslandMotion(
            springResponse: 0.5,
            springDamping: 0.6,
            peekDuration: 0.2,
            reducedMotionCrossFadeDuration: 0.05
        )

        #expect(
            islandAnimationCurve(from: .compact, to: .expanded, motion: slow)
                == .spring(response: 0.5, dampingFraction: 0.6)
        )
        #expect(islandPeekCurve(in: .compact, motion: slow) == .easeOut(duration: 0.2))
        #expect(
            islandAnimationCurve(from: .compact, to: .expanded, motion: slow, reduceMotion: true)
                == .crossFade(duration: 0.05)
        )
    }
}
