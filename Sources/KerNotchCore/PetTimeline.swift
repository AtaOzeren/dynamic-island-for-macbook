import Foundation

/// Where the pet is, and how it is drawn, at one moment.
public struct PetPose: Equatable, Sendable {
    /// Points from the leading flank's outer edge to the pet's left edge.
    /// Negative once the pet has walked off the island.
    public var position: Int
    public var facing: PetFacing
    public var frame: PetFrame

    public init(position: Int, facing: PetFacing, frame: PetFrame) {
        self.position = position
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

/// A stretch of the pet's life: the poses it takes, and when.
///
/// Discrete by design. Each pose holds until the next keyframe replaces it,
/// which is how pixel art moves — a step at a time — and what lets Core
/// Animation leave the pet untouched between steps.
public struct PetTimeline: Equatable, Sendable {
    /// Never empty. The first keyframe is at zero and times never decrease.
    public let keyframes: [PetKeyframe]
    /// At least the last keyframe's time: the last pose holds until then.
    public let duration: TimeInterval

    /// Built by `PetChoreographer`, which is what keeps the keyframes ordered
    /// and starting at zero.
    init(keyframes: [PetKeyframe], duration: TimeInterval) {
        precondition(keyframes.isEmpty == false, "a timeline holds at least one pose")
        self.keyframes = keyframes
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
