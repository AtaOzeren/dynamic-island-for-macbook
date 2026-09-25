import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// How the pet is drawn: the art as images, where it stands on the pill, and
/// the Core Animation that moves it.
@Suite("Island pet drawing", .serialized)
@MainActor
struct IslandPetDrawingTests {
    private static let pet = IslandPet.shiba
    private static let geometry = pet.stageGeometry()
    private static let placement = PetPlacement(pet: pet, pillHeight: 32, metrics: .default)

    /// Now, on the clock the pet's routine is timed by.
    private static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private static func bytes(of image: CGImage) throws -> [UInt8] {
        let data = try #require(image.dataProvider?.data as Data?)
        return [UInt8](data)
    }

    private static func routine(_ stage: PetStage) -> PetRoutine {
        PetRoutine(
            stage: stage,
            from: PetPose(position: geometry.offstagePosition, facing: .right, frame: .stand),
            geometry: geometry,
            species: .dog
        )
    }

    private static func configuration(
        _ stage: PetStage,
        startedAt: TimeInterval,
        isStill: Bool = false
    ) -> PetLayerHostView.Configuration {
        PetLayerHostView.Configuration(
            sprites: pet.sprites,
            performance: PetPerformance(routine: routine(stage), startedAt: startedAt),
            placement: placement,
            isStill: isStill
        )
    }

    /// A host that has landed in a window, which is when it arms its routine.
    private static func hostInWindow(_ configuration: PetLayerHostView.Configuration) -> (PetLayerHostView, NSWindow) {
        let host = PetLayerHostView(frame: CGRect(origin: .zero, size: placement.canvasSize))
        host.configure(configuration)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: placement.canvasSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        // Closed by the test while it still holds the window.
        window.isReleasedWhenClosed = false
        window.contentView = host
        return (host, window)
    }

    // MARK: - Images

    @Test("each frame is an image of the art, one pixel per art pixel")
    func framesAreTheArt() throws {
        let image = try #require(petSpriteImage(of: Self.pet.sprites, frame: .stand, facing: .right))
        let bytes = try Self.bytes(of: image)
        let sheet = Self.pet.sprites

        #expect(image.width == sheet.width)
        #expect(image.height == sheet.height)
        for row in 0..<sheet.height {
            for column in 0..<sheet.width {
                let offset = (row * sheet.width + column) * 4
                if let color = sheet.color(of: .stand, facing: .right, column: column, row: row) {
                    #expect(Array(bytes[offset..<offset + 4]) == [color.red, color.green, color.blue, 255])
                } else {
                    #expect(bytes[offset + 3] == 0)
                }
            }
        }
    }

