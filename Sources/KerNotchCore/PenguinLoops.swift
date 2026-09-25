import Foundation

/// The penguin's loops: the stage's own — waddling the flank, or sitting
/// beside an icon — and one for each way it spends a mood. The moods every pet
/// spends alike — asleep, on a call, lying to watch — are in `PetLoops`.
///
/// Like the dog's, every loop ends in the pose it began with, and the stage's
/// loops sit for most of their length.
enum PenguinLoops {
    static func stageLoop(on stage: PetStage, in geometry: PetStageGeometry) -> PetTimeline? {
        switch stage {
        case .roaming: roaming(in: geometry)
        case .resting: resting(in: geometry)
        case .away: nil
        }
    }

    /// The flank's loop twice, then once more after a snow shower: about a
    /// minute and a quarter, so the snow comes about once a minute while the
    /// island stays empty. Beside an icon the island is never empty, so there
    /// it is the stage's own loop.
    static func idleLoop(on stage: PetStage, in geometry: PetStageGeometry) -> PetTimeline? {
        guard stage == .roaming else { return stageLoop(on: stage, in: geometry) }
        let stroll = roaming(in: geometry)
        var choreographer = PetChoreographer(
            startingAt: stroll.firstPose,
            spriteWidth: geometry.spriteWidth,
            species: .penguin
        )
        for _ in 0..<2 {
            choreographer.append(stroll)
            choreographer.show(stroll.firstPose.frame)
        }
        catchSnow(&choreographer)
        choreographer.append(stroll)
        return choreographer.loop()
    }

    /// Waiting on the user with a question mark over its head, and every few
    /// seconds the gesture it chose when the question came.
    static func asking(style: PetReaction, at home: PetPose, spriteWidth: Int) -> PetTimeline {
        var choreographer = PetChoreographer(
            startingAt: standing(at: home), spriteWidth: spriteWidth, species: .penguin)
        switch style {
        case .barkForAttention:
            choreographer.askQuestion(for: 2.5)
            choreographer.hold(2.5)
            choreographer.callOut(.squawk, times: 2)
            choreographer.askQuestion(for: 2.5)
            choreographer.hold(2.5)
        case .tapFoot:
            let length = 6.0
            choreographer.askQuestion(for: length)
            choreographer.hold(2)
            choreographer.alternate([.footTapUp, .footTapDown], every: 0.13, times: 6)
            choreographer.show(.stand)
            // Ends exactly where the question mark does, so it never blinks
            // out as the loop comes round.
            choreographer.hold(length - choreographer.time)
        default:
            choreographer.askQuestion(for: 7.6)
            choreographer.alternate([.flipperRaised, .stand], every: 1.2, times: 1)
            choreographer.hold(0.3)
            choreographer.alternate([.flipperRaised, .stand], every: 1.2, times: 1)
            choreographer.hold(2.5)
        }
        return choreographer.loop()
    }

    /// Music: nodding along where it sits, or swaying from foot to foot, with
    /// notes rising.
    static func listening(_ pastime: PetPastime, at home: PetPose, spriteWidth: Int) -> PetTimeline {
        switch pastime {
        case .swaying:
            var choreographer = PetChoreographer(
                startingAt: standing(at: home),
                spriteWidth: spriteWidth,
                species: .penguin
            )
            choreographer.hold(1.5)
            choreographer.show(.standBlink)
            choreographer.hold(0.15)
            choreographer.show(.stand)
            choreographer.hold(0.5)
            emitNotes(&choreographer, startingAt: [0.1, 0.9, 1.7])
            choreographer.alternate([.swayLeft, .beam, .swayRight, .beam], every: 0.22, times: 3)
            choreographer.show(.stand)
            choreographer.hold(0.5)
            return choreographer.loop()
        case .nodding, .typing, .fishing:
            var choreographer = PetChoreographer(startingAt: home, spriteWidth: spriteWidth, species: .penguin)
            choreographer.sit(for: 3, beats: [PetBeat(offset: 1.5, gesture: .blink)])
            emitNotes(&choreographer, startingAt: [0.1, 0.9])
            choreographer.alternate([.sitNod, .sit], every: 0.25, times: 4)
            choreographer.show(.sitBeam)
            choreographer.hold(0.3)
            choreographer.show(.sit)
            choreographer.hold(0.2)
            return choreographer.loop()
        }
    }

