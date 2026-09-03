import CoreGraphics
import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// What the island says about an agent that cannot run, and where it says it.
@Suite("Blocked agent footnote")
struct BlockedAgentFootnoteTests {
    private static func blocked(
        _ agent: IPCAgentID = .opencode,
        reason: AIAgentFailureReason = .quotaExhausted,
        retryAt: Date? = nil,
        sessionID: UUID = UUID()
    ) -> AIAgentActivity {
        AIAgentActivity(
            agent: agent,
            sessionID: sessionID,
            state: .error,
            reason: reason,
            retryAt: retryAt,
            detail: "Task failed"
        )
    }

    // MARK: - What counts as blocked

    /// A blocked agent is stopped by something outside the task: no quota, no
    /// credentials, no provider. Those keep failing every retry until something
    /// changes, which is what makes them a standing condition rather than news.
    @Test("only conditions outside the task count as blocked")
    func onlyStandingConditionsBlock() {
        #expect(Self.blocked(reason: .quotaExhausted).isBlocked)
        #expect(Self.blocked(reason: .authFailed).isBlocked)
        #expect(Self.blocked(reason: .providerUnavailable).isBlocked)

        // A refused request and an unclassified failure are about this turn.
        // They are news, and news belongs in the pill like any other error.
        #expect(Self.blocked(reason: .requestRejected).isBlocked == false)
        #expect(Self.blocked(reason: .unknown).isBlocked == false)
    }

    /// A reason outside `error` describes a failure that did not happen.
    @Test("a working agent is never blocked, whatever it carries")
    func workingAgentIsNeverBlocked() {
        let working = AIAgentActivity(
            agent: .opencode,
            sessionID: UUID(),
            state: .working,
            reason: .quotaExhausted,
            detail: "Working"
        )

        #expect(working.reason == nil, "a reason outside error must be dropped")
        #expect(working.isBlocked == false)
    }

    // MARK: - The footnote

    @Test("nothing blocked draws no footnote")
    func nothingBlockedDrawsNoFootnote() {
        let working = AIAgentActivity(
            agent: .opencode, sessionID: UUID(), state: .working, detail: "Working")

        #expect(blockedAgentFootnote(for: [working]) == nil)
    }

    /// Several sessions stop for the same reason at the same moment — that is
    /// what an exhausted quota does. One line for the lot, or the footnote
    /// becomes the noise it exists to remove.
    @Test("many sessions of one agent collapse to one line")
    func manySessionsCollapseToOneLine() throws {
        let sessions: [any Activity] = (0..<4).map { _ in Self.blocked() }
        let footnote = try #require(blockedAgentFootnote(for: sessions))

        #expect(footnote.agents == [.opencode])
        #expect(footnote.title == "OpenCode · Out of quota")
    }

    @Test("two agents are named, more are counted")
    func twoAgentsAreNamedMoreAreCounted() throws {
        let pair = try #require(
            blockedAgentFootnote(for: [Self.blocked(.opencode), Self.blocked(.claudeCode)])
        )
        #expect(pair.title == "OpenCode, Claude · Out of quota")

