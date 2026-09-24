import Foundation

/// How fast the pet crosses the flank, and how fast its legs go.
struct PetGait: Equatable, Sendable {
    /// Seconds per point travelled.
    let stepInterval: TimeInterval
    /// Seconds each leg frame holds.
    let strideInterval: TimeInterval

    /// An amble: 15 points a second, legs at 7.5 frames a second. Slow enough
    /// that crossing the whole flank takes a couple of seconds, which reads as
    /// a stroll rather than as something happening on the island.
    static let walk = PetGait(stepInterval: 1.0 / 15, strideInterval: 2.0 / 15)

    /// Twice the pace, for getting out of an icon's way or off the island,
    /// where the pet crosses the space an arriving icon is growing into.
    static let run = PetGait(stepInterval: 1.0 / 30, strideInterval: 1.0 / 15)

    /// Steps taken on each leg frame.
    var stepsPerStride: Int {
        max(Int((strideInterval / stepInterval).rounded()), 1)
    }
}

/// Something the pet does while it sits.
enum PetGesture: Equatable, Sendable {
    case blink
    case pant
    case wag

    /// The frames it passes through, each with how long it holds. The sit it
    /// happens in restores the resting frame afterwards.
    var sequence: [(frame: PetFrame, duration: TimeInterval)] {
        switch self {
        case .blink:
            [(.sitBlink, 0.15)]
        case .pant:
            [(.sitPant, 0.25), (.sit, 0.2), (.sitPant, 0.25), (.sit, 0.2), (.sitPant, 0.25)]
        case .wag:
            [(.sitWag, 0.15), (.sit, 0.15), (.sitWag, 0.15), (.sit, 0.15), (.sitWag, 0.15)]
        }
    }
}

/// A gesture, and how far into a sit it begins.
struct PetBeat: Equatable, Sendable {
    let offset: TimeInterval
    let gesture: PetGesture
}

/// Writes a timeline one action at a time — walk here, sit there — so a routine
/// reads as a script rather than as a table of keyframes.
struct PetChoreographer {
    /// How long a turn on the spot takes, so the pet is seen facing the new way
    /// before it sets off.
    static let turnDuration: TimeInterval = 0.15
    /// How long the half-way pose between standing and sitting holds.
    static let crouchDuration: TimeInterval = 0.12

    /// The leg frames of one stride, reaching and passing on each side.
    static let strideCycle: [PetFrame] = [.strideA, .stand, .strideB, .stand]

    private(set) var time: TimeInterval = 0
    private(set) var pose: PetPose
    private var keyframes: [PetKeyframe]

    init(startingAt pose: PetPose) {
        self.pose = pose
        keyframes = [PetKeyframe(time: 0, pose: pose)]
    }

    mutating func hold(_ seconds: TimeInterval) {
        time += max(seconds, 0)
    }

    mutating func show(_ frame: PetFrame) {
        guard frame != pose.frame else { return }
        pose.frame = frame
        mark()
    }

    /// Turns on the spot, standing up first: a pet does not spin around on its
    /// haunches, and a leg caught mid-stride or an eye mid-blink would be seen
    /// mirrored for the whole turn.
    mutating func turn(_ facing: PetFacing) {
        guard facing != pose.facing else { return }
        standUp()
        show(.stand)
        pose.facing = facing
        mark()
        hold(Self.turnDuration)
    }

    mutating func standUp() {
        guard pose.frame.isSitting || pose.frame == .crouch else { return }
        if pose.frame != .crouch {
            show(.crouch)
            hold(Self.crouchDuration)
        }
        show(.stand)
    }

    mutating func sitDown() {
        guard pose.frame.isSitting == false else { return }
        if pose.frame != .crouch {
            show(.crouch)
            hold(Self.crouchDuration)
        }
        show(.sit)
    }

    /// Stands, turns towards `position` if it has to, and goes there a point
    /// at a time. Arrives standing.
    mutating func travel(to position: Int, gait: PetGait) {
        guard position != pose.position else { return }
        standUp()
        turn(position > pose.position ? .right : .left)

        let direction = position > pose.position ? 1 : -1
        var step = 0
        while pose.position != position {
            time += gait.stepInterval
            pose.position += direction
            pose.frame = Self.strideCycle[(step / gait.stepsPerStride) % Self.strideCycle.count]
            mark()
            step += 1
        }
        hold(gait.stepInterval)
        show(.stand)
    }

    mutating func walk(to position: Int) {
        travel(to: position, gait: .walk)
    }

    /// Sits for `seconds`, making each gesture at its offset into the sit. A
    /// gesture that runs past the end lengthens the sit rather than being cut.
    mutating func sit(for seconds: TimeInterval, beats: [PetBeat] = []) {
        sitDown()
        let start = time
        for beat in beats.sorted(by: { $0.offset < $1.offset }) {
            time = max(time, start + beat.offset)
            for (frame, duration) in beat.gesture.sequence {
                show(frame)
                hold(duration)
            }
            show(.sit)
        }
        time = max(time, start + seconds)
    }

    /// Everything written so far, played once.
    func timeline() -> PetTimeline {
        PetTimeline(keyframes: keyframes, duration: time)
    }

    /// Everything written so far, as a loop that ends where it began.
    ///
    /// A keyframe that lands exactly at the end and matches the opening pose
    /// is the loop closing, and is dropped: the opening keyframe already says
    /// it, and keeping both would give one pose two places in the loop.
    func loop() -> PetTimeline {
        var closed = keyframes
        if closed.count > 1, let last = closed.last, last.time >= time, last.pose == closed[0].pose {
            closed.removeLast()
        }
        return PetTimeline(keyframes: closed, duration: time)
    }

    /// Records the pose as of now. A second change at the same instant replaces
    /// the first — nobody sees a pose held for no time.
    private mutating func mark() {
        let keyframe = PetKeyframe(time: time, pose: pose)
        if let last = keyframes.last, last.time == time {
            keyframes[keyframes.count - 1] = keyframe
        } else {
            keyframes.append(keyframe)
        }
    }
}