    @Test("facing left draws the art mirrored")
    func leftImageIsMirrored() throws {
        let sheet = Self.pet.sprites
        let right = try Self.bytes(of: try #require(petSpriteImage(of: sheet, frame: .strideA, facing: .right)))
        let left = try Self.bytes(of: try #require(petSpriteImage(of: sheet, frame: .strideA, facing: .left)))

        for row in 0..<sheet.height {
            for column in 0..<sheet.width {
                let mirrored = (row * sheet.width + (sheet.width - 1 - column)) * 4
                let offset = (row * sheet.width + column) * 4
                #expect(left[offset..<offset + 4] == right[mirrored..<mirrored + 4])
            }
        }
    }

    @Test("every frame is drawn once, facing both ways, and kept", arguments: PetSpecies.allCases)
    func imagesAreDrawnOnce(species: PetSpecies) {
        let first = PetSpriteImages.images(for: species.sprites)
        let second = PetSpriteImages.images(for: species.sprites)

        for frame in PetFrame.allCases where species.sprites.frames[frame] != nil {
            for facing in [PetFacing.left, .right] {
                #expect(first.image(for: frame, facing: facing) != nil)
                #expect(first.image(for: frame, facing: facing) === second.image(for: frame, facing: facing))
            }
        }
    }

    /// A pet's images are only the poses it takes: the other pet's are never
    /// shown, so they are never drawn.
    @Test("a pet's images are only its own poses")
    func onlyItsOwnPosesAreDrawn() {
        let dog = PetSpriteImages.images(for: PetSpriteSheet.shiba)
        let penguin = PetSpriteImages.images(for: PetSpriteSheet.penguin)

        #expect(dog.image(for: .slide, facing: .right) == nil)
        #expect(penguin.image(for: .playBow, facing: .right) == nil)
        #expect(penguin.image(for: .slide, facing: .right) != nil)
    }

    // MARK: - Placement

    @Test("the pet stands level with the bottom of the icons")
    func standsOnTheIconsBaseline() {
        let metrics = CompactPillMetrics.default
        let pillHeight: CGFloat = 32
        let bandBottomFromTop = (pillHeight - metrics.slotHeight) / 2 + metrics.iconBandTopInset + metrics.symbolSize
        let sprite = Self.placement.spriteFrame(at: 0)

        // Layer coordinates run up from the bottom.
        #expect(pillHeight - sprite.minY == bandBottomFromTop)
        let canvasWidth = CGFloat(Self.geometry.edgeInset + Self.geometry.flankWidth + Self.geometry.notchGap)
        #expect(Self.placement.canvasSize == CGSize(width: canvasWidth, height: 32))
        #expect(sprite.minX == CGFloat(Self.geometry.edgeInset))
        #expect(sprite.size == CGSize(width: 16, height: 12))
    }

    @Test("an odd notch height still stands the pet on a whole point", arguments: [32.0, 33.0, 37.0, 38.5])
    func baselineIsAWholePoint(pillHeight: CGFloat) {
        let placement = PetPlacement(pet: Self.pet, pillHeight: pillHeight, metrics: .default)

        #expect(placement.baselineY == placement.baselineY.rounded())
    }

    /// Off the island means past the view's own edge, which clips it — the pet
    /// leaves through the pill's side rather than fading on top of an icon.
    @Test("off the island is wholly outside the view that draws the pet")
    func offstageIsOutsideTheCanvas() {
        let sprite = Self.placement.spriteFrame(at: Self.geometry.offstagePosition)

        #expect(sprite.maxX <= 0)
    }

    // MARK: - Animations

    @Test("discrete key times: one per keyframe, closing on one")
    func discreteKeyTimes() throws {
        let loop = try #require(Self.routine(.roaming).loop)
        let keyTimes = PetAnimation.discreteKeyTimes(for: loop).map(\.doubleValue)

        #expect(keyTimes.count == loop.keyframes.count + 1)
        #expect(keyTimes.first == 0)
        #expect(keyTimes.last == 1)
        #expect(keyTimes == keyTimes.sorted())
    }

    @Test("a loop plays as a frame track and two position tracks, a step at a time, for ever")
    func loopTracks() throws {
        let loop = try #require(Self.routine(.roaming).loop)
        let group = PetAnimation.repeating(
            loop,
            images: PetSpriteImages.images(for: Self.pet.sprites),
            placement: Self.placement,
            beginningAt: 10
        )
        let tracks = try #require(group.animations as? [CAKeyframeAnimation])

        #expect(group.repeatCount == .infinity)
        #expect(group.isRemovedOnCompletion == false)
        #expect(group.beginTime == 10)
        #expect(group.duration == loop.duration)
        #expect(tracks.map(\.keyPath) == ["contents", "position.x", "position.y"])
        #expect(tracks.allSatisfy { $0.calculationMode == .discrete })
        #expect(tracks.allSatisfy { $0.values?.count == loop.keyframes.count })
        #expect(
            (tracks[1].values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
                == loop.keyframes.map { Double(Self.placement.spriteFrame(at: $0.pose.position).minX) }
        )
    }

    @Test("an entrance plays once and is removed")
    func entranceIsPlayedOnce() {
        let group = PetAnimation.playing(
            Self.routine(.roaming).entrance,
            images: PetSpriteImages.images(for: Self.pet.sprites),
            placement: Self.placement,
            beginningAt: 0
        )

        #expect(group.isRemovedOnCompletion)
        #expect(group.repeatCount == 0)
    }

    /// The pet asks for its walk's step rate, and never lets a ProMotion
    /// display be held above the run's.
    @Test("the pet asks the display for fifteen frames a second, and allows no more than thirty")
    func frameRateIsLow() throws {
        let group = PetAnimation.repeating(
            try #require(Self.routine(.roaming).loop),
            images: PetSpriteImages.images(for: Self.pet.sprites),
            placement: Self.placement,
            beginningAt: 0
        )
        let ranges = [group.preferredFrameRateRange] + (group.animations ?? []).map(\.preferredFrameRateRange)

        #expect(ranges.allSatisfy { $0.preferred == 15 })
        #expect(ranges.allSatisfy { $0.maximum <= 30 })
    }

    // MARK: - The host view

    @Test("nothing is armed until the pet is in a window")
    func armsOnlyInAWindow() {
        let host = PetLayerHostView(frame: CGRect(origin: .zero, size: Self.placement.canvasSize))
        host.configure(Self.configuration(.roaming, startedAt: Self.uptime))

        #expect(host.sprite.animationKeys() == nil)
    }

    @Test("a routine just begun plays its entrance, then its loop")
    func freshRoutinePlaysTheEntranceFirst() throws {
        let (host, window) = Self.hostInWindow(Self.configuration(.roaming, startedAt: Self.uptime))
        defer { window.close() }
        let now = host.sprite.convertTime(CACurrentMediaTime(), from: nil)
        let entrance = Self.routine(.roaming).entrance

        let playing = try #require(host.sprite.animation(forKey: PetAnimation.entranceKey))
        let loop = try #require(host.sprite.animation(forKey: PetAnimation.loopKey))
        #expect(abs(playing.beginTime - now) < 0.5)
        #expect(abs(loop.beginTime - (now + entrance.duration)) < 0.5)
    }

    /// The island is rebuilt on every expand and collapse; a pet that had been
    /// roaming for minutes carries on from where its routine has got to.
    @Test("a routine already under way joins its loop where it stands")
    func runningRoutineResumesMidLoop() throws {
        let startedAt = Self.uptime - 300
        let (host, window) = Self.hostInWindow(Self.configuration(.roaming, startedAt: startedAt))
        defer { window.close() }
        let routine = Self.routine(.roaming)
        let loopDuration = try #require(routine.loop?.duration)
        let now = host.sprite.convertTime(CACurrentMediaTime(), from: nil)

        #expect(host.sprite.animation(forKey: PetAnimation.entranceKey) == nil)
        let loop = try #require(host.sprite.animation(forKey: PetAnimation.loopKey))
        let phase = now - loop.beginTime
        let expected = (300 - routine.entrance.duration).truncatingRemainder(dividingBy: loopDuration)
        #expect(phase >= 0)
        #expect(phase < loopDuration)
        #expect(abs(phase - expected) < 0.5)
    }

    @Test("updates that change nothing leave the running routine alone")
    func sameConfigurationKeepsTheRoutine() throws {
        let configuration = Self.configuration(.roaming, startedAt: Self.uptime - 60)
        let (host, window) = Self.hostInWindow(configuration)
        defer { window.close() }
        let before = try #require(host.sprite.animation(forKey: PetAnimation.loopKey)).beginTime

        host.configure(configuration)

        #expect(try #require(host.sprite.animation(forKey: PetAnimation.loopKey)).beginTime == before)
    }

    @Test("a new stage replaces the running routine")
    func newStageReplacesTheRoutine() throws {
        let (host, window) = Self.hostInWindow(Self.configuration(.roaming, startedAt: Self.uptime - 60))
        defer { window.close() }
        let roaming = try #require(host.sprite.animation(forKey: PetAnimation.loopKey)).duration

        host.configure(Self.configuration(.resting, startedAt: Self.uptime - 60))

        let resting = try #require(host.sprite.animation(forKey: PetAnimation.loopKey)).duration
        #expect(resting != roaming)
        #expect(resting == Self.routine(.resting).loop?.duration)
    }

    @Test("held still, the pet sits where its routine rests and nothing animates")
    func stillPetDoesNotAnimate() throws {
        let (host, window) = Self.hostInWindow(Self.configuration(.roaming, startedAt: Self.uptime, isStill: true))
        defer { window.close() }
        let still = try #require(Self.routine(.roaming).stillPose)

        #expect(host.sprite.animationKeys() == nil)
        #expect(host.sprite.isHidden == false)
        #expect(host.sprite.frame == Self.placement.spriteFrame(at: still.position))
        #expect(host.sprite.contents != nil)
    }

    @Test("held still with the flank full, the pet is not drawn at all")
    func stillPetAwayIsHidden() {
        let (host, window) = Self.hostInWindow(Self.configuration(.away, startedAt: Self.uptime, isStill: true))
        defer { window.close() }

        #expect(host.sprite.animationKeys() == nil)
        #expect(host.sprite.isHidden)
    }

    /// Once the pet has walked off, nothing is left running: the model value
    /// already holds it past the edge.
    @Test("a pet that has left keeps nothing running")
    func departedPetKeepsNothingRunning() {
        let (host, window) = Self.hostInWindow(Self.configuration(.away, startedAt: Self.uptime - 30))
        defer { window.close() }

        #expect(host.sprite.animationKeys() == nil)
        #expect(host.sprite.frame.maxX <= 0)
    }

    @Test("the pet takes no clicks: they belong to the pill beneath it")
    func petTakesNoClicks() {
        let host = PetLayerHostView(frame: CGRect(origin: .zero, size: Self.placement.canvasSize))

        #expect(host.hitTest(CGPoint(x: 20, y: 16)) == nil)
    }

    // MARK: - On the island

    @Test("the pet's stage draws the pet only when there is one")
    func stageDrawsThePet() {
        #expect(Self.rendersPet(PetFixtures.roamingPresentation()))
        #expect(Self.rendersPet(nil) == false)
    }

    /// The island draws the pet, carrying it between the compact and the open
    /// island; the pill only keeps its flank open for it.
    @Test("the compact pill itself draws no pet")
    func compactPillLeavesThePetToTheIsland() {
        let view = CompactActivityView(
            presentation: ActivityManager().compactPresentation,
            notchSize: CGSize(width: 185, height: 32),
            pet: .shiba
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 40)
        hostingView.layoutSubtreeIfNeeded()

        #expect(Self.containsView(named: "PetLayerHostView", in: hostingView) == false)
    }

    private static func rendersPet(_ pet: IslandPetPresentation?) -> Bool {
        let view = IslandPetStage(pet: pet, pillHeight: 32)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 40)
        hostingView.layoutSubtreeIfNeeded()
        return containsView(named: "PetLayerHostView", in: hostingView)
    }

    private static func containsView(named name: String, in view: NSView) -> Bool {
        if String(describing: type(of: view)).contains(name) {
            return true
        }
        return view.subviews.contains { containsView(named: name, in: $0) }
    }

    /// The performance contract forbids a clock kept alive for motion. The
    /// pet's only clock is Core Animation's, so no source that draws it may
    /// start one of its own.
    @Test(
        "nothing that draws the pet keeps a clock of its own",
        arguments: [
            "Sources/KerNotchUI/IslandPetView.swift",
            "Sources/KerNotchUI/PetLayerHostView.swift",
            "Sources/KerNotchUI/PetAnimation.swift",
            "Sources/KerNotchUI/PetSpriteImages.swift",
            "Sources/KerNotchUI/PetSettingsView.swift",
            "Sources/KerNotchCore/PetChoreographer.swift",
            "Sources/KerNotchCore/PetCues.swift",
            "Sources/KerNotchCore/PetLoops.swift",
            "Sources/KerNotchCore/PetNewsReactionScripts.swift",
            "Sources/KerNotchCore/PetReactionScripts.swift",
            "Sources/KerNotchCore/PetRoutine.swift",
            "Sources/KerNotchCore/PetRoutineTracker.swift",
        ]
    )
    func noClockOfItsOwn(path: String) throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(path),
            encoding: .utf8
        )

