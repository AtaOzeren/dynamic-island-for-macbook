import AppKit
import KerNotchCore
import SwiftUI

/// The pet as the island draws it: which pet, and the routine it is in the
/// middle of.
public struct IslandPetPresentation: Equatable, Sendable {
    public let pet: IslandPet
    public let performance: PetPerformance

    public init(pet: IslandPet, performance: PetPerformance) {
        self.pet = pet
        self.performance = performance
    }
}

/// Where the pet's stage sits inside the view that draws it, in the layer
/// coordinates Core Animation places the pet by: points, origin bottom left.
struct PetPlacement: Equatable {
    /// From the pill's outer edge to the flank's notch-side end, the pill's
    /// full height. The margin is included so the pet can walk out through it:
    /// the view clips at the pill's edge, which is where the pet disappears.
    let canvasSize: CGSize
    let spriteSize: CGSize
    /// Where stage position zero lands: the pill's margin in from its edge.
    let stageOriginX: CGFloat
    /// The sprite's bottom edge, measured up from the canvas bottom.
    let baselineY: CGFloat

    init(pet: IslandPet, pillHeight: CGFloat, metrics: CompactPillMetrics) {
        let geometry = pet.stageGeometry(on: metrics)
        spriteSize = CGSize(width: pet.sprites.pointWidth, height: pet.sprites.pointHeight)
        stageOriginX = CGFloat(geometry.edgeInset)
        canvasSize = CGSize(width: CGFloat(geometry.edgeInset + geometry.flankWidth), height: pillHeight)
        // Level with the bottom of the icons' band, so the pet's paws and the
        // glyphs beside it stand on one line. Whole points, so the art's pixels
        // land on device pixels.
        let slotTop = (pillHeight - metrics.slotHeight) / 2
        let bandBottom = slotTop + metrics.iconBandTopInset + metrics.symbolSize
        baselineY = (pillHeight - bandBottom).rounded(.down)
    }

    func spriteFrame(at position: Int) -> CGRect {
        CGRect(origin: CGPoint(x: stageOriginX + CGFloat(position), y: baselineY), size: spriteSize)
    }
}

/// The pet's corner of the compact pill, drawn from the pill's outer edge so
/// the pet can walk out through the margin — the view clips it there, which is
/// where it leaves. Switching the pet on or off fades it on the island's own
/// content motion, with the pill widening or narrowing around it.
///
/// The hover peek scales the island by a few percent; the pet is scaled back
/// by the same amount, so it moves with the peek but stays one image pixel to
/// one device pixel instead of being resampled into a slightly lumpy dog.
struct CompactPetStage: View {
    @Environment(\.islandContentMotion) private var islandMotion
    @Environment(\.islandHoverScale) private var islandHoverScale

    let pet: IslandPetPresentation?
    let pillHeight: CGFloat
    let metrics: CompactPillMetrics

    var body: some View {
        ZStack(alignment: .leading) {
            if let pet {
                IslandPetView(
                    presentation: pet,
                    placement: PetPlacement(pet: pet.pet, pillHeight: pillHeight, metrics: metrics)
                )
                .scaleEffect(islandPeekCounterScale(for: islandHoverScale))
                .transition(.opacity)
            }
        }
        .animation(islandMotion.content, value: pet?.pet)
    }
}

/// The pet on the compact pill's leading flank.
///
/// Played by Core Animation from the routine the presenter chose, with this
/// body evaluated only when the routine changes — the arrangement the
/// equaliser and the attention glow use, for the reason measured there: a
/// SwiftUI animation re-evaluates the island on every frame.
///
/// With motion reduced — by the system, or by KerNotch's own Motion choice —
/// or while the CPU watchdog holds the island still, the pet sits where its
/// routine rests and nothing moves.
struct IslandPetView: View {
    @Environment(\.prefersReducedIslandMotion) private var reduceMotion
    @Environment(\.islandMotionSuspended) private var islandMotionSuspended

    let presentation: IslandPetPresentation
    let placement: PetPlacement

