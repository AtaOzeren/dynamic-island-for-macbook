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

    /// The `NSPanel` frame is allocated once and never resized, so a view that
    /// measured past it would be silently clipped.
    @Test("clamps the expanded size to the window's allocation")
    func expandedSizeIsClamped() {
        let panelMetrics = PanelMetrics(
            maximumExpandedSize: CGSize(width: 100, height: 20),
            minimumBottomInset: 120
        )
        let size = aiAgentExpandedSize(hasProgress: true, panelMetrics: panelMetrics)

        #expect(size.width <= 100)
        #expect(size.height <= 20)
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

    // MARK: - The compact slot

    @Test("normalizes Codex artwork to the OpenCode icon footprint")
    func normalizesCodexArtworkSize() {
        #expect(aiAgentIconArtworkScale(for: .claudeCode) == 1)
        #expect(aiAgentIconArtworkScale(for: .opencode) == 1)
        #expect(aiAgentIconArtworkScale(for: .codex) == 1.24)
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

    @Test("completed compact status keeps the five-second activity lifetime")
    func compactCompletedLifetime() {
        let slot = aiAgentCompactSlot(for: Self.activity(state: .completed))

        #expect(slot.aiAgentPresentation?.indicator == .completed)
        #expect(AIAgentActivity.completedAutoDismissAfter == .seconds(5))
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

    @Test("groups concurrent sessions from one agent into one expanded item")
    func expandedItemsGroupAgentSessions() throws {
        let first = Self.activity(
            agent: .opencode,
            sessionID: UUID(),
            detail: "Editing first project"
        )
        let second = Self.activity(
            agent: .opencode,
            sessionID: UUID(),
            detail: "Running second project"
        )

        let items = expandedActivityItems(for: [first, second])
        let group = try #require(items.first?.aiAgentGroup)

        #expect(items.count == 1)
        #expect(group.agentID == .opencode)
        #expect(group.sessions.map(\.sessionID) == [first.sessionID, second.sessionID])
        #expect(group.showsDisclosure)
    }

    @Test("does not combine different agents in the expanded panel")
    func expandedItemsKeepAgentsSeparate() {
        let items = expandedActivityItems(
            for: [
                Self.activity(agent: .opencode, sessionID: UUID()),
                Self.activity(agent: .opencode, sessionID: UUID()),
                Self.activity(agent: .codex, sessionID: UUID()),
            ]
        )

        #expect(items.count == 2)
        #expect(items.compactMap { $0.aiAgentGroup?.agentID } == [.opencode, .codex])
    }

    @Test("uses recording-row height until a multi-session group is disclosed")
    func expandedAgentGroupDisclosureHeight() {
        let sessions: [any Activity] = [
            Self.activity(agent: .opencode, sessionID: UUID()),
            Self.activity(agent: .opencode, sessionID: UUID()),
        ]
        let metrics = ExpandedItemMetrics.default
        let collapsed = expandedPanelSize(for: sessions, metrics: metrics)
        let disclosed = expandedPanelSize(
            for: sessions,
            disclosedAgentIDs: [.opencode],
            metrics: metrics
        )

        #expect(
            collapsed.height
                == metrics.panel.rowHeight + metrics.panel.contentInset * 2
        )
        #expect(disclosed.height > collapsed.height)
        #expect(
            disclosed.height - collapsed.height
                == AIAgentGroupViewMetrics.default.separatorHeight
                + AIAgentGroupViewMetrics.default.detailRowHeight * 2
        )
        #expect(disclosed.height <= PanelMetrics.default.maximumExpandedSize.height)
    }

    @Test("single-session groups show no disclosure control")
    func singleAgentSessionHasNoDisclosure() throws {
        let item = try #require(
            expandedActivityItems(for: [Self.activity(agent: .codex)]).first
        )

        #expect(item.aiAgentGroup?.showsDisclosure == false)
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
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/NotchFlowUI/AIAgentActivityView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("compactAIAgentIconSize(iconSize: iconSize, state: presentation.state)"))
        #expect(source.contains("statusIndicator\n                .offset(y: iconSize + 1)"))
    }
}
