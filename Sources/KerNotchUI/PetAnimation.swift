import AppKit
import KerNotchCore

/// The pet's routine as Core Animation plays it, built as values so the timing
/// is testable without a screen.
///
/// Two tracks per timeline — which frame is shown and where it stands — both
/// discrete: each value holds until the next replaces it, so between steps the
/// render server has nothing to redraw, and KerNotch itself does no work per
/// frame at all.
enum PetAnimation {
    static let entranceKey = "kernotch.pet.entrance"
    static let loopKey = "kernotch.pet.loop"

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

    /// Discrete key times: one per keyframe, then the closing `1` Core
    /// Animation requires in discrete mode, where each value holds until the
    /// next key time.
    static func discreteKeyTimes(for timeline: PetTimeline) -> [NSNumber] {
        guard timeline.duration > 0 else { return [0, 1] }
        return timeline.keyframes.map { NSNumber(value: $0.time / timeline.duration) } + [1]
    }

    private static func steps(
        of timeline: PetTimeline,
        images: PetSpriteImageSet,
        placement: PetPlacement
    ) -> CAAnimationGroup {
        let keyTimes = discreteKeyTimes(for: timeline)

        let contents = CAKeyframeAnimation(keyPath: "contents")
        contents.values = timeline.keyframes.map { keyframe -> Any in
            images.image(for: keyframe.pose.frame, facing: keyframe.pose.facing) ?? NSNull()
        }
        let position = CAKeyframeAnimation(keyPath: "position.x")
        position.values = timeline.keyframes.map { placement.spriteFrame(at: $0.pose.position).minX }

        for track in [contents, position] {
            track.keyTimes = keyTimes
            track.calculationMode = .discrete
            track.duration = timeline.duration
            track.preferredFrameRateRange = frameRateRange
        }

        let group = CAAnimationGroup()
        group.animations = [contents, position]
        group.duration = timeline.duration
        group.preferredFrameRateRange = frameRateRange
        return group
    }
}
