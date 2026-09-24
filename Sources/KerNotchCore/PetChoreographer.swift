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
///
/// Every action starts from whatever pose the pet is in. Getting to its feet,
/// down on its haunches or onto the floor goes through the moves a dog makes —
/// a pet caught in the air lands first, a lying one pushes up through the
/// crouch — which is what lets a new routine begin mid-way through any other.
struct PetChoreographer {
    /// How long a turn on the spot takes, so the pet is seen facing the new way
    /// before it sets off.
    static let turnDuration: TimeInterval = 0.15
    /// How long the half-way pose between standing and sitting holds.
    static let crouchDuration: TimeInterval = 0.12
    /// One step of anything that moves smoothly — a hop's arc, an effect
    /// drifting — at the rate the pet is drawn.
    static let frameInterval: TimeInterval = 1.0 / 15
    /// How far the pet comes down in a frame of falling, as it does at the
    /// end of a hop.
    static let landingStep = 2

    /// The leg frames of one stride, reaching and passing on each side.
    static let strideCycle: [PetFrame] = [.strideA, .stand, .strideB, .stand]

    /// The sprite's width in points, which is how far an effect beside the pet
    /// has to be mirrored when the pet turns round.
    let spriteWidth: Int

    private(set) var time: TimeInterval = 0
    private(set) var pose: PetPose
    private var keyframes: [PetKeyframe]
    private var effects: [PetEffectTrack] = []

    init(startingAt pose: PetPose, spriteWidth: Int) {
        self.pose = pose
        self.spriteWidth = spriteWidth
        keyframes = [PetKeyframe(time: 0, pose: pose)]
    }

