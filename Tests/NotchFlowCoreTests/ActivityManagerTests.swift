import Foundation
import Testing

@testable import NotchFlowCore

@Suite("ActivityManager")
@MainActor
struct ActivityManagerTests {
    @Test("registers an activity into the active set")
    func registerActivity() {
        let manager = ActivityManager()
        let activity = StubManagerActivity(
            identity: ActivityIdentity("music.playing"),
            kind: .music,
            priority: .low
        )

        manager.register(activity, at: date(1))

        #expect(manager.activeActivities.count == 1)
        #expect(manager.activeActivities.first?.identity == ActivityIdentity("music.playing"))
    }

    @Test("deduplicates activities by identity upon registration")
    func deduplicateByIdentity() {
        let manager = ActivityManager()
        let olderPeer = StubManagerActivity(
            identity: ActivityIdentity("timer.break"),
            kind: .timer,
            priority: .normal
        )
        let initialActivity = StubManagerActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .normal
        )
        let updatedActivity = StubManagerActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .normal
        )

        manager.register(olderPeer, at: date(1))
        manager.register(initialActivity, at: date(2))
        manager.register(updatedActivity, at: date(3))

        #expect(manager.activeActivities.count == 2)
        #expect(manager.activeActivities.map(\.identity) == [olderPeer.identity, updatedActivity.identity])
    }

    @Test("updates an existing activity in place")
    func updateInPlace() {
        let manager = ActivityManager()
        let activity = StubManagerActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .high
        )

        manager.register(activity, at: date(1))

        let updatedActivity = StubManagerActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .critical
        )
        manager.update(updatedActivity, at: date(2))

        #expect(manager.activeActivities.count == 1)
        #expect(manager.activeActivities.first?.priority == .critical)
    }

    @Test("removes an activity when ended")
    func removeOnEnd() {
        let manager = ActivityManager()
        let activity = StubManagerActivity(
            identity: ActivityIdentity("file.transfer"),
            kind: .fileTransfer,
            priority: .normal
        )

        manager.register(activity, at: date(1))
        manager.end(activity.identity, at: date(2))

        #expect(manager.activeActivities.isEmpty)
    }

    @Test("orders active activities by priority and start time")
    func orderingByPriorityAndStartTime() {
        let manager = ActivityManager()
        let music = StubManagerActivity(
            identity: ActivityIdentity("music.track"),
            kind: .music,
            priority: .low
        )
        let transfer = StubManagerActivity(
            identity: ActivityIdentity("file.copy"),
            kind: .fileTransfer,
            priority: .normal
        )
        let timer = StubManagerActivity(
            identity: ActivityIdentity("timer.pomodoro"),
            kind: .timer,
            priority: .high
        )

        manager.register(music, at: date(1))
        manager.register(transfer, at: date(2))
        manager.register(timer, at: date(3))

        let identities = manager.activeActivities.map(\.identity)
        #expect(
            identities == [
                ActivityIdentity("timer.pomodoro"),
                ActivityIdentity("file.copy"),
                ActivityIdentity("music.track"),
            ])
    }

    @Test("enforces compact slot limit and reports overflow count")
    func compactSlotLimitAndOverflow() {
        let manager = ActivityManager(compactCapacity: 2)
        let first = StubManagerActivity(
            identity: ActivityIdentity("act.1"),
            kind: .timer,
            priority: .high
        )
        let second = StubManagerActivity(
            identity: ActivityIdentity("act.2"),
            kind: .fileTransfer,
            priority: .normal
        )
        let third = StubManagerActivity(
            identity: ActivityIdentity("act.3"),
            kind: .music,
            priority: .low
        )

        manager.register(first, at: date(1))
        manager.register(second, at: date(2))
        manager.register(third, at: date(3))

        #expect(manager.compactPresentation.activities.count == 1)
        #expect(manager.compactPresentation.overflowCount == 2)
        #expect(manager.expandedActivities.count == 3)
    }

    @Test("counts concurrent sessions from one agent as one compact activity")
    func compactGroupsSessionsByAgent() {
        let manager = ActivityManager(compactCapacity: 3)
        for index in 0..<4 {
            manager.register(
                aiAgent(
                    agent: .opencode,
                    sessionID: UUID(),
                    state: .working
                ),
                at: date(TimeInterval(index))
            )
        }

        #expect(manager.expandedActivities.count == 4)
        #expect(manager.compactPresentation.activities.count == 1)
        #expect(manager.compactPresentation.overflowCount == 0)
        #expect((manager.compactPresentation.activities.first as? AIAgentActivity)?.agent == .opencode)
    }

    @Test("keeps different agents as separate compact activities")
    func compactKeepsAgentsSeparate() {
        let manager = ActivityManager(compactCapacity: 3)
        manager.register(aiAgent(agent: .opencode, sessionID: UUID()), at: date(1))
        manager.register(aiAgent(agent: .opencode, sessionID: UUID()), at: date(2))
        manager.register(aiAgent(agent: .codex, sessionID: UUID()), at: date(3))
        manager.register(aiAgent(agent: .codex, sessionID: UUID()), at: date(4))

        #expect(manager.compactPresentation.activities.count == 2)
        #expect(manager.compactPresentation.overflowCount == 0)
        #expect(
            Set(
                manager.compactPresentation.activities.compactMap {
                    ($0 as? AIAgentActivity)?.agent
                }
            ) == [.opencode, .codex]
        )
    }

    @Test("reserves two compact positions for the newest AI agents")
    func compactReservesNewestAgentPositions() {
        let manager = ActivityManager(compactCapacity: 3)
        for index in 1...4 {
            manager.register(
                StubManagerActivity(
                    identity: ActivityIdentity("standard.\(index)"),
                    kind: .timer,
                    priority: .high
                ),
                at: date(TimeInterval(index))
            )
        }
        manager.register(aiAgent(agent: .claudeCode, sessionID: UUID()), at: date(5))
        manager.register(aiAgent(agent: .codex, sessionID: UUID()), at: date(6))
        manager.register(aiAgent(agent: .opencode, sessionID: UUID()), at: date(7))

        let presentation = manager.compactPresentation

        #expect(presentation.activities.filter { $0.kind != .aiAgent }.count == 2)
        #expect(
            presentation.activities.compactMap { ($0 as? AIAgentActivity)?.agent }
                == [.codex, .opencode]
        )
        #expect(presentation.overflowCount == 2)
    }

    @Test("represents an agent group with its most important live state")
    func compactAgentRepresentativeState() throws {
        let manager = ActivityManager()
        manager.register(
            aiAgent(agent: .opencode, sessionID: UUID(), state: .completed),
            at: date(1)
        )
        manager.register(
            aiAgent(agent: .opencode, sessionID: UUID(), state: .working),
            at: date(2)
        )

        let activity = try #require(
            manager.compactPresentation.activities.first as? AIAgentActivity
        )
        #expect(activity.state == .working)

        manager.register(
            aiAgent(agent: .opencode, sessionID: UUID(), state: .error),
            at: date(3)
        )
        let error = try #require(
            manager.compactPresentation.activities.first as? AIAgentActivity
        )
        #expect(error.state == .error)
    }

    @Test("fires auto-dismiss when expiration condition is reached")
    func autoDismissFiring() async {
        let manager = ActivityManager(sleep: { _ in })
        let autoDismissActivity = StubManagerActivity(
            identity: ActivityIdentity("charging.status"),
            kind: .charging,
            priority: .normal,
            autoDismiss: AutoDismissDescriptor(after: .seconds(5))
        )

        manager.register(autoDismissActivity, at: date(1))
        await Task.yield()
        await Task.yield()

        #expect(manager.activeActivities.isEmpty)
    }

    @Test("emits idle signal exactly once when transitioning to empty")
    func idleSignalOnEmptying() {
        let manager = ActivityManager()
        var idleSignalCount = 0
        manager.onBecomeIdle = {
            idleSignalCount += 1
        }

        let first = StubManagerActivity(
            identity: ActivityIdentity("act.1"),
            kind: .timer,
            priority: .high
        )
        let second = StubManagerActivity(
            identity: ActivityIdentity("act.2"),
            kind: .music,
            priority: .low
        )

        manager.register(first, at: date(1))
        manager.register(second, at: date(2))

        manager.end(first.identity, at: date(3))
        #expect(idleSignalCount == 0)

        manager.end(second.identity, at: date(4))
        #expect(idleSignalCount == 1)

        manager.end(ActivityIdentity("non-existent"), at: date(5))
        #expect(idleSignalCount == 1)
    }

    @Test("signals every change to the active set")
    func changeSignalOnEveryMutation() {
        let manager = ActivityManager()
        var changeSignalCount = 0
        manager.onActivitiesChanged = {
            changeSignalCount += 1
        }

        let activity = StubManagerActivity(
            identity: ActivityIdentity("timer.focus"),
            kind: .timer,
            priority: .normal
        )

        manager.register(activity, at: date(1))
        #expect(changeSignalCount == 1)

        manager.update(activity, at: date(2))
        #expect(changeSignalCount == 2)

        manager.end(activity.identity, at: date(3))
        #expect(changeSignalCount == 3)

        manager.end(ActivityIdentity("non-existent"), at: date(4))
        #expect(changeSignalCount == 3)
    }

    @Test("multiple presentation observers receive changes independently")
    func multipleChangeObservers() {
        let manager = ActivityManager()
        var firstCount = 0
        var secondCount = 0
        let firstID = manager.observeActivitiesChanged { firstCount += 1 }
        _ = manager.observeActivitiesChanged { secondCount += 1 }
        let activity = StubManagerActivity(
            identity: ActivityIdentity("timer.multi-display"),
            kind: .timer,
            priority: .normal
        )

        manager.register(activity, at: date(1))
        #expect(firstCount == 1)
        #expect(secondCount == 1)

        manager.removeActivitiesObserver(firstID)
        manager.end(activity.identity, at: date(2))
        #expect(firstCount == 1)
        #expect(secondCount == 2)
    }


    // MARK: - Media and capture stay on top

    /// The reported wish, end to end: the track the user is listening to sits
    /// above the agents, whatever the agents are doing and however long they
    /// have been at it.
    @Test("music sorts above every agent state")
    @MainActor
    func musicOutranksAgents() {
        for state in AIAgentState.allCases where state != .idle {
            let manager = ActivityManager()
            // The agent registers first, so start time cannot be what saves the
            // track's place.
            manager.register(
                AIAgentActivity(agent: .claudeCode, sessionID: UUID(), state: state, detail: "x"),
                at: Date(timeIntervalSinceReferenceDate: 0)
            )
            manager.register(
                MusicActivity(
                    nowPlaying: NowPlaying(
                        title: "Windowlicker",
                        artist: "Aphex Twin",
                        playbackState: .playing,
                        sourceApplicationName: "Spotify"
                    )
                ),
                at: Date(timeIntervalSinceReferenceDate: 100)
            )

            #expect(
                manager.activeActivities.first?.kind == .music,
                "an agent in \(state) displaced the music"
            )
        }
    }

    /// A live camera or microphone belongs at the top too.
    @Test("a recording sorts above every agent state")
    @MainActor
    func recordingOutranksAgents() {
        let manager = ActivityManager()
        manager.register(
            AIAgentActivity(
                agent: .claudeCode,
                sessionID: UUID(),
                state: .waitingForUser,
                detail: "x"
            ),
            at: Date(timeIntervalSinceReferenceDate: 0)
        )
        manager.register(
            RecordingActivity.started(.screen, at: Date(timeIntervalSinceReferenceDate: 100)),
            at: Date(timeIntervalSinceReferenceDate: 100)
        )

        #expect(manager.activeActivities.first?.kind == .recording)
    }

    /// A finished turn's green tick is worth catching, so it lingers — but a new
    /// prompt inside that window must replace it at once rather than wait it out.
    @Test("a new turn cancels the completed tick immediately")
    @MainActor
    func aNewTurnCancelsTheCompletedTick() {
        // A sleep that never returns: if the tick's dismissal were what removed
        // the card, nothing here could remove it, and the assertion below would
        // be measuring the timer rather than the replacement.
        let manager = ActivityManager(sleep: { _ in try? await Task.sleep(for: .seconds(3_600)) })
        let session = UUID()

        manager.register(
            AIAgentActivity(agent: .claudeCode, sessionID: session, state: .completed, detail: "done")
        )
        // The next turn arrives while the tick is still on screen.
        manager.register(
            AIAgentActivity(agent: .claudeCode, sessionID: session, state: .thinking, detail: "next")
        )

        let shown = manager.activeActivities.compactMap { $0 as? AIAgentActivity }
        #expect(shown.count == 1, "the turn was added beside the tick instead of replacing it")
        #expect(shown.first?.state == .thinking, "the tick outlived the turn that replaced it")
    }
}

private func aiAgent(
    agent: IPCAgentID,
    sessionID: UUID,
    state: AIAgentState = .working
) -> AIAgentActivity {
    AIAgentActivity(
        agent: agent,
        sessionID: sessionID,
        state: state,
        detail: "Working"
    )
}

private struct StubManagerActivity: Activity {
    let identity: ActivityIdentity
    let kind: ActivityKind
    let priority: ActivityPriority
    let autoDismiss: AutoDismissDescriptor?

    init(
        identity: ActivityIdentity,
        kind: ActivityKind,
        priority: ActivityPriority,
        autoDismiss: AutoDismissDescriptor? = nil
    ) {
        self.identity = identity
        self.kind = kind
        self.priority = priority
        self.autoDismiss = autoDismiss
    }
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}
