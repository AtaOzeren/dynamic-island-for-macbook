import Foundation

/// Something the pet does in answer to what happens on the island: a hop when
/// the island opens, a tilt of the head when an agent asks something, a
/// celebration when one finishes.
///
/// A reaction is a few seconds long and played where the pet is. It never
/// leaves the stage it is given, so an icon beside the pet is never walked
/// through, and it ends on the floor — sitting, or standing to set off — so the
/// routine that follows can take over from it without a jump.
public enum PetReaction: String, CaseIterable, Sendable {
    /// The island opening: startled into a hop, with an exclamation mark.
    case surprisedHop
    /// The island opening: running with its edge to the new corner.
    case runAlongEdge
    /// The island opening: lying down to watch for as long as it stays open.
    case lieAndWatch
    /// The island closing: shaking itself off like a wet dog.
    case shakeOff
    /// The island closing: a long stretch, then a yawn.
    case stretch
    /// The island closing: panting with relief.
    case relief
    /// An agent asking something: ear flopped, head tilted, question mark.
    case headTilt
    /// An agent asking something: barking to fetch the user.
    case barkForAttention
    /// An agent asking something: a paw raised, like a hand.
    case raisePaw
    /// An agent asking something: looking one way, then the other.
    case lookAround
    /// An agent failing: lying down with its ears back under a rain cloud.
    case sulk
    /// An agent failing: seeing stars.
    case dazed
    /// An agent failing: keeling over, then shaking it off.
    case faint
    /// An agent finishing: hopping for joy among sparkles.
    case celebrate
    /// An agent finishing: tearing back and forth across the flank.
    case zoomies
    /// An agent finishing: catching a bone that drops from above.
    case treat
    /// A countdown running out: barking at the bell.
    case timerAlarm
    /// The charger going in: a jolt, a hop and a dash.
    case powerRush
    /// The pointer moving onto the pet: wagging, with hearts.
    case petted
    /// The CPU watchdog's notice: panting, with a bead of sweat.
    case sweat
    /// An agent out of quota: a yawn, then off to sleep until it is back.
    case dozeOff

    /// Whether the reaction needs the whole flank to run in. Beside an icon
    /// there is one place, and the pet reacts in it or not at all.
    var needsRoom: Bool {
        self == .zoomies || self == .runAlongEdge
    }
}

/// Something that happened, which the pet may answer with a reaction.
public enum PetMoment: Hashable, Sendable {
    case islandOpened
    case islandClosed
    case agentAsked
    case agentFailed
    case quotaExhausted
    case agentCompleted
    case timerExpired
    case chargerConnected
    case cpuStrained
    case petted

    /// The reactions the pet chooses between, at random, for this moment.
    public var reactions: [PetReaction] {
        switch self {
        case .islandOpened: [.surprisedHop, .runAlongEdge, .lieAndWatch]
        case .islandClosed: [.shakeOff, .stretch, .relief]
        case .agentAsked: [.headTilt, .barkForAttention, .raisePaw, .lookAround]
        case .agentFailed: [.sulk, .dazed, .faint]
        case .quotaExhausted: [.dozeOff]
        case .agentCompleted: [.celebrate, .zoomies, .treat]
        case .timerExpired: [.timerAlarm]
        case .chargerConnected: [.powerRush]
        case .cpuStrained: [.sweat]
        case .petted: [.petted]
        }
    }

    /// How much the moment matters: a reaction to a moment that matters as much
    /// or more cuts in on one already playing, anything less is let go.
    public var urgency: PetUrgency {
        switch self {
        case .agentAsked, .agentFailed, .quotaExhausted: .pressing
        case .agentCompleted, .timerExpired: .notable
        case .chargerConnected, .cpuStrained: .passing
        case .islandOpened, .islandClosed, .petted: .casual
        }
    }

    /// The island opening and closing happen whenever the pointer passes over
    /// it, so they are answered only now and then; everything else is news.
    var isOccasional: Bool {
        self == .islandOpened || self == .islandClosed
    }
}

/// How much a moment matters to the pet.
public enum PetUrgency: Int, Comparable, Sendable {
    case casual
    case passing
    case notable
    case pressing

    public static func < (lhs: PetUrgency, rhs: PetUrgency) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
