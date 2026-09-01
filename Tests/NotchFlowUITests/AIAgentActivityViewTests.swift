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
        state: AIAgentState = .working,
        detail: String = "Editing src/App.swift",
        toolName: String? = nil,
        progress: Double? = nil
    ) -> AIAgentActivity {
        AIAgentActivity(
            agent: agent,
            sessionID: UUID(
                uuid: (0x6F, 0x96, 0x19, 0xFF, 0x8B, 0x86, 0xD0, 0x11, 0xB4, 0x2D, 0x00, 0xC0, 0x4F, 0xC9, 0x64, 0xFF)
            ),
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

    @Test("compact slots carry the originating agent logo identity")
    func compactSlotUsesAgentIdentity() {
        for agent in IPCAgentID.allCases {
            let slot = aiAgentCompactSlot(for: Self.activity(agent: agent, state: .error))

            #expect(slot.aiAgentID == agent)
        }
    }

    @Test("compact activity routing preserves the agent logo identity")
    func compactActivityRoutingUsesAgentIdentity() throws {
        let manager = ActivityManager()
        manager.register(Self.activity(agent: .codex))

        let slot = try #require(compactSlots(for: manager.compactPresentation).first)

        #expect(slot.aiAgentID == .codex)
    }

    @Test("announces the state and detail rather than the generic kind label")
    func compactSlotAnnouncesTheState() {
        let slot = aiAgentCompactSlot(for: Self.activity(state: .completed))

        #expect(slot.accessibilityLabel == "Claude · Task completed, Editing src/App.swift")
        #expect(slot.accessibilityLabel != compactAccessibilityLabel(.aiAgent))
    }

    @Test("keeps the slot identity aligned with the activity's")
    func compactSlotIdentity() {
        let activity = Self.activity()

        #expect(aiAgentCompactSlot(for: activity).id == activity.identity.rawValue)
    }

    @Test("expanded agent card stays inside the minimalist visual budget")
    func expandedViewStaysMinimal() {
        let size = aiAgentExpandedSize(hasProgress: true)

        #expect(size.width <= 280)
        #expect(size.height <= 64)
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
}
