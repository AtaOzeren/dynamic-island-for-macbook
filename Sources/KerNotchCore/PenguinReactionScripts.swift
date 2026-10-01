import Foundation

/// Where effects sit beside the penguin, whose head is further back on its
/// sprite than the dog's.
enum PenguinAnchors {
    static let exclamation = PetEffectAnchor(effect: .exclamation, inset: 9, height: 13)
    static let bell = PetEffectAnchor(effect: .bell, inset: 8, height: 13)
    static let bolt = PetEffectAnchor(effect: .bolt, inset: 8, height: 13)
    /// The middle of the head, which stars circle.
    static let head = PetEffectAnchor(effect: .star, inset: 7, height: 13)
    /// The head of a penguin flat on its back.
    static let headOnTheFloor = PetEffectAnchor(effect: .star, inset: 12, height: 5)
    /// The back of the head, where sweat runs down.
    static let backOfHead = PetEffectAnchor(effect: .sweat, inset: 3, height: 10)
    static let hearts = PetEffectAnchor(effect: .smallHeart, inset: 9, height: 12)
    static let notes = PetEffectAnchor(effect: .note, inset: 14, height: 9)
    /// Just over the open beak, where something dropping is caught.
    static let beak = PetEffectAnchor(effect: .fish, inset: 12, height: 7)
}

/// The penguin's reactions: the same moments as the dog's, answered with
/// flippers, a beak and a belly to slide on.
extension PetChoreographer {
    /// A reaction outside the penguin's repertoire plays nothing.
    mutating func performAsPenguin(_ reaction: PetReaction, on stage: PetStage, in geometry: PetStageGeometry) {
        switch reaction {
        case .surprisedHop, .runAlongEdge, .lieAndWatch, .wave, .shakeOff, .stretch, .relief, .preen:
            performPenguinIslandReaction(reaction, in: geometry)
        case .barkForAttention, .raisePaw, .tapFoot:
            performPenguinQuestion(reaction)
        case .dazed, .slip, .celebrate, .treat, .dance:
            performPenguinAgentNews(reaction)
        case .timerAlarm, .powerRush, .petted, .sweat, .dozeOff:
            performPenguinNews(reaction, on: stage, in: geometry)
        case .headTilt, .lookAround, .sulk, .faint, .zoomies:
            return
        }
    }

    /// A flipper fanning the face, `times` strokes up and down.
    mutating func fan(times: Int) {
        standUp()
        alternate([.fanUp, .fanDown], every: 0.13, times: times)
    }

    private mutating func performPenguinIslandReaction(_ reaction: PetReaction, in geometry: PetStageGeometry) {
        switch reaction {
        case .surprisedHop:
            hop(height: 4, carrying: PenguinAnchors.exclamation)
            sitDown()
            alternate([.sitBeam, .sit], every: 0.15, times: 2)
        case .runAlongEdge:
            travel(to: geometry.roamingRange.lowerBound, gait: .run)
            turn(.right)
            sitDown()
            alternate([.sitBeam, .sit], every: 0.15, times: 2)
        case .lieAndWatch:
            lieDown()
            hold(0.4)
        case .wave:
            standUp()
            alternate([.waveLow, .waveHigh], every: 0.2, times: 4)
            show(.stand)
            hold(0.3)
        case .shakeOff:
            shakeOff()
        case .stretch:
            standUp()
            show(.stretch)
            hold(1)
            show(.stand)
            hold(0.15)
            show(.standYawn)
            hold(0.7)
            show(.standBlink)
            hold(0.13)
            show(.stand)
            hold(0.3)
            sitDown()
        case .relief:
            fan(times: 7)
            show(.beam)
            hold(0.6)
            show(.stand)
            hold(0.3)
        case .preen:
            standUp()
            alternate([.preenA, .preenB], every: 0.2, times: 5)
            show(.standBlink)
            hold(0.15)
            show(.stand)
            hold(0.3)
        default:
            return
        }
    }

    private mutating func performPenguinQuestion(_ reaction: PetReaction) {
        switch reaction {
        case .barkForAttention:
            callOut(.squawk, times: 3, marking: PenguinAnchors.exclamation)
            askQuestion(for: 1.6)
            hold(1.6)
        case .raisePaw:
            standUp()
            askQuestion(for: 3.1)
            show(.flipperRaised)
            hold(1.2)
            show(.stand)
            hold(0.4)
            show(.flipperRaised)
            hold(1.2)
            show(.stand)
            hold(0.3)
        case .tapFoot:
            standUp()
            askQuestion(for: 2.5)
            alternate([.footTapUp, .footTapDown], every: 0.13, times: 9)
            show(.stand)
            hold(0.3)
        default:
            return
        }
    }