        for clock in ["Timer.", "Task.sleep", "DispatchSource", "CADisplayLink", "repeatForever", "TimelineView"] {
            #expect(source.contains(clock) == false, "\(path) starts a clock: \(clock)")
        }
    }
}

@Suite("Pet settings")
@MainActor
struct PetSettingsViewTests {
    private final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    @Test("the switch writes straight through to the preferences")
    func switchWritesThrough() {
        let box = Box(PetPreferences.default)
        let view = PetSettingsView(preferences: box.binding)

        view.isEnabled.wrappedValue = true
        #expect(box.value.isEnabled)

        view.isEnabled.wrappedValue = false
        #expect(box.value.isEnabled == false)
    }

    @Test("the picker writes straight through to the preferences")
    func pickerWritesThrough() {
        let box = Box(PetPreferences.default)
        let view = PetSettingsView(preferences: box.binding)

        view.species.wrappedValue = .penguin
        #expect(box.value.species == .penguin)
        #expect(box.value.isEnabled == false)

        view.species.wrappedValue = .dog
        #expect(box.value.species == .dog)
    }

    @Test("the pane shows the pet it would put on the island, switched on or not", arguments: [false, true])
    func paneShowsThePet(isEnabled: Bool) {
        let box = Box(PetPreferences(isEnabled: isEnabled))
        let hostingView = NSHostingView(rootView: PetSettingsView(preferences: box.binding))
        hostingView.frame = CGRect(x: 0, y: 0, width: 440, height: 300)
        hostingView.layoutSubtreeIfNeeded()

        #expect(Self.containsView(named: "PetLayerHostView", in: hostingView))
    }

    private static func containsView(named name: String, in view: NSView) -> Bool {
        if String(describing: type(of: view)).contains(name) {
            return true
        }
        return view.subviews.contains { containsView(named: name, in: $0) }
    }
}
