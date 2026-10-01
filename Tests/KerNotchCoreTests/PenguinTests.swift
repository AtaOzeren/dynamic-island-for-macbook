import Foundation
import Testing

@testable import KerNotchCore

@Suite("Penguin art")
struct PenguinArtTests {
    private static let sheet = PetSpriteSheet.penguin

    @Test("the art is drawn two pixels to a point, 16 × 12 points on screen like the Shiba")
    func artIsRetinaDense() {
        #expect(Self.sheet.pixelsPerPoint == 2)
        #expect(Self.sheet.width == 32)
        #expect(Self.sheet.height == 24)
        #expect(Self.sheet.pointWidth == PetSpriteSheet.shiba.pointWidth)
        #expect(Self.sheet.pointHeight == PetSpriteSheet.shiba.pointHeight)
    }

    /// The head is the same block in every standing and sitting pose, so a
    /// blink touches nothing but the eyes: rows three to five of the head,
    /// between the far eye's edge and the near eye's.
    @Test(
        "a blink shuts the eyes and changes nothing else",
        arguments: [(PetFrame.stand, PetFrame.standBlink, 0), (.sit, .sitBlink, 4), (.typing, .typingBlink, 4)]
    )
    func blinkOnlyShutsTheEyes(open: PetFrame, shut: PetFrame, headTop: Int) {
        let changed = Self.changedPixels(from: open, to: shut)

        #expect(changed.isEmpty == false)
        #expect(changed.allSatisfy { (13...20).contains($0.column) && (headTop + 3...headTop + 5).contains($0.row) })
    }

    /// The island is black, so the coat is slate and its outline lit: a black
    /// penguin would be a white belly floating on nothing.
    @Test("the coat stands out from the island's black")
    func coatIsNotBlack() throws {
        let coat = try #require(Self.sheet.palette["K"])
        let rim = try #require(Self.sheet.palette["H"])

        #expect(Int(coat.red) + Int(coat.green) + Int(coat.blue) > 3 * 0x28)
        #expect(Int(rim.red) + Int(rim.green) + Int(rim.blue) > Int(coat.red) + Int(coat.green) + Int(coat.blue))
    }

    @Test("walking, one foot is off the floor at a time")
    func strideLiftsOneFoot() {
        let floor = Self.sheet.height - 1
        for stride in [PetFrame.strideA, .strideB] {
            let standing = (0..<Self.sheet.width).filter {
                Self.sheet.color(of: .stand, facing: .right, column: $0, row: floor) != nil
            }
            let walking = (0..<Self.sheet.width).filter {
                Self.sheet.color(of: stride, facing: .right, column: $0, row: floor) != nil
            }

            #expect(walking.count < standing.count, "\(stride)")
            #expect(walking.isEmpty == false, "\(stride)")
        }
    }

    private static func changedPixels(from before: PetFrame, to after: PetFrame) -> [(column: Int, row: Int)] {
        var changed: [(column: Int, row: Int)] = []
        for row in 0..<sheet.height {
            for column in 0..<sheet.width
            where sheet.color(of: before, facing: .right, column: column, row: row)
                != sheet.color(of: after, facing: .right, column: column, row: row)
            {
                changed.append((column, row))
            }
        }
        return changed
    }
}

@Suite("Penguin movement")
struct PenguinMovementTests {
    private static let standing = PetPose(position: 0, facing: .right, frame: .stand)

    @Test("in a hurry the penguin slides on its belly, a point at a time, and gets up at the end")
    func hurryingIsASlide() {
        var choreographer = PetChoreographer(startingAt: Self.standing, spriteWidth: 16, species: .penguin)
        choreographer.travel(to: 15, gait: .run)
        let timeline = choreographer.timeline()
        let moving = timeline.keyframes.filter { $0.pose.position != 0 }

        #expect(moving.allSatisfy { $0.pose.frame == .slide || $0.pose.position == 15 })
        #expect(PetChoreographerTests.largestStep(in: timeline) == 1)
        #expect(timeline.lastPose == PetPose(position: 15, facing: .right, frame: .stand))
        #expect(timeline.keyframes.contains { $0.pose.frame == .crouch })
    }

    @Test("strolling the penguin waddles on its feet")
    func walkingIsAWaddle() {
        var choreographer = PetChoreographer(startingAt: Self.standing, spriteWidth: 16, species: .penguin)
        choreographer.walk(to: 12)
        let frames = Set(choreographer.timeline().keyframes.map(\.pose.frame))

        #expect(frames.isSuperset(of: [.strideA, .strideB, .stand]))
        #expect(frames.contains(.slide) == false)
    }

