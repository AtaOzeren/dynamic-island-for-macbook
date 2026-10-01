import Foundation

/// Where the pet is, and how it is drawn, at one moment.
public struct PetPose: Equatable, Sendable {
    /// Points from the stage's outer edge to the pet's left edge. Negative once
    /// the pet has walked off the island.
    public var position: Int
    /// Points above the floor: zero except in the air.
    public var lift: Int
    public var facing: PetFacing
    public var frame: PetFrame

    public init(position: Int, lift: Int = 0, facing: PetFacing, frame: PetFrame) {
        self.position = position
        self.lift = lift
        self.facing = facing
        self.frame = frame
    }
}

/// A pose, and the moment it begins.
public struct PetKeyframe: Equatable, Sendable {
    /// Seconds from the start of the timeline.
    public let time: TimeInterval
    public let pose: PetPose

    public init(time: TimeInterval, pose: PetPose) {
        self.time = time
        self.pose = pose
    }
}

/// Where an effect is drawn: its bottom-left corner.
public struct PetPoint: Equatable, Sendable {
    /// Points across the stage from its outer edge, as a pose's position is.
    public var position: Int
    /// Points up from the floor the pet stands on.
    public var height: Int

    public init(position: Int, height: Int) {
        self.position = position
        self.height = height
    }
}

/// Where an effect is at one moment, `nil` while it is not drawn.
public struct PetEffectKeyframe: Equatable, Sendable {
    public let time: TimeInterval
    public let point: PetPoint?

    public init(time: TimeInterval, point: PetPoint?) {
        self.time = time
        self.point = point
    }
}

/// One effect's life in a timeline: out of sight until it appears, moving a
/// step at a time, out of sight again once it is done.
public struct PetEffectTrack: Equatable, Sendable {
    public let effect: PetEffect
    /// Drawn mirrored: only for effects that point somewhere, such as a bark's
    /// lines when the pet faces left.
    public let isMirrored: Bool
    /// The first at zero; times never decrease.
    public let keyframes: [PetEffectKeyframe]

    public init(effect: PetEffect, isMirrored: Bool, keyframes: [PetEffectKeyframe]) {
        self.effect = effect
        self.isMirrored = isMirrored
        self.keyframes = keyframes
    }

    /// Where the effect is drawn at `time`, or `nil` while it is not.
    public func point(at time: TimeInterval) -> PetPoint? {
        guard let keyframe = keyframes.last(where: { $0.time <= time }) else {
            return keyframes.first?.point
        }
        return keyframe.point
    }
}

/// A stretch of the pet's life: the poses it takes, the effects around it, and
/// when.
///
/// Discrete by design. Each pose holds until the next keyframe replaces it,
/// which is how pixel art moves — a step at a time — and what lets Core
/// Animation leave the pet untouched between steps.
public struct PetTimeline: Equatable, Sendable {
    /// Never empty. The first keyframe is at zero and times never decrease.
    public let keyframes: [PetKeyframe]
    /// Everything drawn beside the pet, each on its own track.
    public let effects: [PetEffectTrack]
    /// At least the last keyframe's time: the last pose holds until then.
    public let duration: TimeInterval

    /// Built by `PetChoreographer`, which is what keeps the keyframes ordered
    /// and starting at zero.
    init(keyframes: [PetKeyframe], effects: [PetEffectTrack] = [], duration: TimeInterval) {
        precondition(keyframes.isEmpty == false, "a timeline holds at least one pose")
        self.keyframes = keyframes
        self.effects = effects
        self.duration = max(duration, keyframes[keyframes.count - 1].time)
    }

    public var firstPose: PetPose { keyframes[0].pose }

    public var lastPose: PetPose { keyframes[keyframes.count - 1].pose }

    /// The pose held at `time`, clamped to the timeline's own span.
    public func pose(at time: TimeInterval) -> PetPose {
        var lower = 0
        var upper = keyframes.count - 1
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            if keyframes[middle].time <= time {
                lower = middle
            } else {
                upper = middle - 1
            }
        }
        return keyframes[lower].pose
    }
}

extension PetTimeline {
    /// The stretch from `start` to `end` as a timeline of its own, beginning in
    /// the pose held at `start`: what the pet still has to do of a reaction it
    /// is in the middle of.
    func cut(from start: TimeInterval, to end: TimeInterval) -> PetTimeline {
        var poses = [PetKeyframe(time: 0, pose: pose(at: start))]
        guard end > start else {
            return PetTimeline(keyframes: poses, duration: 0)
        }
        for keyframe in keyframes where keyframe.time > start && keyframe.time <= end {
            poses.append(PetKeyframe(time: keyframe.time - start, pose: keyframe.pose))
        }
        let tracks: [PetEffectTrack] = effects.compactMap { track in
            var points = [PetEffectKeyframe(time: 0, point: track.point(at: start))]
            for keyframe in track.keyframes where keyframe.time > start && keyframe.time < end {
                points.append(PetEffectKeyframe(time: keyframe.time - start, point: keyframe.point))
            }
            points.append(PetEffectKeyframe(time: end - start, point: nil))
            guard points.contains(where: { $0.point != nil }) else { return nil }
            return PetEffectTrack(effect: track.effect, isMirrored: track.isMirrored, keyframes: points)
        }
        return PetTimeline(keyframes: poses, effects: tracks, duration: end - start)
    }
}
