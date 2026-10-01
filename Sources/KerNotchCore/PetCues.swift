import Foundation

/// What the pet makes of the island at one refresh: the mood it is in, and
/// what has just happened that it might answer.
public struct PetCues: Equatable, Sendable {
    public let mood: PetMood
    public let moments: [PetMoment]

    public init(mood: PetMood, moments: [PetMoment]) {
        self.mood = mood
        self.moments = moments
    }
}

/// Reads the island, refresh after refresh, for what the pet should notice.
///
/// News is an arrival — a state entered, a notice appearing, the island
/// opening — never a state merely held: agents repeat their state freely, and
/// a pet that reacted to every repetition would never stop. The first reading
/// sets the baseline for the island's own opening and closing, so switching
/// the pet on is not taken for the island having just opened.
public struct PetCueReader: Equatable, Sendable {
    private var agentStates: [ActivityIdentity: AIAgentState] = [:]
    private var timerWasExpiring = false
    private var wasOnPower = false
    private var hadWatchdogNotice = false
    private var wasExpanded: Bool?
    private var emptySince: TimeInterval?

    public init() {}

    /// Reads `activities` at uptime `now`, with the island expanded or not.
    public mutating func read(activities: [any Activity], isExpanded: Bool, at now: TimeInterval) -> PetCues {
        var moments = agentMoments(in: activities)

        let timerIsExpiring = activities.contains { ($0 as? TimerActivity)?.isExpiring == true }
        if timerIsExpiring, timerWasExpiring == false {
            moments.append(.timerExpired)
        }
        timerWasExpiring = timerIsExpiring

        if let charging = activities.lazy.compactMap({ $0 as? ChargingActivity }).first {
            if charging.state.isConnectedToPower, wasOnPower == false {
                moments.append(.chargerConnected)
            }
            wasOnPower = charging.state.isConnectedToPower
        }

        let hasWatchdogNotice = activities.contains { $0 is WatchdogNoticeActivity }
        if hasWatchdogNotice, hadWatchdogNotice == false {
            moments.append(.cpuStrained)
        }
        hadWatchdogNotice = hasWatchdogNotice

        if let wasExpanded, wasExpanded != isExpanded {
            moments.append(isExpanded ? .islandOpened : .islandClosed)
        }
        wasExpanded = isExpanded

        emptySince = activities.isEmpty ? (emptySince ?? now) : nil
        return PetCues(mood: mood(among: activities), moments: moments)
    }

    /// The sessions that have just entered a state worth answering. A
    /// sub-agent finishing is not news — its instance is still working — but a
    /// sub-agent asking or failing blocks it, so those count.
    private mutating func agentMoments(in activities: [any Activity]) -> [PetMoment] {
        let sessions = activities.compactMap { $0 as? AIAgentActivity }
        let moments: [PetMoment] = sessions.compactMap { session in
            guard agentStates[session.identity] != session.state else { return nil }
            switch session.state {
            case .waitingForUser:
                return .agentAsked
            case .completed where session.isSubagent == false:
                return .agentCompleted
            case .error:
                return session.reason == .quotaExhausted ? .quotaExhausted : .agentFailed
            case .idle, .thinking, .working, .usingTool, .completed:
                return nil
            }
        }
        agentStates = Dictionary(sessions.map { ($0.identity, $0.state) }, uniquingKeysWith: { _, latest in latest })
        return moments
    }

    /// The strongest of what is going on: keeping out of a screen recording
    /// first, then an agent waiting on the user, then one out of quota, then a
    /// call, an agent at work, music, and last an island with nothing on it.
    private func mood(among activities: [any Activity]) -> PetMood {
        let sessions = activities.compactMap { $0 as? AIAgentActivity }
        if activities.contains(where: { ($0 as? RecordingActivity)?.source == .screen }) {
            return .hiding
        }
        if sessions.contains(where: { $0.state == .waitingForUser }) {
            return .asking
        }
        if sessions.contains(where: { $0.state == .error && $0.reason == .quotaExhausted }) {
            return .napping
        }
        if activities.contains(where: { $0 is DiscordCallActivity }) {
            return .onCall
        }
        if sessions.contains(where: { [.thinking, .working, .usingTool].contains($0.state) }) {
            return .digging
        }
        if activities.contains(where: { ($0 as? MusicActivity)?.nowPlaying.playbackState == .playing }) {
            return .listening
        }
        if let emptySince {
            return .idle(since: emptySince)
        }
        return .calm
    }
}
