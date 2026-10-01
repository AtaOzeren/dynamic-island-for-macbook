import AppKit
import KerNotchCore

/// The pet's routine as Core Animation plays it, built as values so the timing
/// is testable without a screen.
///
/// Three tracks per timeline — which frame is shown, where it stands, and how
/// high it is off the floor — and two per effect beside it — where it is and
/// whether it shows — all discrete: each value holds until the next replaces
/// it, so between steps the render server has nothing to redraw, and KerNotch
/// itself does no work per frame at all.
enum PetAnimation {
    static let entranceKey = "kernotch.pet.entrance"
    static let loopKey = "kernotch.pet.loop"
    /// Each effect layer carries one animation: its track in the entrance or
    /// in the loop.
    static let effectKey = "kernotch.pet.effect"

    /// The walk's own step rate. The pet spends most of its routine sitting,
    /// and whatever the render server does for an attached animation between
    /// steps it does at this rate rather than at the panel's — on a ProMotion
    /// display, 15 Hz instead of 120. A run, at 30 steps a second, is then
    /// drawn two points at a time, which pixel art carries well. The maximum
    /// lets a display already refreshing faster for something else show every
    /// step.
    static let frameRateRange = CAFrameRateRange(minimum: 8, maximum: 30, preferred: 15)

    /// A timeline played once, from `beginTime`, then removed — the model
    /// values underneath already hold where it ends.
    static func playing(
        _ timeline: PetTimeline,
        images: PetSpriteImageSet,
        placement: PetPlacement,
        beginningAt beginTime: CFTimeInterval
    ) -> CAAnimationGroup {
        let group = steps(of: timeline, images: images, placement: placement)
        group.beginTime = beginTime
        group.isRemovedOnCompletion = true
        return group
    }

    /// A timeline repeated for as long as the layer shows it.
    ///
    /// Kept attached rather than left to be removed, as the equaliser's
    /// strokes are: an animation Core Animation drops while the view stays in
    /// its window is only re-armed by the next SwiftUI update, and until then
    /// the pet would stand frozen where its routine rests.
    static func repeating(
        _ timeline: PetTimeline,
        images: PetSpriteImageSet,
        placement: PetPlacement,
        beginningAt beginTime: CFTimeInterval
    ) -> CAAnimationGroup {
        let group = steps(of: timeline, images: images, placement: placement)
        group.beginTime = beginTime
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        return group
    }

    /// One effect of a timeline played once, alongside the pet.
    static func playingEffect(
        _ track: PetEffectTrack,
        lasting duration: TimeInterval,
        placement: PetPlacement,
        beginningAt beginTime: CFTimeInterval
    ) -> CAAnimationGroup {
        let group = effectSteps(of: track, lasting: duration, placement: placement)
        group.beginTime = beginTime
        group.isRemovedOnCompletion = true
        return group
    }

    /// One effect of a loop, repeated with it.
    static func repeatingEffect(
        _ track: PetEffectTrack,
        lasting duration: TimeInterval,
        placement: PetPlacement,
        beginningAt beginTime: CFTimeInterval
    ) -> CAAnimationGroup {
        let group = effectSteps(of: track, lasting: duration, placement: placement)
        group.beginTime = beginTime
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        return group
    }

    /// Discrete key times: one per keyframe, then the closing `1` Core
    /// Animation requires in discrete mode, where each value holds until the
    /// next key time.
    static func discreteKeyTimes(for timeline: PetTimeline) -> [NSNumber] {
        discreteKeyTimes(for: timeline.keyframes.map(\.time), lasting: timeline.duration)
    }

    /// The keyframes of an effect that fall inside a timeline `duration` long.
    /// One at the very end would be shown for no time at all, and leaving it
    /// out keeps a loop's last point showing up to the moment it wraps.
    static func keyframes(of track: PetEffectTrack, lasting duration: TimeInterval) -> [PetEffectKeyframe] {
        let inside = track.keyframes.filter { $0.time < duration }
        return inside.isEmpty ? Array(track.keyframes.prefix(1)) : inside
    }

    private static func discreteKeyTimes(for times: [TimeInterval], lasting duration: TimeInterval) -> [NSNumber] {
        guard duration > 0 else { return [0, 1] }
        return times.map { NSNumber(value: $0 / duration) } + [1]
    }

    private static func steps(
        of timeline: PetTimeline,
        images: PetSpriteImageSet,
        placement: PetPlacement
    ) -> CAAnimationGroup {
        let keyTimes = discreteKeyTimes(for: timeline)
        let frames = timeline.keyframes.map { placement.spriteFrame(at: $0.pose.position, lift: $0.pose.lift) }

        let contents = CAKeyframeAnimation(keyPath: "contents")
        contents.values = timeline.keyframes.map { keyframe -> Any in
            images.image(for: keyframe.pose.frame, facing: keyframe.pose.facing) ?? NSNull()
        }
        let across = CAKeyframeAnimation(keyPath: "position.x")
        across.values = frames.map(\.minX)
        let rise = CAKeyframeAnimation(keyPath: "position.y")
        rise.values = frames.map(\.minY)

        return group(of: [contents, across, rise], keyTimes: keyTimes, duration: timeline.duration)
    }

    /// Where the effect is and whether it shows. Out of sight it stays where it
    /// last was, so appearing never slides it in from somewhere else.
    private static func effectSteps(
        of track: PetEffectTrack,
        lasting duration: TimeInterval,
        placement: PetPlacement
    ) -> CAAnimationGroup {
        let keyframes = keyframes(of: track, lasting: duration)
        var lastOrigin = keyframes.lazy.compactMap(\.point).first.map(placement.effectOrigin(at:)) ?? .zero
        let origins = keyframes.map { keyframe -> CGPoint in
            if let point = keyframe.point {
                lastOrigin = placement.effectOrigin(at: point)
            }
            return lastOrigin
        }

        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = origins.map { NSValue(point: $0) }
        let hidden = CAKeyframeAnimation(keyPath: "hidden")
        hidden.values = keyframes.map { NSNumber(value: $0.point == nil) }

        return group(
            of: [position, hidden],
            keyTimes: discreteKeyTimes(for: keyframes.map(\.time), lasting: duration),
            duration: duration
        )
    }

    private static func group(
        of tracks: [CAKeyframeAnimation],
        keyTimes: [NSNumber],
        duration: TimeInterval
    ) -> CAAnimationGroup {
        for track in tracks {
            track.keyTimes = keyTimes
            track.calculationMode = .discrete
            track.duration = duration
            track.preferredFrameRateRange = frameRateRange
        }
        let group = CAAnimationGroup()
        group.animations = tracks
        group.duration = duration
        group.preferredFrameRateRange = frameRateRange
        return group
    }
}