    var body: some View {
        PetLayerView(
            configuration: PetLayerHostView.Configuration(
                sprites: presentation.pet.sprites,
                performance: presentation.performance,
                placement: placement,
                isStill: reduceMotion || islandMotionSuspended
            )
        )
        .frame(width: placement.canvasSize.width, height: placement.canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PetLayerView: NSViewRepresentable {
    let configuration: PetLayerHostView.Configuration

    func makeNSView(context: Context) -> PetLayerHostView {
        let view = PetLayerHostView(frame: CGRect(origin: .zero, size: configuration.placement.canvasSize))
        view.configure(configuration)
        return view
    }

    func updateNSView(_ view: PetLayerHostView, context: Context) {
        view.configure(configuration)
    }
}

/// Hosts the pet's one layer, and the routine's animations on it.
///
/// The layer's model values always hold where the routine leaves the pet, so
/// whenever nothing is animating it — the entrance finished, the view just
/// placed, motion held still — the pet is already in its place.
final class PetLayerHostView: NSView {
    struct Configuration: Equatable {
        let sprites: PetSpriteSheet
        let performance: PetPerformance
        let placement: PetPlacement
        let isStill: Bool
    }

    let sprite = CALayer()
    private var configuration: Configuration?
    private var images: PetSpriteImageSet?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true

        sprite.anchorPoint = .zero
        sprite.contentsGravity = .resize
        // On a Retina panel the art is shown pixel for pixel and neither filter
        // runs. On a 1x display it is halved, where averaging keeps the dog
        // whole rather than dropping every other pixel of it.
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .linear
        // Only the routine moves the pet: an implicit animation on a changed
        // model value would slide it between whole-point positions.
        sprite.actions = [
            "contents": NSNull(),
            "position": NSNull(),
            "bounds": NSNull(),
            "hidden": NSNull(),
        ]
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// The pet is decoration: a click lands on the pill beneath it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// Starting over only when the routine or its placement changed. Every
    /// other update re-arms whatever Core Animation dropped, which is a no-op
    /// while the animations run.
    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            startIfNeeded()
            return
        }
        if self.configuration?.sprites != configuration.sprites || images == nil {
            images = PetSpriteImages.images(for: configuration.sprites)
        }
        self.configuration = configuration
        restart()
    }

    /// Core Animation drops a layer's animations when it leaves the render
    /// tree, so the routine is resumed — at its elapsed point — whenever the
    /// view lands in a window again.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startIfNeeded()
    }

    private func restart() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        sprite.removeAnimation(forKey: PetAnimation.entranceKey)
        sprite.removeAnimation(forKey: PetAnimation.loopKey)
        settle()
        startIfNeeded()
    }

    /// Puts the model values where the routine leaves the pet, or hides it
    /// when that is off the island and nothing may move.
    private func settle() {
        guard let configuration, let images else { return }
        let routine = configuration.performance.routine
        guard let pose = configuration.isStill ? routine.stillPose : routine.settledPose else {
            sprite.isHidden = true
            return
        }
        sprite.isHidden = false
        sprite.frame = configuration.placement.spriteFrame(at: pose.position)
        sprite.contents = images.image(for: pose.frame, facing: pose.facing)
    }

    private func startIfNeeded() {
        guard let configuration, let images, configuration.isStill == false, window != nil else { return }
        let routine = configuration.performance.routine
        // Uptime and media time are one clock, so a duration read on the first
        // places the routine on the second exactly.
        let elapsed = configuration.performance.elapsed(at: ProcessInfo.processInfo.systemUptime)
        let now = CACurrentMediaTime()

        if elapsed < routine.entrance.duration, sprite.animation(forKey: PetAnimation.entranceKey) == nil {
            sprite.add(
                PetAnimation.playing(
                    routine.entrance,
                    images: images,
                    placement: configuration.placement,
                    beginningAt: now - elapsed
                ),
                forKey: PetAnimation.entranceKey
            )
        }

        guard
            let loop = routine.loop,
            loop.duration > 0,
            sprite.animation(forKey: PetAnimation.loopKey) == nil
        else {
            return
        }
        // Joined at its current phase rather than at its start, so a pet whose
        // island was open for a minute is where a minute of its routine left it.
        let intoLoop = elapsed - routine.entrance.duration
        let loopBegan = intoLoop > 0 ? now - intoLoop.truncatingRemainder(dividingBy: loop.duration) : now - intoLoop
        sprite.add(
            PetAnimation.repeating(
                loop,
                images: images,
                placement: configuration.placement,
                beginningAt: loopBegan
            ),
            forKey: PetAnimation.loopKey
        )
    }
}
