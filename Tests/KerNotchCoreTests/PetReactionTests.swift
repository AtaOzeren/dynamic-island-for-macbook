import Foundation
import Testing

@testable import KerNotchCore

/// Every reaction of every pet, played from every kind of pose a moment can
/// catch the pet in, on both stages it can react on.
@Suite("Pet reactions")
struct PetReactionTests {
    static let geometry = IslandPet.shiba.stageGeometry()
    static let openGeometry = IslandPet.shiba.openIslandStageGeometry(stripWidth: 85)

    /// Sitting, walking, in the air, asleep, bowed or on its belly, facing
    /// either way, at both ends of the flank — each in the poses that pet has.
    static func startingPoses(for species: PetSpecies) -> [PetPose] {
        switch species {
        case .dog:
            [
                PetPose(position: 6, facing: .right, frame: .sit),
                PetPose(position: 0, facing: .left, frame: .sitWag),
                PetPose(position: 20, facing: .right, frame: .strideA),
                PetPose(position: 34, facing: .left, frame: .stand),
                PetPose(position: 12, lift: 3, facing: .right, frame: .hop),
                PetPose(position: 9, facing: .right, frame: .sleep),
                PetPose(position: 17, facing: .left, frame: .playBow),
                PetPose(position: 3, facing: .right, frame: .crouch),
            ]
        case .penguin:
            [
                PetPose(position: 6, facing: .right, frame: .sit),
                PetPose(position: 0, facing: .left, frame: .sitBeam),
                PetPose(position: 20, facing: .right, frame: .strideA),
                PetPose(position: 34, facing: .left, frame: .stand),
                PetPose(position: 12, lift: 3, facing: .right, frame: .hop),
                PetPose(position: 9, facing: .right, frame: .sleep),
                PetPose(position: 17, facing: .left, frame: .slide),
                PetPose(position: 3, facing: .right, frame: .crouch),
            ]
        }
    }

    static func routine(
        _ reaction: PetReaction,
        of species: PetSpecies = .dog,
        on stage: PetStage,
        from pose: PetPose,
        geometry: PetStageGeometry = geometry
    ) -> PetRoutine {
        PetRoutine(
            stage: stage,
            from: pose,
            geometry: geometry,
            direction: PetDirection(species: species, reaction: reaction)
        )
    }

    /// Every reaction each pet plays, with the pet playing it.
    static let performances: [(PetSpecies, PetReaction)] = PetSpecies.allCases.flatMap { species in
        species.repertoire.map { (species, $0) }
    }

    /// The reactions a stage plays: all of them on an empty flank, only those
    /// that stay put beside an icon.
    static func performances(on stage: PetStage) -> [(PetSpecies, PetReaction)] {
        performances.filter { stage == .roaming || $0.1.needsRoom == false }
    }

    @Test("each pet plays only reactions it knows, and one for every moment", arguments: PetSpecies.allCases)
    func repertoireCoversEveryMoment(species: PetSpecies) {
        for moment in PetMoment.allCases {
            #expect(species.reactions(to: moment).isEmpty == false, "\(species) ignores \(moment)")
        }
        #expect(species.repertoire.isEmpty == false)
    }

    @Test(
        "a reaction starts where the pet is and hands over to the loop without a jump",
        arguments: [PetStage.roaming, .resting])
    func reactionsStartInPlaceAndEndOnTheLoop(stage: PetStage) throws {
        for (species, reaction) in Self.performances(on: stage) {
            for pose in Self.startingPoses(for: species) {
                let routine = Self.routine(reaction, of: species, on: stage, from: pose)
                let loop = try #require(routine.loop)

                #expect(routine.entrance.firstPose.position == pose.position, "\(species) \(reaction)")
                #expect(routine.entrance.lastPose == loop.firstPose, "\(species) \(reaction)")
                #expect(PetChoreographerTests.largestStep(in: routine.entrance) <= 1, "\(species) \(reaction)")
            }
        }
    }