        let trio = try #require(
            blockedAgentFootnote(for: [
                Self.blocked(.opencode), Self.blocked(.claudeCode), Self.blocked(.codex),
            ])
        )
        #expect(trio.title == "3 agents · Out of quota")
    }

    /// A footnote is one line, not a report. Where causes differ it names the
    /// one the user can act on first.
    @Test("mixed causes collapse to the most actionable one")
    func mixedCausesCollapseToTheMostActionable() throws {
        let footnote = try #require(
            blockedAgentFootnote(for: [
                Self.blocked(.opencode, reason: .providerUnavailable),
                Self.blocked(.claudeCode, reason: .authFailed),
            ])
        )

        #expect(footnote.reason == .authFailed)
        #expect(footnote.agents == [.claudeCode], "only the agents with that cause are named")
    }

    // MARK: - The recovery line

    /// Quota is the only condition that lifts on its own, so it is the only one
    /// a time may be promised for.
    @Test("only a quota block promises a time")
    func onlyQuotaPromisesATime() throws {
        let at = Date().addingTimeInterval(60 * 60)
        let quota = try #require(
            blockedAgentFootnote(for: [Self.blocked(reason: .quotaExhausted, retryAt: at)]))
        let auth = try #require(
            blockedAgentFootnote(for: [Self.blocked(reason: .authFailed, retryAt: at)]))

        #expect(quota.recoveryText() != nil)
        #expect(auth.recoveryText() == nil, "nothing lifts an auth failure but the user")
    }

    /// Without a time from the agent there is nothing to promise, and the
    /// footnote says only what it knows.
    @Test("a quota block with no time still draws")
    func quotaWithNoTimeStillDraws() throws {
        let footnote = try #require(blockedAgentFootnote(for: [Self.blocked()]))

        #expect(footnote.recoveryText() == nil)
        #expect(footnote.title.isEmpty == false)
    }

    /// The earliest recovery wins: that is when the island stops being wrong.
    @Test("the soonest recovery is the one shown")
    func soonestRecoveryWins() throws {
        let soon = Date(timeIntervalSinceReferenceDate: 100)
        let late = Date(timeIntervalSinceReferenceDate: 10_000)
        let footnote = try #require(
            blockedAgentFootnote(for: [
                Self.blocked(retryAt: late), Self.blocked(retryAt: soon),
            ])
        )

        #expect(footnote.retryAt == soon)
    }

    // MARK: - The panel makes room for it

    /// The panel is sized from its height model. A footnote the model does not
    /// know about is a footnote drawn past the bottom of the island.
    @Test("the panel grows to fit the footnote")
    func panelGrowsToFitTheFootnote() {
        let working = AIAgentActivity(
            agent: .claudeCode, sessionID: UUID(), state: .working, detail: "Working")

        let withoutFootnote = expandedPanelSize(for: [working])
        let withFootnote = expandedPanelSize(for: [working, Self.blocked()])

        #expect(withFootnote.height > withoutFootnote.height)
    }

    /// A recovery line is a second line, and the model has to count it.
    @Test("a recovery line makes the footnote taller")
    func recoveryLineMakesItTaller() {
        let oneLine = blockedFootnoteHeight(hasRecoveryText: false)
        let twoLines = blockedFootnoteHeight(hasRecoveryText: true)

        #expect(twoLines > oneLine)
    }

    /// It is the smallest thing the island draws: it is not what the user came
    /// to read.
    @Test("the footnote is the smallest step of the scale")
    func footnoteIsTheSmallestStep() {
        let scale = IslandTypeScale.default

        #expect(scale.footnote < scale.nestedDetail)
        #expect(scale.footnote < scale.detail)
        #expect(scale.footnote < scale.title)
    }

    /// A reset time that has already passed is not a promise, it is a stale one.
    /// Pointing at a moment that has been and gone is worse than saying nothing.
    @Test("a reset time already past is not shown")
    func stalePromiseIsNotShown() throws {
        let past = Date().addingTimeInterval(-60 * 60)
        let footnote = try #require(
            blockedAgentFootnote(for: [Self.blocked(retryAt: past)]))

        #expect(footnote.hasRecoveryText() == false)
        #expect(footnote.recoveryText() == nil)
        #expect(footnote.title.isEmpty == false, "the block itself is still reported")
    }

    /// The height model asks whether there is a time, never formats one: it runs
    /// several times per animation frame and a `DateFormatter` there is a real
    /// cost against the idle budget.
    @Test("the height model agrees with what the view draws")
    func heightModelAgreesWithTheView() throws {
        let ahead = try #require(
            blockedAgentFootnote(for: [Self.blocked(retryAt: Date().addingTimeInterval(3_600))]))
        let none = try #require(blockedAgentFootnote(for: [Self.blocked()]))

        #expect(ahead.hasRecoveryText() == (ahead.recoveryText() != nil))
        #expect(none.hasRecoveryText() == (none.recoveryText() != nil))
        #expect(
            blockedFootnoteHeight(hasRecoveryText: ahead.hasRecoveryText())
                > blockedFootnoteHeight(hasRecoveryText: none.hasRecoveryText())
        )
    }
}

/// How long a blocked agent may occupy the compact pill.
@Suite("Compact announcement window")
struct CompactAnnouncementWindowTests {
    private static func blocked(
        _ agent: IPCAgentID = .opencode,
        sessionID: UUID = UUID()
    ) -> AIAgentActivity {
        AIAgentActivity(
            agent: agent,
            sessionID: sessionID,
            state: .error,
            reason: .quotaExhausted,
            detail: "Task failed"
        )
    }

    private static func working(_ agent: IPCAgentID = .opencode) -> AIAgentActivity {
        AIAgentActivity(agent: agent, sessionID: UUID(), state: .working, detail: "Working")
    }

    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    /// Only a standing condition claims a window. Everything else is its own
    /// news for as long as it lasts.
    @Test("only a blocked agent claims an announcement window")
    func onlyBlockedAgentsClaimAWindow() {
        #expect(Self.blocked().compactAnnouncementWindow != nil)
        #expect(Self.working().compactAnnouncementWindow == nil)
    }

