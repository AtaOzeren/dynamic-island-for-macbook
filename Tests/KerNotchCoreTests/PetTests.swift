import CoreGraphics
import Foundation
import Testing

@testable import KerNotchCore

@Suite("Pet stage")
struct PetStageTests {
    @Test(
        "the places the icons leave free decide the stage",
        arguments: [
            (-1, PetStage.away),
            (0, .away),
            (1, .resting),
            (2, .roaming),
            (3, .roaming),
        ]
    )
    func freePlacesDecideTheStage(freePlaces: Int, stage: PetStage) {
        #expect(PetStage(freePlaceCount: freePlaces) == stage)
    }

    @Test("the stage is one of the pill's own places")
    func stageGeometryFollowsThePill() {
        let geometry = PetStageGeometry(pill: .default, spriteWidth: 16)

        // One 22-point place: the 16-point pet has six points to walk.
        #expect(geometry.flankWidth == 22)
        #expect(geometry.roamingRange == 0...6)
        #expect(geometry.restingPosition == 3)
        #expect(geometry.offstagePosition == -26)
    }

    @Test("the stage is exactly as wide as the place the pill draws for it", arguments: PetSpecies.allCases)
    func flankMatchesThePill(species: PetSpecies) {
        let geometry = IslandPet(species: species).stageGeometry()

        #expect(CGFloat(geometry.flankWidth) == compactSideWidth(slotCount: 1, metrics: .default))
    }

    @Test("a pet wider than the flank still has somewhere to stand")
    func oversizedSpriteKeepsAPlace() {
        let geometry = PetStageGeometry(pill: .default, spriteWidth: 80)

        #expect(geometry.roamingRange == 0...0)
        #expect(geometry.restingPosition == 0)
    }
}

@Suite("Pet sprite sheet")
struct PetSpriteSheetTests {
    private static let sheet = PetSpriteSheet.shiba

    /// Every frame each pet's sheet draws, with the pet drawing it.
    static let drawnFrames: [(PetSpecies, PetFrame)] = PetSpecies.allCases.flatMap { species in
        PetFrame.allCases.filter { species.sprites.frames[$0] != nil }.map { (species, $0) }
    }

    @Test("every frame is drawn, at the sheet's size", arguments: drawnFrames)
    func everyFrameHasTheSheetsSize(species: PetSpecies, frame: PetFrame) throws {
        let sheet = species.sprites
        let rows = try #require(sheet.frames[frame])

        #expect(rows.count == sheet.height)
        #expect(rows.allSatisfy { $0.count == sheet.width })
    }

    @Test("every pixel is either empty or a palette colour", arguments: drawnFrames)
    func everyPixelIsInThePalette(species: PetSpecies, frame: PetFrame) throws {
        let sheet = species.sprites
        let rows = try #require(sheet.frames[frame])
        let keys = Set(sheet.palette.keys).union([PetSpriteSheet.transparentKey])

        #expect(rows.joined().allSatisfy(keys.contains))
    }