    @Test("a reaction ends back on the floor, in a few seconds", arguments: performances)
    func reactionsEndOnTheFloor(species: PetSpecies, reaction: PetReaction) throws {
        let routine = Self.routine(reaction, of: species, on: .roaming, from: Self.startingPoses(for: species)[0])
        let end = try #require(routine.reactionEnd)

        #expect(end > 0)
        #expect(end <= routine.entrance.duration)
        #expect(end < 6)
        #expect(routine.entrance.pose(at: end).lift == 0)
        #expect(routine.entrance.pose(at: end).frame.posture != .airborne)
    }

    /// Only a hop takes the pet off the floor, and it always comes down.
    @Test("the pet is in the air only mid-hop", arguments: performances)
    func liftOnlyInTheAir(species: PetSpecies, reaction: PetReaction) {
        for pose in Self.startingPoses(for: species) {
            let entrance = Self.routine(reaction, of: species, on: .roaming, from: pose).entrance
            for keyframe in entrance.keyframes.dropFirst() {
                #expect(keyframe.pose.lift >= 0)
                #expect((keyframe.pose.lift > 0) == (keyframe.pose.frame == .hop), "\(reaction) at \(keyframe.time)")
            }
            #expect(entrance.lastPose.lift == 0)
        }
    }

    /// Beside an icon there is one place: the pet may sway in it, never leave
    /// it for the icon's.
    @Test("beside an icon a reaction stays in the one place left", arguments: performances(on: .resting))
    func restingReactionsStayPut(species: PetSpecies, reaction: PetReaction) {
        let home = Self.geometry.restingPosition
        let entrance = Self.routine(
            reaction,
            of: species,
            on: .resting,
            from: PetPose(position: home, facing: .right, frame: .sit)
        ).entrance

        #expect(entrance.keyframes.allSatisfy { abs($0.pose.position - home) <= 1 }, "\(reaction)")
    }

