import Foundation

/// The loops the pet repeats between reactions: the stage's own — strolling
/// the flank, or sitting beside an icon — and one for each mood.
///
/// Every loop ends in the pose it began with, so Core Animation can repeat it
/// without a seam, and every loop sits for most of its length: a pet that
/// never stopped moving would be a distraction on the edge of the screen.
enum PetLoops {
    /// Where the pet settles on `stage`: a little in from the island's edge
    /// with the flank to itself, the outer place beside an icon.
    static func home(on stage: PetStage, in geometry: PetStageGeometry) -> PetPose? {
        switch stage {
        case .roaming: PetPose(position: spot(0.18, in: geometry), facing: .right, frame: .sit)
        case .resting: PetPose(position: geometry.restingPosition, facing: .right, frame: .sit)
        case .away: nil
        }
    }

    /// What the pet repeats on `stage` as `direction` has it. The moods that
    /// bed the pet down — asleep, or lying to watch the open island — keep it
    /// at `spot`, where it happened to be; every other mood sits it at home.
    static func loop(
        for direction: PetDirection,
        on stage: PetStage,
        in geometry: PetStageGeometry,
        at spot: PetPose
    ) -> PetTimeline? {
        guard let home = home(on: stage, in: geometry) else { return nil }
        let width = geometry.spriteWidth
        let bed = PetPose(
            position: min(max(spot.position, geometry.roamingRange.lowerBound), geometry.roamingRange.upperBound),
            facing: spot.facing,
            frame: .sit
        )
        switch direction.mood {
        case .napping:
            return napping(at: stage == .resting ? home : bed, spriteWidth: width)
        case .asking:
            return asking(style: direction.askingStyle ?? .headTilt, at: home, spriteWidth: width)
        case .listening:
            return listening(at: home, spriteWidth: width)
        case .digging:
            return digging(at: home, spriteWidth: width)
        case .onCall:
            return onCall(at: home, spriteWidth: width)
        case .calm, .idle, .hiding:
            if direction.isWatching {
                return watching(at: bed, spriteWidth: width)
            }
            return stageLoop(on: stage, in: geometry)
        }
    }

    /// The stage's own loop, whatever the mood.
    static func stageLoop(on stage: PetStage, in geometry: PetStageGeometry) -> PetTimeline? {
        switch stage {
        case .roaming: roaming(in: geometry)
        case .resting: resting(in: geometry)
        case .away: nil
        }
    }

    /// Asleep in place, the Zs drifting up from its head.
    static func napping(at spot: PetPose, spriteWidth: Int) -> PetTimeline {
        var choreographer = PetChoreographer(startingAt: bedded(spot, in: .sleep), spriteWidth: spriteWidth)
        for (effect, start) in [(PetEffect.smallZ, 0.2), (.bigZ, 1.4), (.smallZ, 2.6)] {
            choreographer.emit(
                effect,
                along: choreographer.drifting(effect, fromInset: 14, height: 8, steps: 5, every: 0.25, after: start),
                lasting: start + 1.25
            )
        }
        choreographer.hold(4.8)
        return choreographer.loop()
    }

    /// Lying where it is, blinking now and then, for as long as the island
    /// stays open.
    static func watching(at spot: PetPose, spriteWidth: Int) -> PetTimeline {
        var choreographer = PetChoreographer(startingAt: bedded(spot, in: .lie), spriteWidth: spriteWidth)
        choreographer.hold(3)
        choreographer.show(.lieBlink)
        choreographer.hold(0.15)
        choreographer.show(.lie)
        choreographer.hold(2.5)
        choreographer.show(.lieBlink)
        choreographer.hold(0.15)
        choreographer.show(.lie)
        return choreographer.loop()
    }

    /// Waiting on the user with a question mark over its head, and every few
    /// seconds the gesture it chose when the question came.
    static func asking(style: PetReaction, at home: PetPose, spriteWidth: Int) -> PetTimeline {
        var choreographer = PetChoreographer(startingAt: home, spriteWidth: spriteWidth)
        switch style {
        case .barkForAttention:
            choreographer.askQuestion(for: 2.5)
            choreographer.hold(2.5)
            choreographer.bark(times: 2)
            choreographer.askQuestion(for: 2.5)
            choreographer.hold(2.5)
        case .raisePaw:
            choreographer.askQuestion(for: 7.6)
            choreographer.alternate([.pawUp, .sit], every: 1.2, times: 1)
            choreographer.hold(0.3)
            choreographer.alternate([.pawUp, .sit], every: 1.2, times: 1)
            choreographer.hold(2.5)
        case .lookAround:
            for look in [PetFacing.right, .left, .right, .left] {
                choreographer.glance(look)
                choreographer.askQuestion(for: 1.5)
                choreographer.hold(1.5)
            }
            choreographer.glance(.right)
        default:
            choreographer.askQuestion(for: 7.1)
            for (frame, seconds) in [
                (PetFrame.curious, 2.0), (.curiousLow, 0.3), (.curious, 1.5), (.curiousLow, 0.3), (.curious, 2.0),
                (.sit, 1.0),
            ] {
                choreographer.show(frame)
                choreographer.hold(seconds)
            }
        }
        return choreographer.loop()
    }

    /// Sitting with the music, and every few seconds nodding along to it.
    static func listening(at home: PetPose, spriteWidth: Int) -> PetTimeline {
        var choreographer = PetChoreographer(startingAt: home, spriteWidth: spriteWidth)
        choreographer.sit(for: 3, beats: [PetBeat(offset: 1.5, gesture: .blink)])
        for start in [0.1, 0.9] {
            choreographer.emit(
                .note,
                along: choreographer.drifting(.note, fromInset: 15, height: 9, steps: 6, every: 0.18, after: start),
                lasting: start + 1.08
            )
        }
        choreographer.alternate([.sitNod, .sit], every: 0.25, times: 4)
        choreographer.alternate([.sitWag, .sit], every: 0.15, times: 1)
        choreographer.hold(0.2)
        return choreographer.loop()
    }