    /// Carries on from the end of `timeline`, which is kept as the start of
    /// what gets written.
    init(continuing timeline: PetTimeline, spriteWidth: Int) {
        self.spriteWidth = spriteWidth
        keyframes = timeline.keyframes
        effects = timeline.effects
        time = timeline.duration
        pose = timeline.lastPose
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

    /// Looks the other way without getting up: a sitting pet turns its head,
    /// which in profile is the whole pet facing the other way. Anything but a
    /// sitting pet turns round properly.
    mutating func glance(_ facing: PetFacing) {
        guard facing != pose.facing else { return }
        guard pose.frame.isSitting else {
            turn(facing)
            return
        }
        show(.sit)
        pose.facing = facing
        mark()
    }

    /// On its feet, from whatever it was doing.
    mutating func standUp() {
        switch pose.frame.posture {
        case .standing:
            return
        case .airborne:
            land()
            return
        case .bowing:
            show(.stand)
            return
        case .lying:
            openEyesLying()
        case .sitting, .crouching:
            break
        }
        crouch()
        show(.stand)
    }

    /// On its haunches, from whatever it was doing.
    mutating func sitDown() {
        switch pose.frame.posture {
        case .sitting:
            return
        case .airborne:
            land()
        case .bowing:
            show(.stand)
        case .lying:
            openEyesLying()
        case .standing, .crouching:
            break
        }
        crouch()
        show(.sit)
    }

    /// Down on the floor, from whatever it was doing.
    mutating func lieDown() {
        switch pose.frame.posture {
        case .lying:
            return
        case .airborne:
            land()
        case .bowing:
            show(.stand)
        case .standing, .sitting, .crouching:
            break
        }
        crouch()
        show(.lie)
    }

    /// Back on the floor after a hop, or after a routine that began mid-air:
    /// the landing is a crouch, then the pet straightens up.
    ///
    /// Caught higher than a hop's last step, the pet first comes down the rest
    /// of the way two points a frame, as a hop does: dropping straight to the
    /// floor would replace the pose it was caught in before it was ever drawn.
    mutating func land() {
        guard pose.frame.posture == .airborne || pose.lift != 0 else { return }
        let fallsStepByStep = pose.lift > Self.landingStep
        while pose.lift > Self.landingStep {
            hold(Self.frameInterval)
            pose.lift -= Self.landingStep
            pose.frame = .hop
            mark()
        }
        if fallsStepByStep {
            hold(Self.frameInterval)
        }
        pose.lift = 0
        pose.frame = .crouch
        mark()
        hold(Self.crouchDuration)
        show(.stand)
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

    /// One step of a hop: in the air, `lift` points up.
    mutating func rise(to lift: Int) {
        pose.lift = lift
        pose.frame = .hop
        mark()
    }

    /// Shifts the pet by `points` where it stands: a sway, not a walk.
    mutating func sway(by points: Int) {
        pose.position += points
        mark()
    }

    /// Shows `frames` in turn, each for `interval`, `times` times over.
    mutating func alternate(_ frames: [PetFrame], every interval: TimeInterval, times: Int = 1) {
        for _ in 0..<max(times, 0) {
            for frame in frames {
                show(frame)
                hold(interval)
            }
        }
    }

    /// Plays `timeline` from here, the pet already in its opening pose — how a
    /// loop is played a set number of times before something else follows.
    mutating func append(_ timeline: PetTimeline) {
        let start = time
        for keyframe in timeline.keyframes {
            time = start + keyframe.time
            pose = keyframe.pose
            mark()
        }
        for track in timeline.effects {
            let shifted = track.keyframes.map { PetEffectKeyframe(time: start + $0.time, point: $0.point) }
            effects.append(
                PetEffectTrack(
                    effect: track.effect,
                    isMirrored: track.isMirrored,
                    keyframes: start > 0 ? [PetEffectKeyframe(time: 0, point: nil)] + shifted : shifted
                )
            )
        }
        time = start + timeline.duration
    }

    /// Everything written so far, played once.
    func timeline() -> PetTimeline {
        let lastEffect = effects.compactMap { $0.keyframes.last?.time }.max() ?? 0
        return PetTimeline(keyframes: keyframes, effects: effects, duration: max(time, lastEffect))
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
        return PetTimeline(keyframes: closed, effects: effects, duration: time)
    }

    /// Opens the eyes of a pet asleep or sulking on the floor, the first part
    /// of getting up.
    private mutating func openEyesLying() {
        guard pose.frame != .lie else { return }
        show(.lie)
        hold(Self.crouchDuration)
    }

    private mutating func crouch() {
        guard pose.frame != .crouch else { return }
        show(.crouch)
        hold(Self.crouchDuration)
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

/// One step of an effect's path: where it is from a moment on, in seconds from
/// when it was emitted, or `nil` to take it out of sight for a while.
struct PetEffectStep {
    let after: TimeInterval
    let point: PetPoint?
}

extension PetChoreographer {
    /// Shows `effect` along `path` and takes it away `duration` seconds from
    /// now. The pet's own time does not move: the effect plays alongside
    /// whatever the pet does next.
    mutating func emit(
        _ effect: PetEffect,
        along path: [PetEffectStep],
        lasting duration: TimeInterval,
        mirrored: Bool = false
    ) {
        let steps = path.filter { $0.after < duration }.sorted { $0.after < $1.after }
        guard steps.isEmpty == false else { return }
        var track = time > 0 || steps[0].after > 0 ? [PetEffectKeyframe(time: 0, point: nil)] : []
        for step in steps {
            let keyframe = PetEffectKeyframe(time: time + step.after, point: step.point)
            if track.last?.time == keyframe.time {
                track[track.count - 1] = keyframe
            } else {
                track.append(keyframe)
            }
        }
        track.append(PetEffectKeyframe(time: time + duration, point: nil))
        effects.append(PetEffectTrack(effect: effect, isMirrored: mirrored, keyframes: track))
    }

    /// Shows `effect` at each of `points` in turn, `interval` apart from now,
    /// and takes it away after the last.
    mutating func emit(
        _ effect: PetEffect,
        at points: [PetPoint],
        every interval: TimeInterval,
        mirrored: Bool = false
    ) {
        let step = max(interval, 0.001)
        emit(
            effect,
            along: points.enumerated().map { PetEffectStep(after: Double($0.offset) * step, point: $0.element) },
            lasting: Double(points.count) * step,
            mirrored: mirrored
        )
    }

    /// Shows `effect` at one place for `seconds`.
    mutating func emit(_ effect: PetEffect, at point: PetPoint, for seconds: TimeInterval, mirrored: Bool = false) {
        emit(effect, at: [point], every: seconds, mirrored: mirrored)
    }

    /// A point beside the pet as it is now: `inset` points in from the
    /// sprite's left edge as drawn facing right, mirrored when it faces left,
    /// and `height` points above its feet. Mirroring keeps the effect's width
    /// on the same side of the point, so a question mark over the head is over
    /// the head either way.
    func besidePet(_ effect: PetEffect, inset: Int, height: Int) -> PetPoint {
        let art = PetEffectArt.standard
        let width = (art.pixelWidth(of: effect) + art.pixelsPerPoint - 1) / art.pixelsPerPoint
        let across = pose.facing == .right ? inset : spriteWidth - inset - width
        return PetPoint(position: pose.position + across, height: pose.lift + height)
    }
}
