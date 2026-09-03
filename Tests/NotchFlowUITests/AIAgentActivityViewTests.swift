import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// What the AI agent views draw for each state and supported agent.
@Suite("AIAgentActivityView")
@MainActor
struct AIAgentActivityViewTests {
    /// A session an agent spawned to delegate work, as `AIAgentActivity` sees it.
    private static func subagent(
        root: UUID,
        name: String?,
        state: AIAgentState = .usingTool,
        sessionID: UUID = UUID()
    ) -> AIAgentActivity {
        AIAgentActivity(
            agent: .opencode,
            sessionID: sessionID,
            rootSessionID: root,
            sessionName: name,
            state: state,
            detail: "Delegated work"
        )
    }

    private static func activity(
        agent: IPCAgentID = .claudeCode,
        sessionID: UUID = UUID(
            uuid: (0x6F, 0x96, 0x19, 0xFF, 0x8B, 0x86, 0xD0, 0x11, 0xB4, 0x2D, 0x00, 0xC0, 0x4F, 0xC9, 0x64, 0xFF)
        ),
        state: AIAgentState = .working,
        detail: String = "Editing src/App.swift",
        toolName: String? = nil,
        progress: Double? = nil
    ) -> AIAgentActivity {
        AIAgentActivity(
            agent: agent,
            sessionID: sessionID,
            state: state,
            detail: detail,
            toolName: toolName,
            progress: progress
        )
    }

    private static func presentation(
        agent: IPCAgentID = .claudeCode,
        state: AIAgentState = .working,
        detail: String = "Editing src/App.swift",
        toolName: String? = nil,
        progress: Double? = nil
    ) -> AIAgentPresentation {
        AIAgentPresentation(
            activity: activity(
                agent: agent,
                state: state,
                detail: detail,
                toolName: toolName,
                progress: progress
            )
        )
    }

    // MARK: - Distinctness across all seven states

    @Test("gives each state its own status text")
    func statusTextPerState() {
        let texts = AIAgentState.allCases.map { Self.presentation(state: $0).statusText }

        #expect(Set(texts).count == AIAgentState.allCases.count)
    }

    /// The compact column of the state table in `docs/07-ai-integration.md`,
    /// checked as whole lines rather than as fragments — the pill is where a
    /// state has to be legible without expanding anything.
    @Test("draws the agent and its status in the compact line")
    func compactTitlePerState() {
        #expect(Self.presentation(state: .thinking).compactTitle == "Claude · Thinking…")
        #expect(Self.presentation(state: .working).compactTitle == "Claude · Working…")
        #expect(Self.presentation(state: .waitingForUser).compactTitle == "Claude · Needs your input")
        #expect(Self.presentation(state: .completed).compactTitle == "Claude · Task completed")
        #expect(Self.presentation(state: .error).compactTitle == "Claude · Task error")
    }

    @Test("surfaces workspace last path component in compact title")
    func rendersWorkspaceName() {
        let activity = AIAgentActivity(
            agent: .claudeCode,
            sessionID: UUID(),
            workspace: "/Users/test/Projects/my-awesome-app",
            state: .working,
            detail: "Working..."
        )
        let presentation = AIAgentPresentation(activity: activity)
        #expect(presentation.workspace == "/Users/test/Projects/my-awesome-app")
        #expect(presentation.workspaceName == "my-awesome-app")
        #expect(presentation.compactTitle == "Claude · my-awesome-app · Working…")
    }

    @Test("names each supported agent")
    func agentLabel() {
        #expect(Self.presentation(agent: .claudeCode).agentName == "Claude")
        #expect(Self.presentation(agent: .codex).agentName == "Codex")
        #expect(Self.presentation(agent: .opencode).agentName == "OpenCode")
    }

    // MARK: - The tool name

    @Test("names the tool in flight while using one")
    func rendersToolName() {
        let presentation = Self.presentation(state: .usingTool, toolName: "Bash")

        #expect(presentation.toolName == "Bash")
        #expect(presentation.compactTitle == "Claude · Running Bash…")
    }

    /// An agent can report `usingTool` without naming the tool; the line must
    /// still be a sentence rather than "Running …".
    @Test("falls back to a generic tool line when the agent names none")
    func fallsBackWhenToolIsUnnamed() {
        #expect(Self.presentation(state: .usingTool).compactTitle == "Claude · Running tool…")
    }