    /// An icon arriving beside the pet has a place of its own: the pet only
    /// steps to the middle of its place, with nothing to hurry for.
    @Test("an icon arriving beside it has the penguin step aside, not slide", arguments: [0, 6])
    func iconArrivingIsAStep(position: Int) {
        let geometry = IslandPet.penguin.stageGeometry()
        let routine = PetRoutine(
            stage: .resting,
            from: PetPose(position: position, facing: .right, frame: .stand),
            geometry: geometry,
            species: .penguin
        )
        let frames = Set(routine.entrance.keyframes.map(\.pose.frame))

        #expect(frames.contains(.slide) == false)
        #expect(frames.contains(.strideA) || frames.contains(.strideB))
        #expect(routine.entrance.lastPose.position == geometry.restingPosition)
    }

    @Test("a dog in a hurry still runs")
    func dogsRun() {
        var choreographer = PetChoreographer(startingAt: Self.standing, spriteWidth: 16, species: .dog)
        choreographer.travel(to: 15, gait: .run)

        #expect(choreographer.timeline().keyframes.contains { $0.pose.frame == .slide } == false)
    }
}

/// The penguin's own ways of answering the island's moments.
@Suite("Penguin reactions")
struct PenguinReactionTests {
    private static let home = PetPose(position: 1, facing: .right, frame: .sit)

    private static func routine(_ reaction: PetReaction, from pose: PetPose = home) -> PetRoutine {
        PetReactionTests.routine(reaction, of: .penguin, on: .roaming, from: pose)
    }

    @Test(
        "each reaction shows what it is about",
        arguments: [
            (PetReaction.surprisedHop, PetEffect.exclamation), (.barkForAttention, .barkLines),
            (.barkForAttention, .question), (.raisePaw, .question), (.tapFoot, .question), (.dazed, .star),
            (.slip, .star), (.slip, .puff), (.celebrate, .sparkle), (.treat, .fish), (.dance, .sparkle),
            (.timerAlarm, .bell), (.powerRush, .bolt), (.petted, .smallHeart), (.sweat, .sweat),
            (.shakeOff, .droplet),
        ]
    )
    func reactionsShowTheirEffect(reaction: PetReaction, effect: PetEffect) {
        let effects = Self.routine(reaction).entrance.effects

        #expect(effects.contains { $0.effect == effect })
    }

    @Test(
        "each reaction is drawn in its own poses",
        arguments: [
            (PetReaction.surprisedHop, PetFrame.hop), (.runAlongEdge, .slide), (.lieAndWatch, .lie),
            (.wave, .waveHigh), (.shakeOff, .shakeLeft), (.stretch, .stretch), (.stretch, .standYawn),
            (.relief, .fanUp), (.preen, .preenA), (.barkForAttention, .squawk), (.raisePaw, .flipperRaised),
            (.tapFoot, .footTapUp), (.dazed, .dazed), (.slip, .onBack), (.celebrate, .hop), (.treat, .holdFish),
            (.treat, .gulp), (.dance, .danceLeft), (.timerAlarm, .squawk), (.powerRush, .slide),
            (.petted, .cheerUp), (.sweat, .fanDown), (.dozeOff, .sleep),
        ]
    )
    func reactionsUseTheirPoses(reaction: PetReaction, frame: PetFrame) {
        let frames = Self.routine(reaction).entrance.keyframes.map(\.pose.frame)

        #expect(frames.contains(frame))
    }

    @Test(
        "the dog's own reactions are not the penguin's",
        arguments: [
            PetReaction.headTilt, .lookAround, .sulk, .faint, .zoomies,
        ])
    func dogOnlyReactions(reaction: PetReaction) {
        #expect(PetSpecies.penguin.repertoire.contains(reaction) == false)
        #expect(PetSpecies.dog.repertoire.contains(reaction))
    }

    @Test(
        "the penguin's own reactions are not the dog's",
        arguments: [
            PetReaction.wave, .preen, .tapFoot, .slip, .dance,
        ])
    func penguinOnlyReactions(reaction: PetReaction) {
        #expect(PetSpecies.penguin.repertoire.contains(reaction))
        #expect(PetSpecies.dog.repertoire.contains(reaction) == false)
    }

