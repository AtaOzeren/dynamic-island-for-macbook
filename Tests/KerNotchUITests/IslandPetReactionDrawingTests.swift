import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// How the pet's reactions are drawn: the effects beside it, the height of a
/// hop, the open island's wider stage, and noticing the pointer.
@Suite("Island pet reactions drawn", .serialized)
@MainActor
struct IslandPetReactionDrawingTests {
    private static let pet = IslandPet.shiba
    private static let geometry = pet.stageGeometry()
    private static let placement = PetFixtures.placement
    private static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// A pet asking something since `startedAt`: a reaction with a question
    /// mark over it, then a loop that keeps one there.
    private static func asking(startedAt: TimeInterval) -> PetPerformance {
        let geometry = geometry
        let reaction = PetRoutine(
            stage: .roaming,
            from: PetPose(position: 6, facing: .right, frame: .sit),
            geometry: geometry,
            direction: PetDirection(species: .dog, mood: .asking, reaction: .headTilt, askingStyle: .headTilt)
        )
        return PetPerformance(routine: reaction, startedAt: startedAt)
    }

    private static func host(_ performance: PetPerformance, isStill: Bool = false) -> (PetLayerHostView, NSWindow) {
        let host = PetLayerHostView(frame: CGRect(origin: .zero, size: placement.canvasSize))
        host.configure(
            PetLayerHostView.Configuration(
                sprites: pet.sprites,
                performance: performance,
                placement: placement,
                isStill: isStill
            )
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: placement.canvasSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        return (host, window)
    }

    private static func effectLayers(of host: PetLayerHostView) -> [CALayer] {
        (host.layer?.sublayers ?? []).filter { $0 !== host.sprite }
    }

    @Test("a hop is drawn higher by its lift, a point at a time")
    func liftRaisesTheSprite() {
        let grounded = Self.placement.spriteFrame(at: 4)
        let raised = Self.placement.spriteFrame(at: 4, lift: 3)

        #expect(raised.minX == grounded.minX)
        #expect(raised.minY == grounded.minY + 3)
    }

    @Test("an effect is placed from the stage's origin and the pet's floor")
    func effectsArePlacedOnTheStage() {
        let origin = Self.placement.effectOrigin(at: PetPoint(position: 5, height: 13))

        #expect(origin.x == Self.placement.stageOriginX + 5)
        #expect(origin.y == Self.placement.baselineY + 13)
        #expect(Self.placement.effectSize(of: .question, in: .standard) == CGSize(width: 3, height: 4.5))
    }

    @Test("every effect is an image of its art, and mirrored is the mirror")
    func effectImagesAreTheArt() throws {
        let art = PetEffectArt.standard
        let images = PetSpriteImages.images(for: art)
        for effect in PetEffect.allCases {
            let image = try #require(images.image(for: effect, mirrored: false))
            #expect(image.width == art.pixelWidth(of: effect))
            #expect(image.height == art.pixelHeight(of: effect))
            #expect(images.image(for: effect, mirrored: true) != nil)
        }
        #expect(
            art.color(of: .barkLines, mirrored: true, column: 0, row: 0)
                == art.color(of: .barkLines, mirrored: false, column: 3, row: 0))
    }

    @Test("an effect plays as a position track and a visibility track")
    func effectTracks() throws {
        let track = PetEffectTrack(
            effect: .question,
            isMirrored: false,
            keyframes: [
                PetEffectKeyframe(time: 0, point: nil),
                PetEffectKeyframe(time: 1, point: PetPoint(position: 3, height: 13)),
                PetEffectKeyframe(time: 2, point: PetPoint(position: 3, height: 14)),
                PetEffectKeyframe(time: 4, point: nil),
            ]
        )
        let group = PetAnimation.repeatingEffect(track, lasting: 4, placement: Self.placement, beginningAt: 7)
        let tracks = try #require(group.animations as? [CAKeyframeAnimation])

        #expect(tracks.map(\.keyPath) == ["position", "hidden"])
        // The keyframe at the very end is dropped: it would show for no time.
        #expect(tracks[1].values as? [NSNumber] == [true, false, false])
        #expect(tracks.allSatisfy { $0.keyTimes == [0, 0.25, 0.5, 1] })
        #expect(group.repeatCount == .infinity)
        #expect(group.beginTime == 7)
        // Out of sight it waits where it will appear, rather than sliding in.
        let origins = (tracks[0].values as? [NSValue])?.map(\.pointValue)
        #expect(origins?.first == Self.placement.effectOrigin(at: PetPoint(position: 3, height: 13)))
    }

