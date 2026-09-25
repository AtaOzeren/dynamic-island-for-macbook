import Foundation

/// Where an effect sits beside the pet: points in from the sprite's left edge
/// as drawn facing right, and up from its feet.
struct PetEffectAnchor {
    let effect: PetEffect
    let inset: Int
    let height: Int

    static let exclamation = PetEffectAnchor(effect: .exclamation, inset: 13, height: 13)
    static let question = PetEffectAnchor(effect: .question, inset: 11, height: 13)
    /// Just past the muzzle, level with the open mouth.
    static let barkLines = PetEffectAnchor(effect: .barkLines, inset: 16, height: 4)
    static let bolt = PetEffectAnchor(effect: .bolt, inset: 11, height: 13)
    static let bell = PetEffectAnchor(effect: .bell, inset: 11, height: 13)
    /// Where the bone the pet holds is drawn in its mouth.
    static let heldBone = PetEffectAnchor(effect: .bone, inset: 12, height: 6)
}

/// How a pet calls out: the pose it calls from, the frame with its mouth
/// open, and where the lines of the call hang in the air.
struct PetCall {
    let resting: PetFrame
    let calling: PetFrame
    let lines: PetEffectAnchor

    /// Sitting, barking past the muzzle.
    static let bark = PetCall(resting: .sit, calling: .bark, lines: .barkLines)
    /// Standing, squawking past the beak.
    static let squawk = PetCall(
        resting: .stand,
        calling: .squawk,
        lines: PetEffectAnchor(effect: .barkLines, inset: 13, height: 5)
    )
}

extension PetChoreographer {
    /// Plays `reaction` where the pet is, on `stage`, the way its species
    /// does. Ends on the floor — sitting, lying or standing — ready for the
    /// loop that follows.
    mutating func perform(_ reaction: PetReaction, on stage: PetStage, in geometry: PetStageGeometry) {
        switch species {
        case .dog: performAsDog(reaction, on: stage, in: geometry)
        case .penguin: performAsPenguin(reaction, on: stage, in: geometry)
        }
    }

    /// A reaction outside the dog's repertoire plays nothing.
    private mutating func performAsDog(_ reaction: PetReaction, on stage: PetStage, in geometry: PetStageGeometry) {
        switch reaction {
        case .surprisedHop, .runAlongEdge, .lieAndWatch, .shakeOff, .stretch, .relief:
            performIslandReaction(reaction, in: geometry)
        case .headTilt, .barkForAttention, .raisePaw, .lookAround:
            performQuestion(reaction)
        case .sulk, .dazed, .faint, .celebrate, .zoomies, .treat:
            performAgentNews(reaction, in: geometry)
        case .timerAlarm, .powerRush, .petted, .sweat, .dozeOff:
            performNews(reaction, on: stage, in: geometry)
        case .wave, .preen, .tapFoot, .slip, .dance:
            return
        }
    }

    /// A hop on the spot: down into a crouch, up `height` points and back,
    /// landing on its feet. An effect `carried` rides the hop, so an
    /// exclamation mark over the head stays over the head.
    mutating func hop(height: Int, carrying carried: PetEffectAnchor? = nil) {
        if pose.frame.posture != .sitting, pose.frame.posture != .crouching {
            standUp()
        }
        let lifts = Self.hopLifts(height: height)
        if let carried {
            let landing = Self.crouchDuration + Double(lifts.count) * Self.frameInterval
            var path = [PetEffectStep(after: 0, point: besidePet(carried))]
            for (index, lift) in lifts.enumerated() {
                path.append(
                    PetEffectStep(
                        after: Self.crouchDuration + Double(index) * Self.frameInterval,
                        point: besidePet(carried, raisedBy: lift)
                    )
                )
            }
            path.append(PetEffectStep(after: landing, point: besidePet(carried)))
            emit(carried.effect, along: path, lasting: landing + Self.crouchDuration + 0.25)
        }
        show(.crouch)
        hold(Self.crouchDuration)
        for lift in lifts {
            rise(to: lift)
            hold(Self.frameInterval)
        }
        land()
    }

    /// The height at each step of a hop's arc, the take-off and landing left
    /// off: a third of a second in the air at the pet's frame rate.
    static func hopLifts(height: Int) -> [Int] {
        let steps = 5
        return (1..<steps).map { step in
            Int((Double(height) * sin(Double.pi * Double(step) / Double(steps))).rounded())
        }
    }

