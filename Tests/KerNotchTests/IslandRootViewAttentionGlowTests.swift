import AppKit
import Foundation
import SwiftUI
import Testing

@testable import KerNotch
@testable import KerNotchCore
@testable import KerNotchUI

/// The glow belongs to the small island only: the expanded island already
/// shows the agent's card, and a hidden panel has nothing to light.
@Suite("IslandRootView attention glow")
@MainActor
struct IslandRootViewAttentionGlowTests {
    @Test("the compact island draws the glow")
    func compactIslandDrawsTheGlow() {
        #expect(Self.rendersGlow(in: .compact))
    }

    @Test("the expanded island draws no glow")
    func expandedIslandDrawsNoGlow() {
        #expect(Self.rendersGlow(in: .expanded) == false)
    }

    @Test("a hidden island draws no glow")
    func hiddenIslandDrawsNoGlow() {
        #expect(Self.rendersGlow(in: .hidden) == false)
    }

    private static func rendersGlow(in state: PresentationState) -> Bool {
        let model = IslandViewModel(
            compact: ActivityManager().compactPresentation,
            notchSize: CGSize(width: 200, height: 32)
        )
        model.state = state
        model.attentionGlow = IslandAttentionGlow(
            sessionIdentity: ActivityIdentity("kernotch.ai.claude-code.session"),
            reason: .needsInput,
            startedAt: Date()
        )

        let hostingView = NSHostingView(rootView: IslandRootView(model: model))
        hostingView.frame = CGRect(x: 0, y: 0, width: 640, height: 260)
        hostingView.layoutSubtreeIfNeeded()
        return containsView(named: "AttentionGlowHostView", in: hostingView)
    }

    private static func containsView(named name: String, in view: NSView) -> Bool {
        if String(describing: type(of: view)).contains(name) {
            return true
        }
        return view.subviews.contains { containsView(named: name, in: $0) }
    }
}
