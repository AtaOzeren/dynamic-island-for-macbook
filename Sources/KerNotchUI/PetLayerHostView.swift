import AppKit
import KerNotchCore

/// Hosts the pet's layer, a layer for each effect beside it, and the routine's
/// animations on them.
///
/// The layers' model values always hold where the routine leaves them — the
/// pet where it settles, every effect out of sight — so whenever nothing is
/// animating them, the entrance finished, the view just placed or motion held
/// still, the pet is already in its place and nothing is left hanging in the
/// air beside it.
final class PetLayerHostView: NSView {
    struct Configuration: Equatable {
        let sprites: PetSpriteSheet
        let performance: PetPerformance
        let placement: PetPlacement
        let isStill: Bool
    }

    /// Which of the routine's two timelines an effect belongs to, and so
    /// whether it plays once or repeats.
    private enum Part {
        case entrance
        case loop
    }

    private struct EffectLayer {
        let layer: CALayer
        let track: PetEffectTrack
        let part: Part
    }

    let sprite = CALayer()
    /// Called when the pointer moves onto the pet, once each time it arrives
    /// there.
    var onTouch: () -> Void = {}

    private var configuration: Configuration?
    private var images: PetSpriteImageSet?
    private var effects: [EffectLayer] = []
    private var pointerIsOverPet = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        Self.prepare(sprite)
        layer?.addSublayer(sprite)
        trackPointer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// The pet is decoration: a click lands on the island beneath it.
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

    // MARK: - Petting

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackPointer()
    }

    /// Mouse tracking needs no hit testing, so the pet notices the pointer while
    /// clicks still fall through it onto the island. The area follows the
    /// visible rect by itself, so one is all the view ever needs.
    private func trackPointer() {
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        pointerIsOverPet = false
    }

    /// Whether `point`, in this view, is on the pet as it is drawn right now —
    /// mid-walk or mid-hop — rather than where its routine will leave it.
    func isOverPet(_ point: CGPoint) -> Bool {
        guard sprite.isHidden == false else { return false }
        return (sprite.presentation() ?? sprite).frame.contains(point)
    }

    private func pointerMoved(to point: CGPoint) {
        let isOver = isOverPet(point)
        defer { pointerIsOverPet = isOver }
        if isOver, pointerIsOverPet == false {
            onTouch()
        }
    }

    // MARK: - Animating

    private func restart() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        sprite.removeAnimation(forKey: PetAnimation.entranceKey)
        sprite.removeAnimation(forKey: PetAnimation.loopKey)
        for effect in effects {
            effect.layer.removeFromSuperlayer()
        }
        effects = []
        settle()
        addEffectLayers()
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
        sprite.frame = configuration.placement.spriteFrame(at: pose.position, lift: pose.lift)
        sprite.contents = images.image(for: pose.frame, facing: pose.facing)
    }

    /// A layer for every effect of the routine, out of sight until its track
    /// brings it in. None while the pet is held still: an effect is part of a
    /// reaction, and a reaction is motion.
    private func addEffectLayers() {
        guard let configuration, configuration.isStill == false else { return }
        let routine = configuration.performance.routine
        let images = PetSpriteImages.images(for: PetEffectArt.standard)
        let parts = [(Part.entrance, routine.entrance.effects), (.loop, routine.loop?.effects ?? [])]
        for (part, tracks) in parts {
            for track in tracks {
                let layer = CALayer()
                Self.prepare(layer)
                layer.isHidden = true
                layer.contents = images.image(for: track.effect, mirrored: track.isMirrored)
                layer.bounds = CGRect(
                    origin: .zero,
                    size: configuration.placement.effectSize(of: track.effect, in: .standard)
                )
                self.layer?.addSublayer(layer)
                effects.append(EffectLayer(layer: layer, track: track, part: part))
            }
        }
    }

    private func startIfNeeded() {
        guard let configuration, let images, configuration.isStill == false, window != nil else { return }
        let routine = configuration.performance.routine
        let placement = configuration.placement
        // Uptime and media time are one clock, so a duration read on the first
        // places the routine on the second exactly.
        let elapsed = configuration.performance.elapsed(at: ProcessInfo.processInfo.systemUptime)
        let now = CACurrentMediaTime()
        let entranceBegan = now - elapsed
        let entranceIsPlaying = elapsed < routine.entrance.duration

        if entranceIsPlaying, sprite.animation(forKey: PetAnimation.entranceKey) == nil {
            sprite.add(
                PetAnimation.playing(
                    routine.entrance, images: images, placement: placement, beginningAt: entranceBegan),
                forKey: PetAnimation.entranceKey
            )
        }
        let loopBegan = routine.loop.flatMap { loop -> CFTimeInterval? in
            guard loop.duration > 0 else { return nil }
            // Joined at its current phase rather than at its start, so a pet
            // whose island was open for a minute is where a minute of its
            // routine left it.
            let intoLoop = elapsed - routine.entrance.duration
            return intoLoop > 0 ? now - intoLoop.truncatingRemainder(dividingBy: loop.duration) : now - intoLoop
        }
        if let loop = routine.loop, let loopBegan, sprite.animation(forKey: PetAnimation.loopKey) == nil {
            sprite.add(
                PetAnimation.repeating(loop, images: images, placement: placement, beginningAt: loopBegan),
                forKey: PetAnimation.loopKey
            )
        }

        for effect in effects where effect.layer.animation(forKey: PetAnimation.effectKey) == nil {
            switch effect.part {
            case .entrance where entranceIsPlaying:
                effect.layer.add(
                    PetAnimation.playingEffect(
                        effect.track,
                        lasting: routine.entrance.duration,
                        placement: placement,
                        beginningAt: entranceBegan
                    ),
                    forKey: PetAnimation.effectKey
                )
            case .loop:
                guard let loop = routine.loop, let loopBegan else { continue }
                effect.layer.add(
                    PetAnimation.repeatingEffect(
                        effect.track,
                        lasting: loop.duration,
                        placement: placement,
                        beginningAt: loopBegan
                    ),
                    forKey: PetAnimation.effectKey
                )
            case .entrance:
                continue
            }
        }
    }

    /// Pixel art on a layer: shown at its own size on a Retina panel, where
    /// neither filter runs, and averaged rather than thinned out when a 1x
    /// display halves it. Only the routine moves it: an implicit animation on
    /// a changed model value would slide it between whole-point positions.
    private static func prepare(_ layer: CALayer) {
        layer.anchorPoint = .zero
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .linear
        layer.actions = [
            "contents": NSNull(),
            "position": NSNull(),
            "bounds": NSNull(),
            "hidden": NSNull(),
        ]
    }
}
