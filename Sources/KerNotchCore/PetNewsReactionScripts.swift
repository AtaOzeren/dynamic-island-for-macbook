import Foundation

/// The dog's reactions to news: an agent failing or finishing, a countdown
/// running out, the charger, the watchdog, and the pointer moving onto the pet.
extension PetChoreographer {
    mutating func performAgentNews(_ reaction: PetReaction, in geometry: PetStageGeometry) {
        switch reaction {
        case .sulk:
            sulk()
        case .dazed:
            seeStars()
        case .faint:
            faint()
        case .celebrate:
            celebrate()
        case .zoomies:
            zoomies(in: geometry)
        case .treat:
            catchTreat()
        default:
            return
        }
    }

    mutating func performNews(_ reaction: PetReaction, on stage: PetStage, in geometry: PetStageGeometry) {
        switch reaction {
        case .timerAlarm:
            barkAtTheBell()
        case .powerRush:
            powerRush(canRun: stage == .roaming, in: geometry)
        case .petted:
            enjoyPetting()
        case .sweat:
            sweat()
        case .dozeOff:
            dozeOff()
        default:
            return
        }
    }

    /// Ears back, then down on the floor under a little rain cloud.
    private mutating func sulk() {
        sitDown()
        show(.earsBack)
        hold(0.7)
        lieDown()
        show(.lieSad)
        let duration = 2.2
        emit(.cloud, at: besidePet(.cloud, inset: 10, height: 8), for: duration)
        for (index, inset) in [11, 13, 14].enumerated() {
            var path: [PetEffectStep] = []
            var moment = Double(index) * 0.13
            while moment < duration {
                path.append(PetEffectStep(after: moment, point: besidePet(.raindrop, inset: inset, height: 7)))
                path.append(PetEffectStep(after: moment + 0.1, point: besidePet(.raindrop, inset: inset, height: 6)))
                path.append(PetEffectStep(after: moment + 0.2, point: nil))
                moment += 0.4
            }
            emit(.raindrop, along: path, lasting: duration)
        }
        hold(duration)
        sitDown()
    }

    /// The eye crossed out and three stars circling the head while the pet
    /// sways where it sits.
    private mutating func seeStars() {
        sitDown()
        show(.dazed)
        circleStars(around: PetEffectAnchor(effect: .star, inset: 11, height: 13), for: 2.25)
        for offset in [1, -1, -1, 1, 1, -1, -1, 1] {
            hold(0.25)
            sway(by: offset)
        }
        hold(0.25)
        show(.sitBlink)
        hold(0.13)
        show(.sit)
    }

    /// Keels over where it stands, lies flat out, then gets up and shakes it
    /// off.
    private mutating func faint() {
        standUp()
        show(.stand)
        hold(0.4)
        lieDown()
        show(.lieDazed)
        emit(.puff, at: besidePet(.puff, inset: 2, height: 0), for: 0.3)
        emit(.dust, at: besidePet(.dust, inset: 7, height: 0), for: 0.2)
        emit(.puff, at: besidePet(.puff, inset: 15, height: 0), for: 0.3)
        hold(1.8)
        standUp()
        alternate([.shakeLeft, .shakeRight], every: 0.1, times: 2)
        show(.stand)
        hold(0.3)
        sitDown()
    }

    /// Two hops for joy with sparkles going off around it.
    private mutating func celebrate() {
        sparkle(for: 1.6)
        hop(height: 4)
        hop(height: 4)
        sitDown()
        alternate([.sitWag, .sit], every: 0.13, times: 2)
        hold(0.4)
    }

    /// Tears to the far end of its stage, back to the near end, and home again,
    /// then sits panting. In its one place on the pill the dashes are a few
    /// points long, so it makes three laps of them rather than one.
    private mutating func zoomies(in geometry: PetStageGeometry) {
        let home = pose.position
        let range = geometry.roamingRange
        let laps = range.count < Self.zoomiesLapLength ? 3 : 1
        let ends = (0..<laps).flatMap { _ in [range.upperBound, range.lowerBound] } + [home]
        for end in ends {
            travel(to: end, gait: .run)
            emit(.dust, at: besidePet(.dust, inset: 2, height: 0), for: 0.2)
        }
        sitDown()
        alternate([.sitPant, .sit], every: 0.2, times: 3)
    }

    /// The shortest stage one lap of zoomies is worth running on.
    private static let zoomiesLapLength = 12

    /// Looks up, and a bone drops into its mouth. It wags with it, then it is
    /// gone.
    private mutating func catchTreat() {
        sitDown()
        let mouth = besidePet(.heldBone)
        emit(
            .bone,
            at: [17, 16, 15, 13, 11, 8, 6].map { PetPoint(position: mouth.position, height: pose.lift + $0) },
            every: 0.5 / 7
        )
        show(.curious)
        hold(0.5)
        show(.bark)
        hold(0.13)
        alternate([.holdBone, .holdBoneWag], every: 0.15, times: 3)
        emit(
            .smallHeart,
            along: drifting(.smallHeart, fromInset: 11, height: 12, steps: 5, every: 0.14),
            lasting: 0.7
        )
        show(.holdBone)
        hold(0.7)
        show(.sit)
        hold(0.3)
    }

    /// Barks at the bell ringing over its head.
    private mutating func barkAtTheBell() {
        sitDown()
        let bell = besidePet(.bell)
        let ringing = (0..<20).map { step in
            PetPoint(position: bell.position + (step.isMultiple(of: 2) ? 0 : 1), height: bell.height)
        }
        emit(.bell, at: ringing, every: Self.frameInterval)
        callOut(.bark, times: 3)
    }

    /// A bolt over its head, a hop, and — with the flank to itself — a dash
    /// out and back, then panting.
    private mutating func powerRush(canRun: Bool, in geometry: PetStageGeometry) {
        emit(.bolt, along: twinkling(at: besidePet(.bolt), for: 1.3, flashing: 0.15), lasting: 1.3)
        hop(height: 3)
        if canRun {
            let home = pose.position
            let facing = pose.facing
            travel(to: min(home + 12, geometry.roamingRange.upperBound), gait: .run)
            travel(to: home, gait: .run)
            turn(facing)
        }
        sitDown()
        alternate([.sitPant, .sit], every: 0.2, times: 3)
    }

    /// Wags hard with hearts floating up, then shuts its eyes a moment.
    private mutating func enjoyPetting() {
        sitDown()
        floatHearts(from: PetEffectAnchor(effect: .smallHeart, inset: 11, height: 12))
        alternate([.sitWag, .sit], every: 0.13, times: 6)
        show(.sitBlink)
        hold(0.5)
        show(.sit)
        hold(0.3)
    }

    /// Pants with a bead of sweat sliding down the back of its head.
    private mutating func sweat() {
        sitDown()
        sweatDrops(from: PetEffectAnchor(effect: .sweat, inset: 10, height: 10))
        alternate([.sitPant, .sit], every: 0.2, times: 6)
    }

    /// Ears back, a yawn, then down on the floor and asleep: the nap that
    /// follows lasts until the quota is back.
    private mutating func dozeOff() {
        sitDown()
        show(.earsBack)
        hold(0.5)
        show(.yawn)
        hold(0.6)
        show(.sit)
        hold(0.2)
        lieDown()
        hold(0.3)
        show(.lieBlink)
        hold(0.2)
        show(.lie)
        hold(0.3)
        show(.sleep)
        hold(0.4)
    }
}