    private mutating func performPenguinAgentNews(_ reaction: PetReaction) {
        switch reaction {
        case .dazed:
            sitDown()
            show(.dazed)
            circleStars(around: PenguinAnchors.head, for: 2.25)
            for offset in [1, -1, -1, 1, 1, -1, -1, 1] {
                hold(0.25)
                sway(by: offset)
            }
            hold(0.25)
            show(.sitBlink)
            hold(0.13)
            show(.sit)
        case .slip:
            slipAndFall()
        case .celebrate:
            sparkle(for: 1.6)
            hop(height: 4)
            hop(height: 4)
            alternate([.cheerOut, .beam], every: 0.13, times: 2)
            show(.stand)
            hold(0.4)
        case .treat:
            catchFish()
        case .dance:
            dance()
        default:
            return
        }
    }

    private mutating func performPenguinNews(_ reaction: PetReaction, on stage: PetStage, in geometry: PetStageGeometry)
    {
        switch reaction {
        case .timerAlarm:
            standUp()
            let bell = besidePet(PenguinAnchors.bell)
            let ringing = (0..<20).map { step in
                PetPoint(position: bell.position + (step.isMultiple(of: 2) ? 0 : 1), height: bell.height)
            }
            emit(.bell, at: ringing, every: Self.frameInterval)
            callOut(.squawk, times: 3)
        case .powerRush:
            powerSlide(canSlide: stage == .roaming, in: geometry)
        case .petted:
            standUp()
            floatHearts(from: PenguinAnchors.hearts)
            alternate([.cheerOut, .cheerUp], every: 0.13, times: 5)
            show(.beam)
            hold(0.5)
            show(.stand)
            hold(0.3)
        case .sweat:
            standUp()
            sweatDrops(from: PenguinAnchors.backOfHead)
            fan(times: 9)
            show(.stand)
            hold(0.2)
        case .dozeOff:
            standUp()
            show(.standYawn)
            hold(0.6)
            show(.stand)
            hold(0.2)
            lieDown()
            hold(0.3)
            show(.lieBlink)
            hold(0.2)
            show(.lie)
            hold(0.3)
            show(.sleep)
            hold(0.4)
        default:
            return
        }
    }

    /// Feet gone from under it: flat on its back among a puff of dust, stars
    /// round its head, then up again shaking it off.
    private mutating func slipAndFall() {
        standUp()
        show(.stand)
        hold(0.3)
        show(.slip)
        hold(0.13)
        show(.onBack)
        emit(.puff, at: besidePet(.puff, inset: 2, height: 0), for: 0.3)
        emit(.dust, at: besidePet(.dust, inset: 7, height: 0), for: 0.2)
        emit(.puff, at: besidePet(.puff, inset: 15, height: 0), for: 0.3)
        hold(0.2)
        circleStars(around: PenguinAnchors.headOnTheFloor, for: 1.5)
        hold(1.6)
        standUp()
        alternate([.shakeLeft, .shakeRight], every: 0.1, times: 2)
        show(.stand)
        hold(0.3)
    }

    /// Looks up, and a fish drops into its open beak. It holds it a moment,
    /// swallows it whole and beams.
    private mutating func catchFish() {
        standUp()
        let beak = besidePet(PenguinAnchors.beak)
        emit(
            .fish,
            at: [12, 10, 8, 6, 4, 2, 0].map { PetPoint(position: beak.position, height: beak.height + $0) },
            every: 0.5 / 7
        )
        show(.lookUp)
        hold(0.5)
        show(.holdFish)
        hold(0.9)
        show(.gulp)
        hold(0.4)
        emit(
            .smallHeart,
            along: drifting(.smallHeart, fromInset: 9, height: 12, steps: 5, every: 0.14),
            lasting: 0.7
        )
        show(.beam)
        hold(0.6)
        show(.stand)
        hold(0.3)
    }

    /// Leans left and right with the flippers up, sparkles going off.
    private mutating func dance() {
        standUp()
        for (index, sparkle) in [
            PetEffectAnchor(effect: .sparkle, inset: -3, height: 10),
            PetEffectAnchor(effect: .sparkle, inset: 16, height: 13),
        ].enumerated() {
            emit(
                sparkle.effect,
                along: twinkling(at: besidePet(sparkle), for: 2, flashing: 0.2, after: Double(index) * 0.1),
                lasting: 2
            )
        }
        alternate([.danceLeft, .cheerUp, .danceRight, .cheerUp], every: 0.18, times: 3)
        show(.beam)
        hold(0.4)
        show(.stand)
        hold(0.3)
    }

    /// A bolt over its head, a hop, and — with the flank to itself — a slide
    /// out and back, then a beam.
    private mutating func powerSlide(canSlide: Bool, in geometry: PetStageGeometry) {
        emit(.bolt, along: twinkling(at: besidePet(PenguinAnchors.bolt), for: 1.3, flashing: 0.15), lasting: 1.3)
        hop(height: 3)
        if canSlide {
            let home = pose.position
            let facing = pose.facing
            travel(to: min(home + 12, geometry.roamingRange.upperBound), gait: .run)
            travel(to: home, gait: .run)
            turn(facing)
        }
        show(.beam)
        hold(0.5)
        show(.stand)
        hold(0.3)
    }
}