    /// The envelope marks `toolName` meaningful only in `usingTool`, so no other
    /// state may leak one into its line.
    @Test("draws no tool name outside the using-tool state")
    func toolNameIsScopedToUsingTool() {
        for state in AIAgentState.allCases where state != .usingTool {
            let presentation = Self.presentation(state: state, toolName: "Bash")

            #expect(presentation.toolName == nil)
            #expect(presentation.compactTitle.contains("Bash") == false)
        }
    }

    // MARK: - Optional progress

    @Test("carries the reported progress through to the view")
    func rendersProgress() {
        #expect(Self.presentation(progress: 0.4).progress == 0.4)
    }

    /// Indeterminate work must not be drawn as a zero-length bar, so the absence
    /// of a fraction has to survive to the view rather than defaulting to zero.
    @Test("omits progress when the agent reports none")
    func omitsAbsentProgress() {
        #expect(Self.presentation(progress: nil).progress == nil)
    }

    /// The bar takes vertical space, so the view's height has to grow with it —
    /// otherwise it is drawn outside the allocated panel frame and clipped.
    @Test("reserves height for the progress bar only when there is progress")
    func progressChangesExpandedHeight() {
        let withProgress = aiAgentExpandedSize(hasProgress: true)
        let withoutProgress = aiAgentExpandedSize(hasProgress: false)

        #expect(withProgress.height > withoutProgress.height)
    }

    /// The `NSPanel` frame is allocated once and never resized, so width stays
    /// inside the allocation. Height does not clamp: the panel scrolls content
    /// past the ceiling, and a height clamped here is a sub-agent list the user
    /// can never scroll to.
    @Test("clamps the expanded width to the window's allocation")
    func expandedWidthIsClamped() {
        let panelMetrics = PanelMetrics(
            maximumExpandedSize: CGSize(width: 100, height: 20),
            minimumBottomInset: 120
        )
        let size = aiAgentExpandedSize(hasProgress: true, panelMetrics: panelMetrics)

        #expect(size.width <= 100)
    }

    /// A disclosed tree taller than the window must be reported at its full
    /// drawn height: the scroll view's content is sized from this number, so a
    /// clamped report is a list whose tail no amount of scrolling reaches.
    @Test("reports a disclosed tree taller than the window at its full height")
    func oversizedDisclosureIsNotClamped() {
        let metrics = AIAgentViewMetrics.default
        let subagentCount = 25

        let size = aiAgentExpandedSize(
            hasProgress: false,
            subagentCount: subagentCount,
            isDisclosed: true,
            metrics: metrics
        )
        let natural =
            metrics.glyphSize
            + metrics.subagentSeparatorHeight
            + CGFloat(subagentCount) * metrics.subagentRowHeight
            + metrics.contentInset * 2

        #expect(size.height == natural)
        #expect(size.height > PanelMetrics.default.maximumExpandedSize.height)
    }

    // MARK: - The detail line

    @Test("draws the detail line the agent sent")
    func rendersDetail() {
        #expect(Self.presentation(detail: "Running test suite").detail == "Running test suite")
    }

    /// An agent that sends an empty detail must not produce a blank second line.
    @Test("drops the detail line when the agent sends none")
    func omitsEmptyDetail() {
        #expect(Self.presentation(detail: "").detail == nil)
    }