    @Test(
        "the question mark hangs over the penguin's head, whichever way it faces",
        arguments: [
            PetFacing.right, .left,
        ])
    func questionOverTheHead(facing: PetFacing) throws {
        let position = 3
        let routine = Self.routine(.raisePaw, from: PetPose(position: position, facing: facing, frame: .stand))
        let question = try #require(routine.entrance.effects.first { $0.effect == .question })
        let mark = try #require(question.keyframes.compactMap(\.point).first)
        let sheet = PetSpriteSheet.penguin
        let crown = (0..<sheet.width).filter { sheet.color(of: .stand, facing: facing, column: $0, row: 0) != nil }
        let crownLeft = try #require(crown.min())
        let crownRight = try #require(crown.max())
        let crownMiddle = Double(position) + Double(crownLeft + crownRight) / 2 / Double(sheet.pixelsPerPoint)
        let markMiddle = Double(mark.position) + 1.5

        #expect(abs(markMiddle - crownMiddle) <= 2)
        #expect(mark.height > sheet.pointHeight)
    }

    @Test("a squawk's lines point the way the penguin faces")
    func squawkLinesAreMirroredFacingLeft() throws {
        let left = Self.routine(.barkForAttention, from: PetPose(position: 3, facing: .left, frame: .stand))
        let lines = try #require(left.entrance.effects.first { $0.effect == .barkLines })

        #expect(lines.isMirrored)
    }

    /// In its one place on the pill the slide is as long as the place allows;
    /// on the open island's strip it goes the full twelve points.
    @Test("with the flank to itself a charging penguin slides out and back, as far as its stage allows")
    func powerRushSlidesOutAndBack() throws {
        let geometries = [PetReactionTests.geometry, PetReactionTests.openGeometry]
        for geometry in geometries {
            let routine = PetReactionTests.routine(
                .powerRush, of: .penguin, on: .roaming, from: Self.home, geometry: geometry
            )
            let end = try #require(routine.reactionEnd)
            let reaction = routine.entrance.keyframes.filter { $0.time <= end }

            #expect(
                reaction.map(\.pose.position).max() == min(Self.home.position + 12, geometry.roamingRange.upperBound))
            #expect(routine.entrance.pose(at: end).position == Self.home.position)
            #expect(reaction.contains { $0.pose.frame == .slide })
        }
    }
}

/// What the penguin does between reactions.
@Suite("Penguin moods")
struct PenguinMoodTests {
    private static let geometry = IslandPet.penguin.stageGeometry()
    private static let home = PetPose(position: 6, facing: .right, frame: .sit)

    private static func routine(
        _ mood: PetMood,
        on stage: PetStage = .roaming,
        from pose: PetPose = home,
        askingStyle: PetReaction? = nil,
        pastime: PetPastime? = nil,
        napDelay: TimeInterval? = nil
    ) -> PetRoutine {
        PetRoutine(
            stage: stage,
            from: pose,
            geometry: geometry,
            direction: PetDirection(
                species: .penguin,
                mood: mood,
                askingStyle: askingStyle,
                pastime: pastime,
                napDelay: napDelay
            )
        )
    }

    /// Every mood, and every way the penguin has of spending it.
    private static let moods: [(PetMood, PetPastime?)] = [
        (.calm, nil), (.listening, .nodding), (.listening, .swaying), (.digging, .typing), (.digging, .fishing),
        (.onCall, nil), (.napping, nil), (.asking, nil),
    ]

    @Test("every mood's loop comes back round seamlessly", arguments: moods)
    func loopsCloseSeamlessly(mood: PetMood, pastime: PetPastime?) throws {
        for stage in [PetStage.roaming, .resting] {
            let loop = try #require(Self.routine(mood, on: stage, pastime: pastime).loop)

            #expect(loop.keyframes.last.map { $0.time < loop.duration } == true)
            #expect(loop.lastPose.position == loop.firstPose.position)
            #expect(loop.lastPose.facing == loop.firstPose.facing)
            #expect(loop.lastPose.lift == 0)
            for track in loop.effects {
                #expect(track.keyframes.first?.time == 0)
                #expect(track.keyframes.allSatisfy { $0.time <= loop.duration })
                #expect(track.keyframes.last?.point == nil)
            }
        }
    }

    @Test("a mood never takes the penguin off its place beside an icon", arguments: moods)
    func moodsStayInTheRestingPlace(mood: PetMood, pastime: PetPastime?) throws {
        let loop = try #require(Self.routine(mood, on: .resting, pastime: pastime).loop)

        #expect(loop.keyframes.allSatisfy { $0.pose.position == Self.geometry.restingPosition })
    }