    @Test("a routine with effects gives each one a layer, out of sight until it plays")
    func effectsGetLayers() throws {
        let performance = Self.asking(startedAt: Self.uptime)
        let (host, window) = Self.host(performance)
        defer { window.close() }
        let layers = Self.effectLayers(of: host)
        let routine = performance.routine
        let expected = routine.entrance.effects.count + (routine.loop?.effects.count ?? 0)

        #expect(layers.count == expected)
        #expect(layers.allSatisfy { $0.isHidden })
        #expect(layers.allSatisfy { $0.animation(forKey: PetAnimation.effectKey) != nil })
    }

    @Test("held still, nothing is drawn beside the pet")
    func stillPetHasNoEffects() {
        let (host, window) = Self.host(Self.asking(startedAt: Self.uptime), isStill: true)
        defer { window.close() }

        #expect(Self.effectLayers(of: host).isEmpty)
    }

    @Test("a new routine takes the old one's effects away")
    func restartingClearsEffects() {
        let (host, window) = Self.host(Self.asking(startedAt: Self.uptime))
        defer { window.close() }
        let routine = PetRoutine(
            stage: .roaming,
            from: PetPose(position: 6, facing: .right, frame: .sit),
            geometry: Self.geometry,
            species: .dog
        )

        host.configure(
            PetLayerHostView.Configuration(
                sprites: Self.pet.sprites,
                performance: PetPerformance(routine: routine, startedAt: Self.uptime),
                placement: Self.placement,
                isStill: false
            )
        )

        #expect(Self.effectLayers(of: host).isEmpty)
    }

    @Test("the pointer counts as on the pet only over the pet itself")
    func pointerOverThePet() {
        let (host, window) = Self.host(Self.asking(startedAt: Self.uptime - 60), isStill: true)
        defer { window.close() }
        let frame = host.sprite.frame

        #expect(host.isOverPet(CGPoint(x: frame.midX, y: frame.midY)))
        #expect(host.isOverPet(CGPoint(x: frame.maxX + 4, y: frame.midY)) == false)
        #expect(host.isOverPet(CGPoint(x: frame.midX, y: frame.maxY + 6)) == false)
    }

    /// The open island is wider than the pill: its strip beside the notch
    /// gives the pet more room, measured from the same outer edge.
    @Test("the open island gives the pet a wider stage from the same edge")
    func openIslandStage() {
        let compact = IslandExtentInput(
            state: .compact,
            compact: ActivityManager().compactPresentation,
            hiddenMusicSlotIDs: [],
            pet: Self.pet,
            expanded: [ChargingActivity(state: .charging, level: BatteryLevel(fraction: 0.5))],
            disclosedInstances: [],
            registrationTimes: [:],
            notchSize: CGSize(width: 185, height: 32),
            layout: .minimalist
        )
        let open = IslandExtentInput(
            state: .expanded,
            compact: compact.compact,
            hiddenMusicSlotIDs: [],
            pet: Self.pet,
            expanded: compact.expanded,
            disclosedInstances: [],
            registrationTimes: [:],
            notchSize: compact.notchSize,
            layout: .minimalist
        )
        let small = islandPetStageGeometry(compact, for: Self.pet)
        let wide = islandPetStageGeometry(open, for: Self.pet)

        #expect(small == Self.geometry)
        #expect(wide.edgeInset == small.edgeInset)
        #expect(wide.roamingRange.upperBound > small.roamingRange.upperBound)
        #expect(CGFloat(wide.canvasWidth) <= (islandBodyWidth(open) - open.notchSize.width) / 2)
        #expect(islandBodyWidth(compact) == islandCompactPillGeometry(compact).size.width)
        #expect(islandBodyWidth(open) == islandConnectedGeometry(open).expandedBodyWidth)
    }
}
