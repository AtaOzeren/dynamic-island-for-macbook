import Foundation

/// A routine, and the moment it began.
///
/// Moments are seconds of system uptime (`ProcessInfo.systemUptime`), the
/// clock Core Animation's media time runs on. Once a routine is handed to Core
/// Animation, only that clock moves the pet on screen; timing the routine by
/// the wall clock would let a clock correction or plain drift put the pose
/// this reads somewhere the pet is not, and the next stage change would start
/// from there — a jump.
public struct PetPerformance: Equatable, Sendable {
    public let routine: PetRoutine
    public let startedAt: TimeInterval

    public init(routine: PetRoutine, startedAt: TimeInterval) {
        self.routine = routine
        self.startedAt = startedAt
    }

    /// Seconds into the routine at uptime `now`; never negative, so a clock
    /// read a hair before the routine began shows its opening pose.
    public func elapsed(at now: TimeInterval) -> TimeInterval {
        max(now - startedAt, 0)
    }

    public func pose(at now: TimeInterval) -> PetPose {
        routine.pose(atElapsed: elapsed(at: now))
    }
}

/// The pet's life across stage changes: which routine it is performing, and
/// since when.
///
/// Held by the presenter rather than by the view that draws the pet. That view
/// is rebuilt every time the island expands and collapses, and a routine kept
/// there would start over from the edge of the island on every hover. Here it
/// changes only when the stage does, and each change starts from wherever the
/// pet is at that moment, so the pet never jumps.
public struct PetRoutineTracker: Equatable, Sendable {
    public private(set) var performance: PetPerformance?

    public init() {}

    /// Follows the pet onto `stage` at uptime `now`. A stage the pet is
    /// already on changes nothing, so this is safe to call on every refresh.
    ///
    /// A pet with no routine yet — just switched on — enters from beyond the
    /// island's outer edge.
    public mutating func follow(_ stage: PetStage, at now: TimeInterval, geometry: PetStageGeometry) {
        guard performance?.routine.stage != stage else { return }

        let pose =
            performance?.pose(at: now)
            ?? PetPose(position: geometry.offstagePosition, facing: .right, frame: .stand)
        performance = PetPerformance(
            routine: PetRoutine(stage: stage, from: pose, geometry: geometry),
            startedAt: now
        )
    }

    /// The pet is gone from the island — switched off in the Pet tab. When it
    /// comes back it enters from beyond the edge again rather than resuming a
    /// routine nobody saw finish.
    public mutating func forget() {
        performance = nil
    }
}