    /// An agent at work: the penguin typing away at a laptop of its own, or
    /// fishing through a hole in the ice.
    static func working(_ pastime: PetPastime, at home: PetPose, spriteWidth: Int) -> PetTimeline {
        switch pastime {
        case .fishing:
            fishing(at: home, spriteWidth: spriteWidth)
        case .typing, .nodding, .swaying:
            typing(at: home, spriteWidth: spriteWidth)
        }
    }

    /// Bursts of typing, a pause to read what came back, a blink.
    private static func typing(at home: PetPose, spriteWidth: Int) -> PetTimeline {
        var choreographer = PetChoreographer(
            startingAt: PetPose(position: home.position, facing: home.facing, frame: .typing),
            spriteWidth: spriteWidth,
            species: .penguin
        )
        choreographer.alternate([.typingLift, .typing], every: 0.13, times: 6)
        choreographer.hold(1.2)
        choreographer.show(.typingBlink)
        choreographer.hold(0.15)
        choreographer.show(.typing)
        choreographer.hold(0.8)
        choreographer.alternate([.typingLift, .typing], every: 0.13, times: 4)
        choreographer.hold(1.5)
        return choreographer.loop()
    }

    /// Waiting over the ice, a bite that bends the rod, and a fish leaping out
    /// of the hole and back in.
    private static func fishing(at home: PetPose, spriteWidth: Int) -> PetTimeline {
        var choreographer = PetChoreographer(
            startingAt: PetPose(position: home.position, facing: home.facing, frame: .fishing),
            spriteWidth: spriteWidth,
            species: .penguin
        )
        choreographer.hold(2)
        choreographer.show(.fishingBlink)
        choreographer.hold(0.15)
        choreographer.show(.fishing)
        choreographer.hold(1.5)
        choreographer.emit(.exclamation, at: choreographer.besidePet(PenguinAnchors.exclamation), for: 1.2)
        choreographer.alternate([.fishingBite, .fishing], every: 0.2, times: 3)
        let leap = [(13, 1), (13, 3), (14, 5), (14, 6), (15, 6), (15, 5), (14, 3), (14, 1)]
        choreographer.emit(
            .fish,
            at: leap.map { choreographer.besidePet(.fish, inset: $0.0, height: $0.1) },
            every: PetChoreographer.frameInterval
        )
        for (delay, inset) in [(0.0, 16), (Double(leap.count - 1) * PetChoreographer.frameInterval, 12)] {
            choreographer.emit(
                .droplet,
                along: (0..<4).map { step in
                    PetEffectStep(
                        after: delay + Double(step) * PetChoreographer.frameInterval,
                        point: choreographer.besidePet(.droplet, inset: inset + step % 2, height: 1 + step)
                    )
                },
                lasting: delay + 4 * PetChoreographer.frameInterval
            )
        }
        choreographer.hold(1.5)
        return choreographer.loop()
    }

    /// About twenty seconds on the empty flank: sitting most of it, a waddle
    /// to each end, a flap of the flippers and a preen between sits.
    static func roaming(in geometry: PetStageGeometry) -> PetTimeline {
        let home = PetPose(position: PetLoops.spot(0.18, in: geometry), facing: .right, frame: .sit)

        var choreographer = PetChoreographer(startingAt: home, spriteWidth: geometry.spriteWidth, species: .penguin)
        choreographer.sit(for: 3.2, beats: [PetBeat(offset: 1.4, gesture: .blink)])
        choreographer.standUp()
        choreographer.hold(0.3)
        flap(&choreographer, times: 3)
        choreographer.walk(to: PetLoops.spot(1, in: geometry))
        choreographer.hold(0.4)
        choreographer.show(.standBlink)
        choreographer.hold(0.15)
        choreographer.show(.stand)
        choreographer.hold(0.3)
        choreographer.alternate([.preenA, .preenB], every: 0.2, times: 3)
        choreographer.show(.stand)
        choreographer.hold(0.3)
        choreographer.sit(
            for: 4.0,
            beats: [PetBeat(offset: 1.5, gesture: .blink), PetBeat(offset: 3.0, gesture: .blink)]
        )
        choreographer.walk(to: PetLoops.spot(0.35, in: geometry))
        choreographer.sit(for: 2.6, beats: [PetBeat(offset: 1.2, gesture: .blink)])
        choreographer.walk(to: PetLoops.spot(0, in: geometry))
        choreographer.hold(0.3)
        choreographer.turn(.right)
        choreographer.hold(0.3)
        flap(&choreographer, times: 2)
        choreographer.sit(for: 3.4, beats: [PetBeat(offset: 1.6, gesture: .blink)])
        choreographer.walk(to: home.position)
        choreographer.sitDown()
        return choreographer.loop()
    }