    /// Sitting a while, then digging in for a moment, earth flying back
    /// between its hind legs, as the agent it keeps company digs through its
    /// task.
    static func digging(at home: PetPose, spriteWidth: Int) -> PetTimeline {
        var choreographer = PetChoreographer(startingAt: home, spriteWidth: spriteWidth)
        choreographer.sit(
            for: 4.5,
            beats: [PetBeat(offset: 1.2, gesture: .blink), PetBeat(offset: 2.6, gesture: .pant)]
        )
        choreographer.standUp()
        choreographer.show(.playBow)
        choreographer.hold(0.13)
        let arc = [0, 2, 3, 3, 2, 1]
        for clod in 0..<8 {
            let start = 0.1 + Double(clod) * 0.18
            let path = arc.indices.map { step in
                PetEffectStep(
                    after: start + Double(step) * PetChoreographer.frameInterval,
                    point: choreographer.besidePet(.dirt, inset: 9 - step * 2 - clod % 3, height: 1 + arc[step])
                )
            }
            choreographer.emit(.dirt, along: path, lasting: start + 6 * PetChoreographer.frameInterval)
        }
        choreographer.alternate([.digA, .digB], every: 2.0 / 15, times: 6)
        choreographer.show(.stand)
        choreographer.hold(0.4)
        choreographer.sitDown()
        return choreographer.loop()
    }

    /// Headset on, listening to the call, nodding along now and then.
    static func onCall(at home: PetPose, spriteWidth: Int) -> PetTimeline {
        var choreographer = PetChoreographer(startingAt: home, spriteWidth: spriteWidth)
        choreographer.show(.headset)
        for (frame, seconds) in [
            (PetFrame.headset, 3.0), (.headsetNod, 0.25), (.headset, 0.25), (.headsetNod, 0.25), (.headset, 2.0),
            (.headsetBlink, 0.15), (.headset, 2.0),
        ] {
            choreographer.show(frame)
            choreographer.hold(seconds)
        }
        return choreographer.loop()
    }

    private static func bedded(_ spot: PetPose, in frame: PetFrame) -> PetPose {
        PetPose(position: spot.position, facing: spot.facing, frame: frame)
    }

    private static func spot(_ fraction: Double, in geometry: PetStageGeometry) -> Int {
        let range = geometry.roamingRange
        return range.lowerBound + Int((Double(range.upperBound - range.lowerBound) * fraction).rounded())
    }
}

extension PetLoops {
    /// About twenty seconds on the empty flank: sitting most of it, a stroll to
    /// each end, and something small — a blink, a wag, a pant — in every sit.
    static func roaming(in geometry: PetStageGeometry) -> PetTimeline {
        let home = PetPose(position: spot(0.18, in: geometry), facing: .right, frame: .sit)

        var choreographer = PetChoreographer(startingAt: home, spriteWidth: geometry.spriteWidth)
        choreographer.sit(
            for: 3.2,
            beats: [PetBeat(offset: 1.2, gesture: .blink), PetBeat(offset: 2.0, gesture: .pant)]
        )
        choreographer.walk(to: spot(1, in: geometry))
        choreographer.hold(0.5)
        choreographer.show(.standBlink)
        choreographer.hold(0.15)
        choreographer.show(.stand)
        choreographer.hold(0.35)
        choreographer.sit(
            for: 4.0,
            beats: [PetBeat(offset: 1.0, gesture: .wag), PetBeat(offset: 2.8, gesture: .blink)]
        )
        choreographer.walk(to: spot(0.35, in: geometry))
        choreographer.sit(for: 2.6, beats: [PetBeat(offset: 1.2, gesture: .blink)])
        choreographer.walk(to: spot(0, in: geometry))
        choreographer.hold(0.3)
        choreographer.turn(.right)
        choreographer.hold(0.4)
        choreographer.sit(
            for: 3.4,
            beats: [PetBeat(offset: 1.0, gesture: .pant), PetBeat(offset: 2.6, gesture: .blink)]
        )
        choreographer.walk(to: home.position)
        choreographer.sitDown()
        return choreographer.loop()
    }

    /// Beside a single icon, in the one place left: sitting, and every quarter
    /// of a minute standing to look back towards the edge of the island.
    static func resting(in geometry: PetStageGeometry) -> PetTimeline {
        let home = PetPose(position: geometry.restingPosition, facing: .right, frame: .sit)

        var choreographer = PetChoreographer(startingAt: home, spriteWidth: geometry.spriteWidth)
        choreographer.sit(
            for: 7.0,
            beats: [PetBeat(offset: 2.0, gesture: .blink), PetBeat(offset: 4.5, gesture: .wag)]
        )
        choreographer.standUp()
        choreographer.hold(0.4)
        choreographer.turn(.left)
        choreographer.hold(0.9)
        choreographer.show(.standBlink)
        choreographer.hold(0.15)
        choreographer.show(.stand)
        choreographer.hold(0.3)
        choreographer.turn(.right)
        choreographer.hold(0.3)
        choreographer.sit(
            for: 6.0,
            beats: [PetBeat(offset: 1.5, gesture: .pant), PetBeat(offset: 4.0, gesture: .blink)]
        )
        return choreographer.loop()
    }
}
