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

extension PetChoreographer {
    /// Plays `reaction` where the pet is, on `stage`. Ends on the floor —
    /// sitting, lying or standing — ready for the loop that follows.
    mutating func perform(_ reaction: PetReaction, on stage: PetStage, in geometry: PetStageGeometry) {
        switch reaction {
        case .surprisedHop, .runAlongEdge, .lieAndWatch, .shakeOff, .stretch, .relief:
            performIslandReaction(reaction, in: geometry)
        case .headTilt, .barkForAttention, .raisePaw, .lookAround:
            performQuestion(reaction)
        case .sulk, .dazed, .faint, .celebrate, .zoomies, .treat:
            performAgentNews(reaction, in: geometry)
        case .timerAlarm, .powerRush, .petted, .sweat, .dozeOff:
            performNews(reaction, on: stage, in: geometry)
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

    /// Barks `times` times, the lines of each bark in the air before the muzzle
    /// and `mark` over the head while it lasts.
    mutating func bark(times: Int, marking mark: PetEffectAnchor? = nil) {
        sitDown()
        let barkLength = 0.2
        let pause = 0.15
        if let mark {
            emit(mark.effect, at: besidePet(mark), for: Double(times) * (barkLength + pause))
        }
        for _ in 0..<times {
            emit(.barkLines, at: besidePet(.barkLines), for: barkLength, mirrored: pose.facing == .left)
            show(.bark)
            hold(barkLength)
            show(.sit)
            hold(pause)
        }
        hold(0.3)
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
        let low = besidePet(.question)
        let high = besidePet(.question, raisedBy: 1)
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

/// The reactions to the island opening and closing, and to an agent's
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
            bark(times: 3, marking: .exclamation)
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

    private mutating func shakeOff() {
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