    /// Beside a single icon, in the one place left: sitting, and every quarter
    /// of a minute standing for a flap, a look back and a preen.
    static func resting(in geometry: PetStageGeometry) -> PetTimeline {
        let home = PetPose(position: geometry.restingPosition, facing: .right, frame: .sit)

        var choreographer = PetChoreographer(startingAt: home, spriteWidth: geometry.spriteWidth, species: .penguin)
        choreographer.sit(
            for: 7.0,
            beats: [PetBeat(offset: 2.0, gesture: .blink), PetBeat(offset: 5.0, gesture: .blink)]
        )
        choreographer.standUp()
        choreographer.hold(0.3)
        flap(&choreographer, times: 2)
        choreographer.turn(.left)
        choreographer.hold(0.9)
        choreographer.show(.standBlink)
        choreographer.hold(0.15)
        choreographer.show(.stand)
        choreographer.hold(0.3)
        choreographer.turn(.right)
        choreographer.hold(0.3)
        choreographer.alternate([.preenA, .preenB], every: 0.2, times: 2)
        choreographer.show(.stand)
        choreographer.hold(0.2)
        choreographer.sit(
            for: 6.0,
            beats: [PetBeat(offset: 1.5, gesture: .blink), PetBeat(offset: 4.0, gesture: .blink)]
        )
        return choreographer.loop()
    }

    /// Snow drifting down around the penguin, which stands, looks up and
    /// catches a flake in its beak, then flaps for joy and sits back down.
    private static func catchSnow(_ choreographer: inout PetChoreographer) {
        choreographer.standUp()
        let flakes = [(2, 0), (25, 4), (-4, 8), (12, 2), (30, 11), (7, 14)]
        for (inset, delay) in flakes {
            choreographer.emit(
                .snowflake,
                along: (0...20).map { step in
                    PetEffectStep(
                        after: Double(delay + step * 2) * PetChoreographer.frameInterval,
                        point: choreographer.besidePet(.snowflake, inset: inset + (step / 3) % 2, height: 20 - step)
                    )
                },
                lasting: Double(delay + 42) * PetChoreographer.frameInterval
            )
        }
        let caught = [20, 18, 16, 14, 12, 10, 9]
        choreographer.emit(
            .snowflake,
            along: caught.enumerated().map { step, height in
                PetEffectStep(
                    after: 0.87 + Double(step) * PetChoreographer.frameInterval,
                    point: choreographer.besidePet(.snowflake, inset: PenguinAnchors.beak.inset, height: height)
                )
            },
            lasting: 0.87 + Double(caught.count) * PetChoreographer.frameInterval
        )
        choreographer.hold(0.9)
        choreographer.show(.lookUp)
        choreographer.hold(0.45)
        choreographer.show(.gulp)
        choreographer.hold(0.3)
        choreographer.show(.beam)
        choreographer.hold(0.5)
        choreographer.alternate([.cheerOut, .cheerUp], every: 0.13, times: 2)
        choreographer.show(.stand)
        choreographer.hold(0.8)
        choreographer.sitDown()
    }

    /// A few strokes of the flippers, standing.
    private static func flap(_ choreographer: inout PetChoreographer, times: Int) {
        choreographer.standUp()
        choreographer.alternate([.flippersOut, .flippersUp], every: 0.1, times: times)
        choreographer.show(.stand)
        choreographer.hold(0.2)
    }

    private static func emitNotes(_ choreographer: inout PetChoreographer, startingAt starts: [TimeInterval]) {
        let notes = PenguinAnchors.notes
        for start in starts {
            choreographer.emit(
                .note,
                along: choreographer.drifting(
                    .note,
                    fromInset: notes.inset,
                    height: notes.height,
                    steps: 6,
                    every: 0.18,
                    after: start
                ),
                lasting: start + 1.08
            )
        }
    }

    private static func standing(at home: PetPose) -> PetPose {
        PetPose(position: home.position, facing: home.facing, frame: .stand)
    }
}