    private static func agentActivityViewSource() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/NotchFlowUI/AIAgentActivityView.swift"),
            encoding: .utf8
        )
    }

    // MARK: - The compact slot

    @Test("normalizes Codex artwork to the OpenCode icon footprint")
    func normalizesCodexArtworkSize() {
        #expect(aiAgentIconArtworkScale(for: .claudeCode) == 1)
        #expect(aiAgentIconArtworkScale(for: .opencode) == 1)
        #expect(aiAgentIconArtworkScale(for: .codex) == 1.24)
    }

    // MARK: - The fallback tile

    /// The bug this covers: OpenCode's fallback painted a hardcoded
    /// `Color.black`, which in light appearance read as an unblended box rather
    /// than as a tile. Its background must move with the scheme.
    @Test("the OpenCode fallback tile is never a raw black rectangle")
    func openCodeFallbackAdaptsToTheScheme() {
        let light = agentFallbackIconPalette(for: .opencode, scheme: .light)
        let dark = agentFallbackIconPalette(for: .opencode, scheme: .dark)

        #expect(light.background != .black)
        #expect(dark.background != .black)
        #expect(light.background != dark.background)
    }

    /// A tile whose glyph matches its background is an empty square. Asserted
    /// per scheme because the light tile inverts both tones together.
    @Test("every fallback tile keeps its glyph off its own background")
    func fallbackGlyphsStayVisible() {
        for agent in IPCAgentID.allCases {
            for scheme in [IslandColorScheme.light, .dark] {
                let palette = agentFallbackIconPalette(for: agent, scheme: scheme)

                #expect(
                    palette.glyph != palette.background,
                    "\(agent) in \(scheme) draws its glyph on a contrasting tile"
                )
                #expect(
                    palette.glyphCounter != palette.background,
                    "\(agent) in \(scheme) keeps its counter off the tile"
                )
            }
        }
    }

    /// Terracotta and blue are brand marks, not surfaces: an agent that changed
    /// hue with the system appearance would read as two different products.
    @Test("branded fallback tiles hold their hue across schemes")
    func brandedFallbackTilesDoNotShiftWithTheScheme() {
        for agent in [IPCAgentID.claudeCode, .codex] {
            #expect(
                agentFallbackIconPalette(for: agent, scheme: .light)
                    == agentFallbackIconPalette(for: agent, scheme: .dark)
            )
        }
    }

    /// All three agents have to reach the screen through the one component, or
    /// the divergence this replaced grows back. Asserted on the source because a
    /// SwiftUI body cannot be measured without a window server.
    @Test("all three fallback tiles render through the shared component")
    func fallbacksShareOneComponent() throws {
        let source = try Self.agentActivityViewSource()

        #expect(source.contains("AgentFallbackIcon(agentID: agentID, size: size)"))
        #expect(!source.contains("OpenCodeLogo"))
    }

    @Test("compact slots carry the originating agent logo identity")
    func compactSlotUsesAgentIdentity() {
        for agent in IPCAgentID.allCases {
            let slot = aiAgentCompactSlot(for: Self.activity(agent: agent, state: .error))

            #expect(slot.aiAgentPresentation?.agentID == agent)
        }
    }

    @Test("maps every agent state to its compact indicator")
    func compactIndicatorPerState() {
        let expectations: [(AIAgentState, AIAgentCompactIndicator)] = [
            (.idle, .none),
            (.thinking, .working),
            (.working, .working),
            (.usingTool, .working),
            (.waitingForUser, .question),
            (.error, .error),
            (.completed, .completed),
        ]

        for (state, indicator) in expectations {
            let slot = aiAgentCompactSlot(for: Self.activity(state: state))

            #expect(slot.aiAgentPresentation?.indicator == indicator)
        }
    }

    @Test("uses compact status symbols with the chosen meanings")
    func compactStatusSymbols() {
        #expect(AIAgentCompactIndicator.question.symbolName == "questionmark")
        #expect(AIAgentCompactIndicator.error.symbolName == "exclamationmark")
        #expect(AIAgentCompactIndicator.completed.symbolName == "checkmark")
        #expect(AIAgentCompactIndicator.question.badgeTone == .yellow)
        #expect(AIAgentCompactIndicator.error.badgeTone == .red)
        #expect(AIAgentCompactIndicator.completed.badgeTone == .green)
        #expect(AIAgentCompactIndicator.none.symbolName == nil)
        #expect(AIAgentCompactIndicator.working.symbolName == nil)
    }

    @Test("keeps every supported agent on the same state mapping")
    func compactIndicatorsAreAgentIndependent() {
        for agent in IPCAgentID.allCases {
            let slot = aiAgentCompactSlot(
                for: Self.activity(agent: agent, state: .waitingForUser)
            )

            #expect(slot.aiAgentPresentation?.indicator == .question)
        }
    }

    @Test("compact activity routing preserves the agent logo identity")
    func compactActivityRoutingUsesAgentIdentity() throws {
        let manager = ActivityManager()
        manager.register(Self.activity(agent: .codex))

        let slot = try #require(compactSlots(for: manager.compactPresentation).first)

        #expect(slot.aiAgentPresentation?.agentID == .codex)
        #expect(slot.aiAgentPresentation?.indicator == .working)
    }

    @Test("uses a three-point working dot with short horizontal travel")
    func compactWorkingIndicatorMetrics() {
        let metrics = CompactAIAgentMetrics.default

        #expect(metrics.dotDiameter == 3)
        #expect(metrics.travelDistance == 8)
        #expect(metrics.oneWayDuration == 0.65)
    }

    @Test("moves the working dot between both endpoints and back")
    func compactWorkingDotMotion() {
        let metrics = CompactAIAgentMetrics.default
        let halfTravel = metrics.travelDistance / 2

        #expect(
            compactAIAgentWorkingDotOffset(
                at: 0,
                reduceMotion: false
            ) == -halfTravel
        )
        #expect(
            abs(
                compactAIAgentWorkingDotOffset(
                    at: metrics.oneWayDuration,
                    reduceMotion: false
                ) - halfTravel
            ) < 0.001
        )
        #expect(
            abs(
                compactAIAgentWorkingDotOffset(
                    at: metrics.oneWayDuration * 2,
                    reduceMotion: false
                ) + halfTravel
            ) < 0.001
        )
    }

    @Test("centres the working dot when reduced motion is enabled")
    func compactWorkingDotReducedMotion() {
        #expect(
            compactAIAgentWorkingDotOffset(
                at: 10,
                reduceMotion: true
            ) == 0
        )
    }

    /// The green tick is the one thing the user looks up *after* the work is
    /// done, so it has to survive a glance away from the screen.
    @Test("the completed tick stays long enough to be caught")
    func compactCompletedLifetime() {
        let slot = aiAgentCompactSlot(for: Self.activity(state: .completed))

        #expect(slot.aiAgentPresentation?.indicator == .completed)
        #expect(AIAgentActivity.completedAutoDismissAfter == .seconds(15))
    }

    @Test("announces the state and detail rather than the generic kind label")
    func compactSlotAnnouncesTheState() {
        let slot = aiAgentCompactSlot(for: Self.activity(state: .completed))

        #expect(slot.accessibilityLabel == "Claude · Task completed, Editing src/App.swift")
        #expect(slot.accessibilityLabel != compactAccessibilityLabel(.aiAgent))
    }

    @Test("keeps one compact slot identity while the representative session changes")
    func compactSlotIdentity() {
        let first = Self.activity(sessionID: UUID())
        let second = Self.activity(sessionID: UUID())

        #expect(aiAgentCompactSlot(for: first).id == first.compactGroupIdentity.rawValue)
        #expect(aiAgentCompactSlot(for: first).id == aiAgentCompactSlot(for: second).id)
    }

    @Test("expanded agent card stays inside the minimalist visual budget")
    func expandedViewStaysMinimal() {
        let size = aiAgentExpandedSize(hasProgress: true)

        #expect(size.width <= 280)
        #expect(size.height <= 64)
    }

    // MARK: - One card per instance, sub-agents behind it

    /// The reported defect: one OpenCode terminal delegating to four sub-agents
    /// read as five agents running.
    ///
    /// A sub-agent is a session the *agent* started, not one the user did. It
    /// belongs under the instance that spawned it, not beside it.
    @Test("folds sub-agents into the instance that spawned them")
    func foldsSubagentsIntoTheirInstance() throws {
        let root = UUID()
        let sessions: [any Activity] = [
            Self.activity(agent: .opencode, sessionID: root, state: .usingTool),
            Self.subagent(root: root, name: "explore"),
            Self.subagent(root: root, name: "general"),
        ]

        let items = expandedActivityItems(for: sessions)
        let instance = try #require(items.first?.aiAgentInstance)

        #expect(items.count == 1, "sub-agents were drawn as instances of their own")
        #expect(instance.subagents.count == 2)
        #expect(instance.root?.sessionID == root)
        #expect(instance.showsDisclosure)
    }

    /// Two terminals are two instances, however many sub-agents each fans out to.
    @Test("keeps separate instances of one agent apart")
    func keepsSeparateInstancesApart() {
        let first = UUID()
        let second = UUID()
        let items = expandedActivityItems(
            for: [
                Self.activity(agent: .opencode, sessionID: first),
                Self.subagent(root: first, name: "explore"),
                Self.activity(agent: .opencode, sessionID: second),
            ]
        )

        #expect(items.count == 2)
        #expect(items.compactMap { $0.aiAgentInstance?.subagents.count } == [1, 0])
    }

    /// A lone session has nothing to open, so it draws no control the user can
    /// click onto an empty list.
    @Test("an instance with no sub-agents offers no disclosure")
    func loneInstanceOffersNoDisclosure() throws {
        let items = expandedActivityItems(for: [Self.activity(agent: .codex)])
        let instance = try #require(items.first?.aiAgentInstance)

        #expect(instance.subagents.isEmpty)
        #expect(instance.showsDisclosure == false)
    }

    /// The whole point of the roll-up: a sub-agent blocked on a permission
    /// prompt has to reach the card without the list being opened.
    @Test("an instance speaks for its most urgent sub-agent")
    func instanceSpeaksForItsMostUrgentSubagent() throws {
        let root = UUID()
        let items = expandedActivityItems(
            for: [
                Self.activity(agent: .opencode, sessionID: root, state: .usingTool),
                Self.subagent(root: root, name: "explore", state: .working),
                Self.subagent(root: root, name: "general", state: .waitingForUser),
            ]
        )
        let instance = try #require(items.first?.aiAgentInstance)

        #expect(instance.representative.state == .waitingForUser)
        #expect(instance.representative.sessionName == "general")
    }

    /// A sub-agent's messages can land before its parent has said anything. The
    /// card still has to draw, or the island stays blank while work runs.
    @Test("an instance draws from its sub-agents alone")
    func instanceDrawsBeforeItsRootReports() throws {
        let root = UUID()
        let items = expandedActivityItems(for: [Self.subagent(root: root, name: "explore")])
        let instance = try #require(items.first?.aiAgentInstance)

        #expect(instance.root == nil)
        #expect(instance.representative.sessionName == "explore")
        #expect(instance.rootSessionID == root)
    }

    /// The panel's height has to include the rows an open card draws, or they
    /// land past the bottom of the island and onto the desktop.
    @Test("opening a card makes the panel taller by its rows")
    func openingACardGrowsThePanel() {
        let root = UUID()
        let sessions: [any Activity] = [
            Self.activity(agent: .opencode, sessionID: root, state: .usingTool),
            Self.subagent(root: root, name: "explore"),
            Self.subagent(root: root, name: "general"),
        ]
        let instance = AIAgentActivity.instanceIdentity(agent: .opencode, rootSessionID: root)
        let metrics = ExpandedItemMetrics.default

        let closed = expandedPanelSize(for: sessions, metrics: metrics)
        let open = expandedPanelSize(
            for: sessions,
            disclosedInstances: [instance],
            metrics: metrics
        )

        #expect(
            open.height - closed.height
                == aiAgentDisclosureHeight(
                    subagentCount: 2,
                    isDisclosed: true,
                    metrics: metrics.aiAgent
                )
        )
    }

    /// Opening one instance must not resize another's card.
    @Test("disclosure only grows the instance that was opened")
    func disclosureIsPerInstance() {
        let first = UUID()
        let second = UUID()
        let sessions: [any Activity] = [
            Self.activity(agent: .opencode, sessionID: first),
            Self.subagent(root: first, name: "explore"),
            Self.activity(agent: .opencode, sessionID: second),
            Self.subagent(root: second, name: "general"),
        ]
        let firstInstance = AIAgentActivity.instanceIdentity(agent: .opencode, rootSessionID: first)
        let secondInstance = AIAgentActivity.instanceIdentity(
            agent: .opencode,
            rootSessionID: second
        )

        let none = expandedPanelSize(for: sessions)
        let one = expandedPanelSize(for: sessions, disclosedInstances: [firstInstance])
        let both = expandedPanelSize(
            for: sessions,
            disclosedInstances: [firstInstance, secondInstance]
        )

        #expect(one.height > none.height)
        #expect(both.height - one.height == one.height - none.height)
    }

    /// Concurrent instances of one agent are numbered so two identical status
    /// lines are still tellable apart.
    @Test("numbers concurrent instances of the same agent")
    func numbersConcurrentInstances() {
        let first = Self.activity(agent: .opencode, sessionID: UUID())
        let second = Self.activity(agent: .opencode, sessionID: UUID())
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let items = expandedActivityItems(
            for: [second, first],
            registrationTimes: [
                first.identity: start,
                second.identity: start.addingTimeInterval(60),
            ]
        )
        let ordinals = Dictionary(
            uniqueKeysWithValues: items.compactMap { item -> (UUID, Int?)? in
                guard let instance = item.aiAgentInstance else { return nil }
                return (instance.rootSessionID, instance.ordinal)
            }
        )

        #expect(ordinals[first.sessionID] == 1)
        #expect(ordinals[second.sessionID] == 2)
    }

    /// The number follows registration, not the urgency order the list is sorted
    /// by — otherwise an instance merely changing state renumbers the cards.
    @Test("instance numbers survive a state change reordering the list")
    func instanceNumbersSurviveReordering() {
        let first = Self.activity(agent: .opencode, sessionID: UUID(), state: .usingTool)
        let second = Self.activity(agent: .opencode, sessionID: UUID(), state: .usingTool)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let times = [
            first.identity: start,
            second.identity: start.addingTimeInterval(60),
        ]

        func ordinals(_ activities: [any Activity]) -> [UUID: Int?] {
            Dictionary(
                uniqueKeysWithValues: expandedActivityItems(
                    for: activities,
                    registrationTimes: times
                )
                .compactMap { item -> (UUID, Int?)? in
                    guard let instance = item.aiAgentInstance else { return nil }
                    return (instance.rootSessionID, instance.ordinal)
                }
            )
        }

        #expect(ordinals([first, second]) == ordinals([second, first]))
    }

    /// A lone instance of an agent is not numbered: there is nothing to tell it
    /// apart from.
    @Test("a single instance of an agent carries no number")
    func singleInstanceHasNoOrdinal() throws {
        let items = expandedActivityItems(
            for: [
                Self.activity(agent: .codex, sessionID: UUID()),
                Self.activity(agent: .opencode, sessionID: UUID()),
            ]
        )

        #expect(items.allSatisfy { $0.aiAgentInstance?.ordinal == nil })
        #expect(items.count == 2)
    }

    /// The number reaches the drawn title rather than stopping at the model.
    @Test("the numbered instance names itself in its title")
    func numberedInstanceNamesItself() {
        let session = Self.activity(agent: .opencode, state: .working)

        #expect(AIAgentPresentation(activity: session).compactTitle == "OpenCode · Working…")
        #expect(
            AIAgentPresentation(activity: session, instanceOrdinal: 2).compactTitle
                == "OpenCode 2 · Working…"
        )
    }

    /// The row names the delegated agent, because "1" and "2" say nothing about
    /// which sub-agent stopped to ask something.
    @Test("a sub-agent row is named after its agent")
    func subagentRowIsNamedAfterItsAgent() {
        let named = AIAgentSubagentPresentation(
            activity: Self.subagent(root: UUID(), name: "explore", state: .waitingForUser),
            fallbackOrdinal: 1
        )

        #expect(named.title == "explore · Needs your input")
    }

    /// An agent that sends no name still has to be identifiable in the list.
    @Test("an unnamed sub-agent falls back to its position")
    func unnamedSubagentFallsBackToItsPosition() {
        let unnamed = AIAgentSubagentPresentation(
            activity: Self.subagent(root: UUID(), name: nil, state: .working),
            fallbackOrdinal: 2
        )

        #expect(unnamed.title == "Agent 2 · Working…")
    }

    // MARK: - The session-count badge

    /// A lone session draws no badge: a "1" the user has to read to learn
    /// nothing is worse than an empty corner.
    @Test("a single session draws no count badge")
    func singleSessionDrawsNoCountBadge() {
        let presentation = CompactAIAgentSlotPresentation(activity: Self.activity())

        #expect(presentation.sessionCount == 1)
        #expect(presentation.showsSessionCount == false)
    }

    /// Two sessions behind one icon is exactly the case the badge exists for.
    @Test("a second session brings out the count badge")
    func secondSessionShowsTheCountBadge() {
        let presentation = CompactAIAgentSlotPresentation(
            activity: Self.activity(),
            sessionCount: 2
        )

        #expect(presentation.showsSessionCount)
        #expect(compactAIAgentCountBadgeText(presentation.sessionCount) == "2")
    }

    /// The badge is a fixed circle, so the count is capped rather than allowed
    /// to overflow it.
    @Test("the count badge caps at nine")
    func countBadgeCapsAtNine() {
        #expect(compactAIAgentCountBadgeText(9) == "9")
        #expect(compactAIAgentCountBadgeText(10) == "9+")
        #expect(compactAIAgentCountBadgeText(147) == "9+")
    }

    /// A count below one is not a state the pill can draw; it clamps rather than
    /// rendering "0 sessions" or a negative badge.
    @Test("a nonsensical count clamps to one")
    func nonsensicalCountClampsToOne() {
        #expect(CompactAIAgentSlotPresentation(activity: Self.activity(), sessionCount: 0).sessionCount == 1)
        #expect(CompactAIAgentSlotPresentation(activity: Self.activity(), sessionCount: -3).sessionCount == 1)
    }

    /// The slot's box must not change with the count, or every icon in the pill
    /// shifts sideways the moment a second terminal opens.
    @Test("the slot box is the same size whatever the count")
    func slotBoxIsIndependentOfTheCount() {
        let sizes = AIAgentState.allCases.map {
            compactAIAgentIconSize(iconSize: 13, state: $0)
        }

        #expect(Set(sizes.map(\.width)).count == 1)
        #expect(Set(sizes.map(\.height)).count == 1)
    }

    /// The badge hangs off the icon's corner, so the box has to be wider and
    /// taller than the icon or the badge is drawn outside the slot it belongs to.
    @Test("the slot box reserves room for the badge overhang")
    func slotBoxReservesTheBadgeOverhang() {
        let iconSize: CGFloat = 13
        let metrics = CompactAIAgentMetrics.default
        let size = compactAIAgentIconSize(iconSize: iconSize, state: .working)

        #expect(size.width >= iconSize + metrics.countBadgeOverhang * 2)
        #expect(size.height == metrics.countBadgeOverhang + metrics.statusBaseline(iconSize: iconSize))
        // And still inside the pill's slot, or the icons overlap each other.
        #expect(size.width <= CompactPillMetrics.default.slotWidth)
    }

    /// Every state's indicator ends on the same line under the logo.
    ///
    /// Hanging a 3pt dot and a 7pt badge from the same *top* offset put the
    /// badge four points lower, and near the pill's rounded end those four
    /// points fell outside the silhouette — the compact shape uses `.continuous`
    /// corners, and a squircle keeps curving well past where a circular arc of
    /// the same radius would have finished.
    @Test("every status indicator ends on the same baseline")
    func statusIndicatorsShareABaseline() {
        let metrics = CompactAIAgentMetrics.default
        let iconSize: CGFloat = 13
        let baseline = metrics.statusBaseline(iconSize: iconSize)

        for diameter in [metrics.dotDiameter, metrics.badgeDiameter] {
            let offset = metrics.statusOffset(iconSize: iconSize, diameter: diameter)
            #expect(offset + diameter == baseline, "an indicator ends off the shared baseline")
        }
    }

    /// The agent slot is the tallest thing in the pill, so it is the one that
    /// decides whether anything is drawn outside the silhouette. It may not
    /// reach lower than the plain glyph every other slot draws.
    @Test("the agent slot is no taller than the pill can safely draw")
    func agentSlotStaysInsideTheSilhouette() {
        let pill = CompactPillMetrics.default
        let box = compactAIAgentIconSize(iconSize: pill.symbolSize, state: .error)
        let notch = PanelMetrics.default.compactFallbackSize

        // Centred in the pill, the column must clear the rounded ends. Half the
        // corner radius of headroom is what the working dot already had and what
        // the state badges lost when they hung four points lower.
        let headroom = (notch.height - box.height) / 2
        #expect(headroom >= 4, "the agent column reaches into the pill's curved ends")
    }

    /// The count has to reach the pill through the manager's grouping rather
    /// than being assumed by the view.
    @Test("the compact pill counts the sessions the manager grouped")
    @MainActor
    func compactPillCarriesTheGroupedSessionCount() throws {
        let manager = ActivityManager()
        manager.register(Self.activity(agent: .opencode, sessionID: UUID(), state: .usingTool))
        manager.register(
            Self.activity(agent: .opencode, sessionID: UUID(), state: .waitingForUser)
        )

        let slots = compactSlots(for: manager.compactPresentation)
        let agentSlot = try #require(slots.first { $0.aiAgentID == .opencode })

        #expect(agentSlot.accessibilityLabel.contains("2 sessions"))
    }

    /// VoiceOver has to hear the count, because the badge is the only place the
    /// other sessions exist on the compact pill.
    @Test("speaks the session count beside the state")
    func speaksTheSessionCount() {
        let slot = aiAgentCompactSlot(for: Self.activity(state: .waitingForUser), sessionCount: 3)

        #expect(slot.accessibilityLabel.contains("Needs your input"))
        #expect(slot.accessibilityLabel.contains("3 sessions"))
    }

    /// A lone session says nothing about counts.
    @Test("says nothing about counts for a lone session")
    func saysNothingAboutCountsForALoneSession() {
        let slot = aiAgentCompactSlot(for: Self.activity(state: .completed))

        #expect(slot.accessibilityLabel == "Claude · Task completed, Editing src/App.swift")
    }

    // MARK: - Accessibility

    @Test("speaks the compact line alone when there is no detail")
    func accessibilityWithoutDetail() {
        #expect(Self.presentation(state: .thinking, detail: "").accessibilityLabel == "Claude · Thinking…")
    }

    // MARK: - The primary action

    /// The action the expanded row offers has to be the one that reaches the
    /// agent's own app, and driving it must not require a window server.
    @Test("activates the originating app through the primary action")
    func primaryActionFires() {
        var fired = 0
        let view = AIAgentActivityView(activity: Self.activity()) { fired += 1 }

        view.performPrimaryAction()

        #expect(fired == 1)
    }

    @Test("offers the expanded row an action naming the agent")
    func expandedRowCarriesTheAction() {
        let rows = expandedRows(for: [Self.activity(agent: .codex)])

        #expect(rows.first?.primaryAction?.title == "Open Codex")
    }

    @Test("dedicated agent view carries the same visible action")
    func dedicatedViewCarriesAction() {
        #expect(Self.presentation(agent: .codex).primaryAction?.title == "Open Codex")
    }

    // MARK: - One status position

    /// The slot leaves room *under* the icon for the indicator.
    @Test("the slot reserves space beneath the icon")
    func slotReservesSpaceBeneathTheIcon() {
        let iconSize: CGFloat = 13
        let metrics = CompactAIAgentMetrics.default
        let size = compactAIAgentIconSize(iconSize: iconSize, state: .waitingForUser)

        #expect(size.height >= iconSize + metrics.badgeDiameter)
    }

    /// And no room *beside* it.
    ///
    /// Needing input and failing used to hang the badge off the icon's side,
    /// which needed `iconSize + badgeDiameter` of width. Staying under that is
    /// what makes "the indicator is below, not beside" a measurable property
    /// rather than a description of the code.
    @Test("the slot is too narrow to hold a badge beside the icon")
    func slotHasNoRoomForASideBadge() {
        let iconSize: CGFloat = 13
        let metrics = CompactAIAgentMetrics.default
        let sideBySide = iconSize + metrics.badgeDiameter

        for state in AIAgentState.allCases {
            let size = compactAIAgentIconSize(iconSize: iconSize, state: state)

            #expect(size.width < sideBySide, "\(state) leaves room for a side badge")
        }
    }

    /// The view has to actually use that box, or the numbers above describe
    /// nothing. Asserted on the source because a SwiftUI body cannot be
    /// measured without a window server.
    @Test("the compact agent icon is laid out from the shared box")
    func compactIconUsesTheSharedBox() throws {
        let source = try Self.agentActivityViewSource()

        #expect(source.contains("compactAIAgentIconSize(iconSize: iconSize, state: presentation.state)"))
        #expect(
            source.contains(
                "statusIndicator\n                .offset(y: metrics.statusOffset(iconSize: iconSize, diameter: statusDiameter))"
            )
        )
    }
}