    /// The pill draws a blocked agent for as long as its announcement lasts,
    /// then stops drawing it at all.
    @Test("a blocked agent holds the pill until its window is up")
    func blockedAgentHoldsThePillBriefly() {
        let agent = Self.blocked()
        let starts = advancedAnnouncementStarts(
            previous: [:], activities: [agent], now: Self.start)

        func drawnCount(at now: Date) -> Int {
            compactPresentation(
                CompactActivityPresentation(
                    activities: [agent], overflowCount: 0, groupSizes: [:]),
                reconciledWith: [agent],
                announcementStarts: starts,
                registrationTimes: [agent.identity: Self.start],
                now: now
            ).activities.count
        }

        #expect(drawnCount(at: Self.start.addingTimeInterval(30)) == 1, "announcement cut short")
        #expect(drawnCount(at: Self.start.addingTimeInterval(90)) == 0)
    }

    /// The reported defect in miniature: an agent retrying every forty seconds
    /// must not restart its own announcement and sit in the pill forever.
    @Test("repeating the same failure does not restart the announcement")
    func repeatingAFailureDoesNotRestartIt() {
        let session = UUID()
        var starts = advancedAnnouncementStarts(
            previous: [:], activities: [Self.blocked(sessionID: session)], now: Self.start)

        // Forty seconds later the agent tries again and fails again.
        let retry = Self.blocked(sessionID: session)
        starts = advancedAnnouncementStarts(
            previous: starts, activities: [retry], now: Self.start.addingTimeInterval(40))

        let drawn = compactPresentation(
            CompactActivityPresentation(activities: [retry], overflowCount: 0, groupSizes: [:]),
            reconciledWith: [retry],
            announcementStarts: starts,
            registrationTimes: [retry.identity: Self.start],
            now: Self.start.addingTimeInterval(70)
        ).activities

        #expect(drawn.isEmpty, "the retry restarted the announcement")
    }