    @Test("facing left is facing right in a mirror", arguments: drawnFrames)
    func leftIsTheMirrorOfRight(species: PetSpecies, frame: PetFrame) {
        let sheet = species.sprites
        for row in 0..<sheet.height {
            for column in 0..<sheet.width {
                #expect(
                    sheet.color(of: frame, facing: .left, column: column, row: row)
                        == sheet.color(of: frame, facing: .right, column: sheet.width - 1 - column, row: row)
                )
            }
        }
    }

    /// A frame whose feet stopped short of the bottom row would make the pet
    /// hop a point every time it switched to it. The hop is the one frame drawn
    /// in the air, and it is raised by the pose's lift instead.
    @Test(
        "every frame on the ground stands on the same bottom row",
        arguments: drawnFrames.filter { $0.1.posture != .airborne }
    )
    func everyFrameReachesTheFloor(species: PetSpecies, frame: PetFrame) {
        let sheet = species.sprites
        let floor = (0..<sheet.width).compactMap {
            sheet.color(of: frame, facing: .right, column: $0, row: sheet.height - 1)
        }

        #expect(floor.isEmpty == false)
    }

    /// Standing up, sitting down, lying down, walking and landing go through
    /// the same poses whichever pet makes them, so every pet draws them.
    @Test("every pet draws the poses every pet moves through", arguments: PetSpecies.allCases)
    func sharedPosesAreDrawn(species: PetSpecies) {
        let shared: [PetFrame] = [
            .stand, .standBlink, .strideA, .strideB, .shakeLeft, .shakeRight, .crouch, .hop, .sit, .sitBlink,
            .sitNod, .dazed, .headset, .headsetBlink, .headsetNod, .lie, .lieBlink, .sleep,
        ]

        #expect(shared.filter { species.sprites.frames[$0] == nil } == [])
    }

    @Test("nothing is drawn outside the art")
    func outsideTheArtIsEmpty() {
        let sheet = Self.sheet

        #expect(sheet.color(of: .stand, facing: .right, column: -1, row: 5) == nil)
        #expect(sheet.color(of: .stand, facing: .right, column: sheet.width, row: 5) == nil)
        #expect(sheet.color(of: .stand, facing: .right, column: 5, row: -1) == nil)
        #expect(sheet.color(of: .stand, facing: .right, column: 5, row: sheet.height) == nil)
    }

    @Test(
        "a blink shuts the eye and changes nothing else",
        arguments: [(PetFrame.stand, PetFrame.standBlink), (.sit, .sitBlink)]
    )
    func blinkOnlyShutsTheEye(open: PetFrame, shut: PetFrame) {
        let eyeColours = [Self.sheet.palette["K"], Self.sheet.palette["W"]]
        let changed = Self.changedPixels(from: open, to: shut)

        // The whole eye, catchlight included, and nothing around it.
        #expect(changed.count == 4)
        #expect(changed.allSatisfy { eyeColours.contains($0.before) })
    }

    @Test("panting opens the mouth and shows the tongue, and changes nothing else")
    func pantOnlyOpensTheMouth() {
        let mouthColours = [Self.sheet.palette["P"], Self.sheet.palette["p"]]
        let changed = Self.changedPixels(from: .sit, to: .sitPant)

        #expect(changed.isEmpty == false)
        #expect(changed.allSatisfy { mouthColours.contains($0.after) })
    }

    /// Two image pixels to a point is one to a device pixel on a Retina panel:
    /// the densest the art can be without drawing below the screen's grain.
    @Test("the art is drawn two pixels to a point, 16 × 12 points on screen")
    func artIsRetinaDense() {
        #expect(Self.sheet.pixelsPerPoint == 2)
        #expect(Self.sheet.width == 32)
        #expect(Self.sheet.height == 24)
        #expect(Self.sheet.pointWidth == 16)
        #expect(Self.sheet.pointHeight == 12)
    }

    private static func changedPixels(
        from before: PetFrame,
        to after: PetFrame
    ) -> [(before: PetColor?, after: PetColor?)] {
        var changed: [(before: PetColor?, after: PetColor?)] = []
        for row in 0..<sheet.height {
            for column in 0..<sheet.width {
                let old = sheet.color(of: before, facing: .right, column: column, row: row)
                let new = sheet.color(of: after, facing: .right, column: column, row: row)
                if old != new {
                    changed.append((old, new))
                }
            }
        }
        return changed
    }

    @Test("the sitting frames are the ones on haunches")
    func sittingFrames() {
        #expect(
            Set(PetFrame.allCases.filter(\.isSitting)) == [
                .sit, .sitBlink, .sitPant, .sitWag, .sitNod, .bark, .yawn, .curious, .curiousLow, .earsBack,
                .pawUp, .dazed, .holdBone, .holdBoneWag, .headset, .headsetBlink, .headsetNod, .sitBeam, .typing,
                .typingLift, .typingBlink, .fishing, .fishingBite, .fishingBlink,
            ]
        )
    }

    @Test("a palette colour reads back as its hex")
    func colourFromHex() {
        let color = PetColor(hex: 0xE39B4A)

        #expect(color.red == 0xE3)
        #expect(color.green == 0x9B)
        #expect(color.blue == 0x4A)
    }
}

@Suite("Pet preferences")
struct PetPreferencesTests {
    @Test("the pet stays off the island until the user asks for it")
    func offByDefault() {
        #expect(PetPreferences.default.isEnabled == false)
        #expect(PetPreferences.default.pet == nil)
        #expect(SettingsKey<Bool>.showIslandPet.defaultValue == false)
        #expect(SettingsKeys.registeredDefaults[SettingsKey<Bool>.showIslandPet.name] as? Bool == false)
    }

    @Test("switching the pet on puts the Shiba on the island")
    func switchedOnIsTheShiba() {
        #expect(PetPreferences(isEnabled: true).pet == .shiba)
        #expect(SettingsKey<PetSpecies>.petSpecies.defaultValue == .dog)
        #expect(SettingsKeys.registeredDefaults[SettingsKey<PetSpecies>.petSpecies.name] as? String == "dog")
    }

    @Test("picking the penguin puts the penguin on the island, once it is switched on")
    func pickedPenguinIsThePenguin() {
        #expect(PetPreferences(isEnabled: true, species: .penguin).pet == .penguin)
        #expect(PetPreferences(isEnabled: false, species: .penguin).pet == nil)
    }

    @Test("each pet is drawn from its own sheet, at the same size", arguments: PetSpecies.allCases)
    func eachPetHasItsSheet(species: PetSpecies) {
        let pet = IslandPet(species: species)

        #expect(pet.sprites == species.sprites)
        #expect(pet.stageGeometry() == IslandPet.shiba.stageGeometry())
    }
}
