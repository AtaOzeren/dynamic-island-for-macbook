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
    /// From the island's outer edge to the notch, the pill's full height. The
    /// margin is included so the pet can walk out through it: the view clips
    /// at the island's edge, which is where the pet disappears.
    let canvasSize: CGSize
    let spriteSize: CGSize
    /// Where stage position zero lands: the pill's margin in from its edge.
    let stageOriginX: CGFloat
    /// The sprite's bottom edge, measured up from the canvas bottom.
    let baselineY: CGFloat
    /// Image pixels to a point, which effects are drawn at too.
    let pixelsPerPoint: CGFloat

    init(sprites: PetSpriteSheet, geometry: PetStageGeometry, pillHeight: CGFloat, metrics: CompactPillMetrics) {
        spriteSize = CGSize(width: sprites.pointWidth, height: sprites.pointHeight)
        pixelsPerPoint = CGFloat(sprites.pixelsPerPoint)
        stageOriginX = CGFloat(geometry.edgeInset)
        canvasSize = CGSize(width: CGFloat(geometry.canvasWidth), height: pillHeight)
        // Level with the bottom of the icons' band, so the pet's paws and the
        // glyphs beside it stand on one line. Whole points, so the art's pixels
        // land on device pixels.
        let slotTop = (pillHeight - metrics.slotHeight) / 2
        let bandBottom = slotTop + metrics.iconBandTopInset + metrics.symbolSize
        baselineY = (pillHeight - bandBottom).rounded(.down)
    }

    /// The pet on the compact pill's leading flank.
    init(pet: IslandPet, pillHeight: CGFloat, metrics: CompactPillMetrics) {
        self.init(
            sprites: pet.sprites, geometry: pet.stageGeometry(on: metrics), pillHeight: pillHeight, metrics: metrics)
    }

    func spriteFrame(at position: Int, lift: Int = 0) -> CGRect {
        CGRect(
            origin: CGPoint(x: stageOriginX + CGFloat(position), y: baselineY + CGFloat(lift)),
            size: spriteSize
        )
    }

    /// Where an effect's bottom-left corner goes.
    func effectOrigin(at point: PetPoint) -> CGPoint {
        CGPoint(x: stageOriginX + CGFloat(point.position), y: baselineY + CGFloat(point.height))
    }

    /// An effect's size on screen, at the pet's own density.
    func effectSize(of effect: PetEffect, in art: PetEffectArt) -> CGSize {
        let density = CGFloat(art.pixelsPerPoint)
        return CGSize(
            width: CGFloat(art.pixelWidth(of: effect)) / density,
            height: CGFloat(art.pixelHeight(of: effect)) / density
        )
    }
}

/// The pet's corner of the island: the compact pill's leading flank, or the
/// open island's strip beside the notch.
///
/// Drawn from the island's outer edge, so the pet walks out through the margin
/// — the island's mask clips it there, which is where it leaves — and laid in
/// the island's own coordinates, so when the island opens or closes the pet
/// rides its edge on the same spring. Switching the pet on or off fades it on
/// the island's own content motion.
///
/// The hover peek scales the island by a few percent; the pet is scaled back
/// by the same amount, so it moves with the peek but stays one image pixel to
/// one device pixel instead of being resampled into a slightly lumpy dog.
public struct IslandPetStage: View {
    @Environment(\.islandContentMotion) private var islandMotion
    @Environment(\.islandHoverScale) private var islandHoverScale

    private let pet: IslandPetPresentation?
    private let pillHeight: CGFloat
    private let metrics: CompactPillMetrics
    private let onTouch: () -> Void

    /// `onTouch` is called when the pointer moves onto the pet.
    public init(
        pet: IslandPetPresentation?,
        pillHeight: CGFloat,
        metrics: CompactPillMetrics = .default,
        onTouch: @escaping () -> Void = {}
    ) {
        self.pet = pet
        self.pillHeight = pillHeight
        self.metrics = metrics
        self.onTouch = onTouch
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if let pet {
                IslandPetView(
                    presentation: pet,
                    placement: PetPlacement(
                        sprites: pet.pet.sprites,
                        geometry: pet.performance.routine.geometry,
                        pillHeight: pillHeight,
                        metrics: metrics
                    ),
                    onTouch: onTouch
                )
                .scaleEffect(islandPeekCounterScale(for: islandHoverScale))
                .transition(.opacity)
            }
        }
        .animation(islandMotion.content, value: pet?.pet)
    }
}

/// The pet on the island.
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
    var onTouch: () -> Void = {}

    var body: some View {
        PetLayerView(
            configuration: PetLayerHostView.Configuration(
                sprites: presentation.pet.sprites,
                performance: presentation.performance,
                placement: placement,
                isStill: reduceMotion || islandMotionSuspended
            ),
            onTouch: onTouch
        )
        .frame(width: placement.canvasSize.width, height: placement.canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PetLayerView: NSViewRepresentable {
    let configuration: PetLayerHostView.Configuration
    let onTouch: () -> Void

    func makeNSView(context: Context) -> PetLayerHostView {
        let view = PetLayerHostView(frame: CGRect(origin: .zero, size: configuration.placement.canvasSize))
        view.onTouch = onTouch
        view.configure(configuration)
        return view
    }

    func updateNSView(_ view: PetLayerHostView, context: Context) {
        view.onTouch = onTouch
        view.configure(configuration)
    }
}