    /// An agent that recovers has something new to say, and gets to say it.
    @Test("recovering clears the announcement")
    func recoveringClearsTheAnnouncement() {
        let session = UUID()
        let starts = advancedAnnouncementStarts(
            previous: [:], activities: [Self.blocked(sessionID: session)], now: Self.start)
        let recovered = AIAgentActivity(
            agent: .opencode, sessionID: session, state: .working, detail: "Working")

        let advanced = advancedAnnouncementStarts(
            previous: starts, activities: [recovered], now: Self.start.addingTimeInterval(90))

        #expect(advanced.isEmpty)
        #expect(
            compactPresentation(
                CompactActivityPresentation(
                    activities: [recovered], overflowCount: 0, groupSizes: [:]),
                reconciledWith: [recovered],
                announcementStarts: advanced,
                registrationTimes: [recovered.identity: Self.start],
                now: Self.start.addingTimeInterval(200)
            ).activities.count == 1
        )
    }

    /// One blocked sub-agent must not take a working instance's icon off the
    /// pill with it — the agent is still doing something worth showing.
    @Test("a group stays while any of it still has something to say")
    func groupStaysWhileAnyMemberIsLive() {
        let blocked = Self.blocked()
        let working = Self.working()
        let starts = advancedAnnouncementStarts(
            previous: [:], activities: [blocked, working], now: Self.start)

        let drawn = compactPresentation(
            CompactActivityPresentation(activities: [blocked], overflowCount: 0, groupSizes: [:]),
            reconciledWith: [blocked, working],
            announcementStarts: starts,
            registrationTimes: [blocked.identity: Self.start, working.identity: Self.start],
            now: Self.start.addingTimeInterval(600)
        ).activities

        #expect(drawn.count == 1)
    }

    /// Hiding the slot is only half of it. A group that keeps its slot — because
    /// something in it is still working — had its speaker picked by urgency, and
    /// a failure outranks work in flight. One blocked instance would otherwise
    /// keep an agent's icon red for hours while another instance ran happily.
    @Test("a muted failure stops speaking for a group that is still working")
    func mutedFailureStopsSpeakingForALiveGroup() throws {
        let blocked = Self.blocked()
        let working = Self.working()
        let starts = advancedAnnouncementStarts(
            previous: [:], activities: [blocked, working], now: Self.start)
        let after = Self.start.addingTimeInterval(90)

        // The manager picks the failure: it is the more urgent of the two.
        let raw = CompactActivityPresentation(
            activities: [blocked], overflowCount: 0, groupSizes: [:])

        let adjusted = compactPresentation(
            raw,
            reconciledWith: [blocked, working],
            announcementStarts: starts,
            registrationTimes: [blocked.identity: Self.start, working.identity: Self.start],
            now: after
        )

        let speaker = try #require(adjusted.activities.first as? AIAgentActivity)
        #expect(speaker.state == .working, "the muted failure still speaks for the group")
    }

    /// Before the window is up the failure is exactly what the pill should say.
    @Test("a failure still speaks during its announcement")
    func failureSpeaksDuringItsAnnouncement() throws {
        let blocked = Self.blocked()
        let working = Self.working()
        let starts = advancedAnnouncementStarts(
            previous: [:], activities: [blocked, working], now: Self.start)

        let adjusted = compactPresentation(
            CompactActivityPresentation(
                activities: [blocked], overflowCount: 0, groupSizes: [:]),
            reconciledWith: [blocked, working],
            announcementStarts: starts,
            registrationTimes: [blocked.identity: Self.start, working.identity: Self.start],
            now: Self.start.addingTimeInterval(20)
        )

        let speaker = try #require(adjusted.activities.first as? AIAgentActivity)
        #expect(speaker.state == .error)
    }

    /// The compact presentation is computed on demand, so nothing re-reads it
    /// until something changes — and an agent that failed once and went quiet
    /// sends nothing more. Without a deadline to wake on, its announcement
    /// never ends and the pill stays red for the activity's whole lifetime.
    @Test("a pending announcement reports the deadline to wake on")
    func pendingAnnouncementReportsItsDeadline() throws {
        let agent = Self.blocked()
        let starts = advancedAnnouncementStarts(
            previous: [:], activities: [agent], now: Self.start)

        let deadline = try #require(
            nextAnnouncementDeadline(
                for: [agent], announcementStarts: starts, after: Self.start)
        )

        #expect(deadline == Self.start.addingTimeInterval(60))
    }

    /// Once it has elapsed there is nothing left to wake for, which is what
    /// stops the refresh it triggers from scheduling another one forever.
    @Test("an elapsed announcement asks for no further wake-up")
    func elapsedAnnouncementAsksForNoWakeUp() {
        let agent = Self.blocked()
        let starts = advancedAnnouncementStarts(
            previous: [:], activities: [agent], now: Self.start)

        #expect(
            nextAnnouncementDeadline(
                for: [agent],
                announcementStarts: starts,
                after: Self.start.addingTimeInterval(90)
            ) == nil
        )
    }

    /// Nothing pending, nothing scheduled: the ordinary case must not arm a
    /// timer at all.
    @Test("an unblocked island schedules nothing")
    func unblockedIslandSchedulesNothing() {
        let working = Self.working()

        #expect(
            nextAnnouncementDeadline(
                for: [working],
                announcementStarts: advancedAnnouncementStarts(
                    previous: [:], activities: [working], now: Self.start),
                after: Self.start
            ) == nil
        )
    }

    /// Several pending windows wake on the soonest, or a later one would keep
    /// an earlier announcement on screen past its time.
    @Test("the soonest pending deadline wins")
    func soonestPendingDeadlineWins() throws {
        let first = Self.blocked()
        let second = Self.blocked()
        let starts = advancedAnnouncementStarts(
            previous: advancedAnnouncementStarts(
                previous: [:], activities: [first], now: Self.start),
            activities: [first, second],
            now: Self.start.addingTimeInterval(30)
        )

        let deadline = try #require(
            nextAnnouncementDeadline(
                for: [first, second], announcementStarts: starts, after: Self.start)
        )

        #expect(deadline == Self.start.addingTimeInterval(60), "woke on the later window")
    }

    /// The defect this reconciliation exists for, end to end.
    ///
    /// The manager fits agent groups to the pill by urgency, and a failure
    /// outranks work in flight — so a blocked agent wins a slot. Hiding it
    /// afterwards left that slot empty while a third agent that was genuinely
    /// working never appeared at all.
    @Test("a muted agent gives its slot back to one that is working")
    @MainActor
    func mutedAgentGivesItsSlotBack() {
        let manager = ActivityManager()
        let blocked = Self.blocked(.claudeCode)
        let codex = AIAgentActivity(
            agent: .codex, sessionID: UUID(), state: .working, detail: "Working")
        let opencode = Self.working()
        manager.register(blocked, at: Self.start)
        manager.register(codex, at: Self.start.addingTimeInterval(10))
        manager.register(opencode, at: Self.start.addingTimeInterval(20))

        let all = manager.expandedActivities
        let starts = advancedAnnouncementStarts(previous: [:], activities: all, now: Self.start)

        // The manager picks the failure first: it is the more urgent.
        let managerChoice = manager.compactPresentation.activities
            .compactMap { ($0 as? AIAgentActivity)?.agent }
        #expect(managerChoice.contains(.claudeCode))

        let drawn = compactPresentation(
            manager.compactPresentation,
            reconciledWith: all,
            announcementStarts: starts,
            registrationTimes: manager.registrationTimes,
            now: Self.start.addingTimeInterval(120)
        ).activities.compactMap { ($0 as? AIAgentActivity)?.agent }

        #expect(drawn.count == 2, "the muted agent kept a slot it no longer draws in")
        #expect(drawn.contains(.claudeCode) == false)
        #expect(Set(drawn) == [.codex, .opencode])
    }
}