    @Test("with the flank to itself a reaction never runs off it", arguments: performances)
    func roamingReactionsStayOnTheFlank(species: PetSpecies, reaction: PetReaction) {
        for geometry in [Self.geometry, Self.openGeometry] {
            let range = geometry.roamingRange
            let entrance = Self.routine(
                reaction,
                of: species,
                on: .roaming,
                from: PetPose(position: range.lowerBound + 6, facing: .right, frame: .sit),
                geometry: geometry
            ).entrance

            #expect(
                entrance.keyframes.allSatisfy {
                    (range.lowerBound - 1...range.upperBound + 1).contains($0.pose.position)
                },
                "\(reaction)"
            )
        }
    }

    /// Turning mirrors the whole frame: standing square it is a turn, sitting
    /// it is a glance over the shoulder, and either way the pet stays put.
    @Test("the pet turns only on the spot, standing or sitting", arguments: performances)
    func turnsOnTheSpot(species: PetSpecies, reaction: PetReaction) {
        for pose in Self.startingPoses(for: species) {
            let entrance = Self.routine(reaction, of: species, on: .roaming, from: pose).entrance
            for (before, after) in zip(entrance.keyframes, entrance.keyframes.dropFirst())
            where before.pose.facing != after.pose.facing {
                #expect(before.pose.position == after.pose.position)
                #expect(after.pose.frame == .stand || after.pose.frame == .sit)
            }
        }
    }

    @Test("keyframes never share an instant, and effects keep to the reaction", arguments: performances)
    func timingIsWellFormed(species: PetSpecies, reaction: PetReaction) throws {
        let routine = Self.routine(reaction, of: species, on: .roaming, from: Self.startingPoses(for: species)[0])
        let times = routine.entrance.keyframes.map(\.time)
        let end = try #require(routine.reactionEnd)

        #expect(times == times.sorted())
        #expect(Set(times).count == times.count)
        for track in routine.entrance.effects {
            let effectTimes = track.keyframes.map(\.time)
            #expect(track.keyframes.first?.time == 0)
            #expect(effectTimes == effectTimes.sorted())
            #expect(track.keyframes.last?.point == nil, "\(reaction)'s \(track.effect) is left showing")
            #expect((effectTimes.last ?? 0) <= end + 0.001, "\(reaction)'s \(track.effect) outlasts it")
        }
    }

    @Test(
        "each reaction shows what it is about",
        arguments: [
            (PetReaction.surprisedHop, PetEffect.exclamation), (.headTilt, .question), (.barkForAttention, .barkLines),
            (.raisePaw, .question), (.lookAround, .question), (.sulk, .cloud), (.dazed, .star), (.celebrate, .sparkle),
            (.treat, .bone), (.timerAlarm, .bell), (.powerRush, .bolt), (.petted, .smallHeart), (.sweat, .sweat),
            (.shakeOff, .droplet),
        ]
    )
    func reactionsShowTheirEffect(reaction: PetReaction, effect: PetEffect) {
        let effects = Self.routine(reaction, on: .roaming, from: Self.startingPoses(for: .dog)[0]).entrance.effects

        #expect(effects.contains { $0.effect == effect })
    }

    @Test(
        "each reaction is drawn in its own poses",
        arguments: [
            (PetReaction.surprisedHop, PetFrame.hop), (.lieAndWatch, .lie), (.shakeOff, .shakeLeft),
            (.stretch, .playBow), (.stretch, .yawn), (.relief, .sitPant), (.headTilt, .curious),
            (.barkForAttention, .bark), (.raisePaw, .pawUp), (.sulk, .lieSad), (.dazed, .dazed),
            (.faint, .lieDazed), (.celebrate, .hop), (.zoomies, .strideA), (.treat, .holdBone),
            (.timerAlarm, .bark), (.powerRush, .hop), (.petted, .sitWag), (.sweat, .sitPant), (.dozeOff, .sleep),
        ]
    )
    func reactionsUseTheirPoses(reaction: PetReaction, frame: PetFrame) {
        let frames = Self.routine(reaction, on: .roaming, from: Self.startingPoses(for: .dog)[0]).entrance.keyframes
            .map(
                \.pose.frame)

        #expect(frames.contains(frame))
    }

    @Test("looking around turns the head both ways and ends facing the way it began")
    func lookingAroundComesBack() {
        let entrance = Self.routine(.lookAround, on: .roaming, from: Self.startingPoses(for: .dog)[0]).entrance
        let facings = Set(entrance.keyframes.map(\.pose.facing))

        #expect(facings == [.left, .right])
        #expect(entrance.pose(at: entrance.duration).facing == .right)
    }

    @Test("zoomies reach both ends of the flank and come home")
    func zoomiesCrossTheFlank() {
        let range = Self.geometry.roamingRange
        let entrance = Self.routine(.zoomies, on: .roaming, from: Self.startingPoses(for: .dog)[0]).entrance
        let positions = Set(entrance.keyframes.map(\.pose.position))

        #expect(positions.contains(range.lowerBound))
        #expect(positions.contains(range.upperBound))
    }

    @Test("an effect beside the pet swaps sides when the pet faces the other way")
    func effectsFollowTheFacing() throws {
        let right = Self.routine(.headTilt, on: .roaming, from: PetPose(position: 3, facing: .right, frame: .sit))
        let left = Self.routine(.headTilt, on: .roaming, from: PetPose(position: 3, facing: .left, frame: .sit))
        let rightMark = try #require(right.entrance.effects.first?.keyframes.compactMap(\.point).first)
        let leftMark = try #require(left.entrance.effects.first?.keyframes.compactMap(\.point).first)

        #expect(rightMark.position > 3 + Self.geometry.spriteWidth / 2)
        #expect(leftMark.position < 3 + Self.geometry.spriteWidth / 2)
        #expect(rightMark.height == leftMark.height)
    }

    @Test("a bark's lines point the way the pet faces")
    func barkLinesAreMirroredFacingLeft() throws {
        let left = Self.routine(
            .barkForAttention, on: .roaming, from: PetPose(position: 10, facing: .left, frame: .sit))
        let lines = try #require(left.entrance.effects.first { $0.effect == .barkLines })

        #expect(lines.isMirrored)
    }

    /// The hop's arc: up and back down, highest in the middle.
    @Test("a hop rises and falls", arguments: [2, 3, 4])
    func hopArc(height: Int) {
        let lifts = PetChoreographer.hopLifts(height: height)

        #expect(lifts.max() == height)
        #expect(lifts == Array(lifts.reversed()))
        #expect(lifts.allSatisfy { $0 > 0 })
    }
}