    /// Calls out `times` times — barks, squawks — the lines of each call in
    /// the air before the mouth and `mark` over the head while it lasts.
    mutating func callOut(_ call: PetCall, times: Int, marking mark: PetEffectAnchor? = nil) {
        if call.resting.isSitting {
            sitDown()
        } else {
            standUp()
        }
        show(call.resting)
        let callLength = 0.2
        let pause = 0.15
        if let mark {
            emit(mark.effect, at: besidePet(mark), for: Double(times) * (callLength + pause))
        }
        for _ in 0..<times {
            emit(.barkLines, at: besidePet(call.lines), for: callLength, mirrored: pose.facing == .left)
            show(call.calling)
            hold(callLength)
            show(call.resting)
            hold(pause)
        }
        hold(0.3)
    }

    /// Three stars circling `anchor` — the head — for `duration` seconds.
    mutating func circleStars(around anchor: PetEffectAnchor, for duration: TimeInterval) {
        for phase in [0.0, 2.1, 4.2] {
            var path: [PetEffectStep] = []
            var moment = 0.0
            while moment < duration {
                let angle = 2 * Double.pi * moment / 0.9 + phase
                path.append(
                    PetEffectStep(
                        after: moment,
                        point: besidePet(
                            .star,
                            inset: anchor.inset + Int((5 * cos(angle)).rounded()),
                            height: anchor.height + Int((2 * sin(angle)).rounded())
                        )
                    )
                )
                moment += Self.frameInterval
            }
            emit(.star, along: path, lasting: duration)
        }
    }

    /// Sparkles and stars going off on either side for `duration` seconds.
    mutating func sparkle(for duration: TimeInterval) {
        let sparkles = [
            PetEffectAnchor(effect: .sparkle, inset: -3, height: 10),
            PetEffectAnchor(effect: .sparkle, inset: 16, height: 13),
            PetEffectAnchor(effect: .star, inset: -5, height: 4),
            PetEffectAnchor(effect: .star, inset: 18, height: 7),
        ]
        for (index, sparkle) in sparkles.enumerated() {
            emit(
                sparkle.effect,
                along: twinkling(at: besidePet(sparkle), for: duration, flashing: 0.2, after: Double(index) * 0.1),
                lasting: duration
            )
        }
    }

    /// Two small hearts and a big one floating up from `anchor`, the first
    /// heart's place, a little apart.
    mutating func floatHearts(from anchor: PetEffectAnchor) {
        let hearts = [
            (PetEffectAnchor(effect: .smallHeart, inset: anchor.inset, height: anchor.height), 0.0),
            (PetEffectAnchor(effect: .smallHeart, inset: anchor.inset + 3, height: anchor.height + 1), 0.4),
            (PetEffectAnchor(effect: .heart, inset: anchor.inset - 1, height: anchor.height), 0.8),
        ]
        for (heart, delay) in hearts {
            emit(
                heart.effect,
                along: drifting(
                    heart.effect,
                    fromInset: heart.inset,
                    height: heart.height,
                    steps: 5,
                    every: 0.15,
                    after: delay
                ),
                lasting: delay + 0.75
            )
        }
    }

    /// Two beads of sweat sliding down from `anchor`, a little over a second
    /// apart.
    mutating func sweatDrops(from anchor: PetEffectAnchor) {
        for start in [0.0, 1.2] {
            let path = (0..<4).map { step in
                PetEffectStep(
                    after: start + Double(step) * 0.2,
                    point: besidePet(.sweat, inset: anchor.inset, height: anchor.height - step)
                )
            }
            emit(.sweat, along: path, lasting: start + 0.8)
        }
    }

    func besidePet(_ anchor: PetEffectAnchor, raisedBy lift: Int = 0) -> PetPoint {
        besidePet(anchor.effect, inset: anchor.inset, height: anchor.height + lift)
    }

    /// `effect` drifting up from `inset`, `height` beside the pet: a point up
    /// each step, and a point across every `across` steps the way the pet
    /// faces.
    func drifting(
        _ effect: PetEffect,
        fromInset inset: Int,
        height: Int,
        steps: Int,
        every interval: TimeInterval,
        after delay: TimeInterval = 0,
        across: Int = 2
    ) -> [PetEffectStep] {
        (0..<steps).map { step in
            PetEffectStep(
                after: delay + Double(step) * interval,
                point: besidePet(effect, inset: inset + step / max(across, 1), height: height + step)
            )
        }
    }

    /// Shown for `flash` seconds and hidden for as long, over and over, for
    /// `duration` seconds from `delay`.
    func twinkling(
        at point: PetPoint,
        for duration: TimeInterval,
        flashing flash: TimeInterval,
        after delay: TimeInterval = 0
    ) -> [PetEffectStep] {
        var steps: [PetEffectStep] = []
        var moment = delay
        while moment < duration {
            steps.append(PetEffectStep(after: moment, point: point))
            steps.append(PetEffectStep(after: moment + flash, point: nil))
            moment += flash * 2
        }
        return steps
    }