    @Test(
        "each way of spending a mood has its own look",
        arguments: [
            (PetPastime.nodding, PetFrame.sitNod, PetEffect.note), (.swaying, .swayLeft, .note),
            (.typing, .typingLift, nil), (.fishing, .fishingBite, .fish),
        ] as [(PetPastime, PetFrame, PetEffect?)]
    )
    func pastimesLookTheirPart(pastime: PetPastime, frame: PetFrame, effect: PetEffect?) throws {
        let mood: PetMood = [.nodding, .swaying].contains(pastime) ? .listening : .digging
        let loop = try #require(Self.routine(mood, pastime: pastime).loop)

        #expect(loop.keyframes.contains { $0.pose.frame == frame })
        if let effect {
            #expect(loop.effects.contains { $0.effect == effect })
        }
    }

    @Test("at work the laptop or the rod never leaves", arguments: [PetPastime.typing, .fishing])
    func workStaysOut(pastime: PetPastime) throws {
        let loop = try #require(Self.routine(.digging, pastime: pastime).loop)
        let props: Set<PetFrame> = [.typing, .typingLift, .typingBlink, .fishing, .fishingBite, .fishingBlink]

        #expect(loop.keyframes.allSatisfy { props.contains($0.pose.frame) })
    }

    @Test(
        "while an agent waits there is always a question mark",
        arguments: PetSpecies.penguin.reactions(to: .agentAsked)
    )
    func askingKeepsTheQuestion(style: PetReaction) throws {
        let loop = try #require(Self.routine(.asking, askingStyle: style).loop)
        let questions = loop.effects.filter { $0.effect == .question }

        #expect(questions.isEmpty == false)
        for moment in stride(from: 0.05, to: loop.duration - 0.3, by: 0.1) where style != .barkForAttention {
            #expect(questions.contains { $0.point(at: moment) != nil }, "\(style) at \(moment)")
        }
    }

    @Test("an empty island's penguin waddles about, catches snow now and then, then naps")
    func idleHasSnowThenANap() throws {
        let routine = Self.routine(.idle(since: 0), napDelay: 300)
        let loop = try #require(routine.loop)
        let snowfalls = routine.entrance.effects.filter { $0.effect == .snowflake }

        #expect(loop.keyframes.allSatisfy { $0.pose.frame == .sleep })
        #expect(routine.entrance.duration >= 300)
        #expect(routine.entrance.duration < 300 + 80)
        #expect(routine.entrance.keyframes.filter { $0.time < 299 }.allSatisfy { $0.pose.frame.posture != .lying })
        #expect(snowfalls.isEmpty == false)
        // Snow about once a minute, not all the time.
        let showers = Set(snowfalls.compactMap { $0.keyframes.first { $0.point != nil }.map { Int($0.time / 60) } })
        #expect((3...6).contains(showers.count))
        #expect(routine.stillPose?.frame.isSitting == true)
    }

    @Test("beside an icon the island is never empty, so there is no snow")
    func noSnowBesideAnIcon() throws {
        let loop = try #require(PetLoops.idleLoop(on: .resting, in: Self.geometry, species: .penguin))

        #expect(loop.effects.contains { $0.effect == .snowflake } == false)
    }

    @Test("woken by something arriving, the penguin stretches and yawns")
    func wakingIsAStretch() {
        let routine = Self.routine(.calm, from: PetPose(position: 6, facing: .right, frame: .sleep))
        let frames = routine.entrance.keyframes.map(\.pose.frame)

        #expect(frames.contains(.stretch))
        #expect(frames.contains(.standYawn))
        #expect(routine.entrance.lastPose == routine.loop?.firstPose)
    }

    @Test("the stage's loops sit for most of their length", arguments: [PetStage.roaming, .resting])
    func stageLoopsMostlySit(stage: PetStage) throws {
        let loop = try #require(PenguinLoops.stageLoop(on: stage, in: Self.geometry))
        let boundaries = loop.keyframes.map(\.time) + [loop.duration]
        let sitting = zip(loop.keyframes, boundaries.dropFirst())
            .filter { $0.0.pose.frame.isSitting }
            .reduce(0) { $0 + ($1.1 - $1.0.time) }

        #expect(sitting / loop.duration > 0.5)
    }
}
