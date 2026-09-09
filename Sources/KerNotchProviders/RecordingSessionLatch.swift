import Foundation

/// Turns a repeatedly-read "is something capturing right now" boolean into
/// session edges.
///
/// Both system observers face the same problem: the signal they can read is a
/// level, not an edge, and they re-read it on every notification. Without this,
/// a notification arriving mid-recording would restamp the start instant and
/// visibly reset the elapsed counter. The start instant is stamped once, when
/// the session first appears, and carried unchanged until it ends — so the
/// counter measures the recording rather than the time since the last
/// notification.
struct RecordingSessionLatch {
    private(set) var session: RecordingSession?

    /// Returns whether the session changed, and so whether the observer owes
    /// its listener an emission.
    mutating func update(isRecording: Bool, at now: () -> Date) -> Bool {
        guard isRecording else {
            guard session != nil else { return false }

            session = nil
            return true
        }

        guard session == nil else { return false }

        session = RecordingSession(startedAt: now())
        return true
    }

    mutating func reset() {
        session = nil
    }
}