    /// The question mark over the head, bobbing a point every quarter second.
    mutating func askQuestion(for duration: TimeInterval) {
        let low = besidePet(species.questionAnchor)
        let high = besidePet(species.questionAnchor, raisedBy: 1)
        let bobs = Int((duration / 0.25).rounded(.up))
        emit(
            .question,
            along: (0..<bobs).map { PetEffectStep(after: Double($0) * 0.25, point: $0.isMultiple(of: 2) ? low : high) },
            lasting: duration
        )
    }
}

/// A drop of water flung off the coat: where it leaves the pet and which way
/// it flies each step.
private struct PetDroplet {
    let inset: Int
    let height: Int
    let sideways: Int
    let upwards: Int

    static let shaken = [
        PetDroplet(inset: 2, height: 9, sideways: -1, upwards: 1),
        PetDroplet(inset: 15, height: 9, sideways: 1, upwards: 1),
        PetDroplet(inset: 6, height: 8, sideways: -1, upwards: 2),
        PetDroplet(inset: 12, height: 11, sideways: 1, upwards: 2),
        PetDroplet(inset: 3, height: 5, sideways: -1, upwards: 0),
        PetDroplet(inset: 14, height: 5, sideways: 1, upwards: 0),
    ]
}

/// The dog's reactions to the island opening and closing, and to an agent's
/// question.
extension PetChoreographer {
    private mutating func performIslandReaction(_ reaction: PetReaction, in geometry: PetStageGeometry) {
        switch reaction {
        case .surprisedHop:
            hop(height: 4, carrying: .exclamation)
            sitDown()
            alternate([.sitWag, .sit], every: 0.15, times: 2)
        case .runAlongEdge:
            runAlongEdge(in: geometry)
        case .lieAndWatch:
            lieDown()
            hold(0.4)
        case .shakeOff:
            shakeOff()
        case .stretch:
            stretchAndYawn()
        case .relief:
            sitDown()
            alternate([.sitPant, .sit], every: 0.2, times: 3)
            alternate([.sitWag, .sit], every: 0.13, times: 2)
        default:
            return
        }
    }

    private mutating func performQuestion(_ reaction: PetReaction) {
        switch reaction {
        case .headTilt:
            tiltHead()
        case .barkForAttention:
            callOut(.bark, times: 3, marking: .exclamation)
        case .raisePaw:
            sitDown()
            askQuestion(for: 2.1)
            alternate([.pawUp, .sit], every: 0.9, times: 2)
            alternate([.sitWag, .sit], every: 0.13, times: 2)
        case .lookAround:
            lookAround()
        default:
            return
        }
    }

    /// Off towards the island's new outer corner while the island grows under
    /// it, then settling there.
    private mutating func runAlongEdge(in geometry: PetStageGeometry) {
        travel(to: geometry.roamingRange.lowerBound, gait: .run)
        turn(.right)
        sitDown()
        alternate([.sitWag, .sit], every: 0.15, times: 2)
    }

    /// Shaking itself dry, drops flying off both sides.
    mutating func shakeOff() {
        standUp()
        show(.stand)
        hold(0.13)
        for (index, droplet) in PetDroplet.shaken.enumerated() {
            let path = (0..<5).map { step in
                PetEffectStep(
                    after: Double(index) * 0.1 + Double(step) * Self.frameInterval,
                    point: besidePet(
                        .droplet,
                        inset: droplet.inset + droplet.sideways * step,
                        height: droplet.height + droplet.upwards * min(step, 2) - max(step - 2, 0)
                    )
                )
            }
            emit(.droplet, along: path, lasting: Double(index) * 0.1 + 5 * Self.frameInterval)
        }
        alternate([.shakeLeft, .shakeRight], every: 0.1, times: 4)
        show(.stand)
        hold(0.2)
        sitDown()
    }

    private mutating func stretchAndYawn() {
        standUp()
        show(.stand)
        show(.playBow)
        hold(1)
        show(.stand)
        hold(0.13)
        sitDown()
        hold(0.2)
        show(.yawn)
        hold(0.7)
        show(.sit)
        hold(0.3)
        show(.sitBlink)
        hold(0.13)
        show(.sit)
    }

    private mutating func tiltHead() {
        sitDown()
        askQuestion(for: 3.1)
        for (frame, seconds) in [
            (PetFrame.curious, 0.9), (.curiousLow, 0.3), (.curious, 0.9), (.curiousLow, 0.3), (.curious, 0.7),
        ] {
            show(frame)
            hold(seconds)
        }
        show(.sit)
    }

    /// One way and then the other, the question mark following the head.
    private mutating func lookAround() {
        sitDown()
        let facing = pose.facing
        let away: PetFacing = facing == .right ? .left : .right
        for (look, seconds) in [(facing, 0.7), (away, 0.6), (facing, 0.6), (away, 0.5), (facing, 0.9)] {
            glance(look)
            askQuestion(for: seconds)
            hold(seconds)
        }
    }
}
