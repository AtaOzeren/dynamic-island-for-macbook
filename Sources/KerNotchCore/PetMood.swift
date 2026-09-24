import Foundation

/// What is going on around the pet, which decides what it does between
/// reactions: nodding along while music plays, digging while an agent works.
public enum PetMood: Equatable, Sendable {
    /// Nothing in particular: the stage's own loop.
    case calm
    /// The island has had nothing on it since `since` — seconds of system
    /// uptime — so the pet keeps to its loop and, once the island has been
    /// empty long enough, lies down for a nap.
    case idle(since: TimeInterval)
    /// Music is playing.
    case listening
    /// An agent is working.
    case digging
    /// A Discord call is going on.
    case onCall
    /// An agent is out of quota: asleep until it is back.
    case napping
    /// An agent is waiting on the user.
    case asking
    /// The screen is being recorded, and the pet keeps out of the picture.
    case hiding
}

/// Everything about the pet's surroundings a routine is planned for.
public struct PetScene: Equatable, Sendable {
    public let stage: PetStage
    public let geometry: PetStageGeometry
    public let mood: PetMood

    public init(stage: PetStage, geometry: PetStageGeometry, mood: PetMood = .calm) {
        self.stage = stage
        self.geometry = geometry
        self.mood = mood
    }
}
