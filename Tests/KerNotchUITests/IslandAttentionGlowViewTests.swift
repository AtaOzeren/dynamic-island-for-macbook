import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// Where the glow is drawn and how it moves, checked as values: the rim's
/// position in layer space, the beat of the travelling light, and that the
/// motion is Core Animation's rather than a per-frame SwiftUI driver's.
@Suite("IslandAttentionGlowView")
@MainActor
struct IslandAttentionGlowViewTests {
    private static let surfaceSize = CGSize(width: 300, height: 32)
    private static let padding = IslandAttentionGlowMetrics.haloPadding

    @Test("the canvas leaves halo room on the sides and below, none above")
    func canvasLeavesRoomBesideAndBelow() {
        let geometry = IslandAttentionGlowGeometry(surfaceSize: Self.surfaceSize)

        #expect(geometry.canvasSize.width == Self.surfaceSize.width + 2 * Self.padding)
        #expect(geometry.canvasSize.height == Self.surfaceSize.height + Self.padding)
    }

    /// The top of the island is the top of the screen. The rim must start and
    /// end there, run along the island's bottom, and never trace the top edge
    /// across the menu bar.
    @Test("the rim runs down the sides and along the bottom, never across the top")
    func rimFollowsTheOpenOutline() {
        let geometry = IslandAttentionGlowGeometry(surfaceSize: Self.surfaceSize)
        let path = geometry.rimPath()
        let points = Self.endPoints(of: path)

        #expect(points.first == CGPoint(x: Self.padding, y: geometry.canvasSize.height))
        #expect(points.last == CGPoint(x: Self.padding + Self.surfaceSize.width, y: geometry.canvasSize.height))
        #expect(abs(path.boundingBoxOfPath.minY - Self.padding) < 0.001, "the bottom edge sits above the halo room")
        #expect(Self.elements(of: path).contains(.closeSubpath) == false)
    }

    @Test("an empty island has no rim")
    func emptyIslandHasNoRim() {
        #expect(IslandAttentionGlowGeometry(surfaceSize: .zero).rimPath().isEmpty)
    }

    @Test("each pass crosses the island once, then waits for the next")
    func travellingLightBeat() throws {
        let animation = IslandAttentionGlowAnimation.travellingLight(Self.progress(elapsed: 0), now: 100)
        let values = try #require(animation.values as? [[NSNumber]])

        #expect(animation.keyPath == "locations")
        #expect(animation.duration == 5, "a two-second crossing and the three-second rest after it")
        #expect(animation.repeatCount == 5)
        #expect(animation.keyTimes?.map(\.doubleValue) == [0, 2.0 / 5, 1])
        #expect(values.count == 3)
        #expect(values[0].allSatisfy { $0.doubleValue <= 0 }, "a pass starts wholly off the left edge")
        #expect(values[1].allSatisfy { $0.doubleValue >= 1 }, "a pass ends wholly off the right edge")
        #expect(values[1] == values[2], "the light waits off the right edge until the next pass")
    }

    /// A glow redrawn mid-sequence — the island collapsing back to compact —
    /// joins the beat where it stands instead of starting five new passes.
    @Test("a glow drawn mid-sequence resumes where the sequence stands")
    func resumesMidSequence() {
        #expect(IslandAttentionGlowAnimation.travellingLight(Self.progress(elapsed: 7), now: 100).beginTime == 93)
        #expect(IslandAttentionGlowAnimation.pulse(Self.progress(elapsed: 4), now: 50).beginTime == 46)
    }

    /// The Settings test button shows one crossing, not an agent's five.
    @Test("the test button's glow crosses the island once")
    func previewCrossesOnce() {
        let preview = IslandAttentionGlow.preview(startedAt: Self.start)
        let progress = IslandAttentionGlowProgress(glow: preview, at: Self.start)

        #expect(preview.passCount == 1)
        #expect(preview.endsAt == Self.start.addingTimeInterval(IslandAttentionGlowTiming.passDuration))
        #expect(IslandAttentionGlowAnimation.travellingLight(progress, now: 0).repeatCount == 1)
        #expect(IslandAttentionGlowProgress(glow: preview, at: Self.start.addingTimeInterval(2)).isFinished)
    }

    @Test("an agent's glow runs its full five crossings")
    func agentGlowCrossesFiveTimes() {
        let glow = IslandAttentionGlow(
            sessionIdentity: ActivityIdentity("session"),
            reason: .failed,
            startedAt: Self.start
        )
        let progress = IslandAttentionGlowProgress(glow: glow, at: Self.start)

        #expect(glow.passCount == 5)
        #expect(IslandAttentionGlowAnimation.pulse(progress, now: 0).repeatCount == 5)
        #expect(IslandAttentionGlowProgress(glow: glow, at: Self.start.addingTimeInterval(21.9)).isFinished == false)
    }

    @Test("under Reduce Motion the rim fades in place on the same beat")
    func pulseKeepsTheBeatWithoutTravel() throws {
        let animation = IslandAttentionGlowAnimation.pulse(Self.progress(elapsed: 0), now: 0)
        let values = try #require(animation.values as? [Double])

        #expect(animation.keyPath == "opacity")
        #expect(values == [0, 1, 0, 0])
        #expect(animation.duration == 5)
        #expect(animation.repeatCount == 5)
    }

    @Test("the light's stops rise across its width")
    func lightStopsAreOrdered() {
        let stops = IslandAttentionGlowAnimation.lightLocations(leadingEdgeAt: 0.25).map(\.doubleValue)

        #expect(stops == stops.sorted())
        #expect(abs((stops.last ?? 0) - (stops.first ?? 0) - IslandAttentionGlowMetrics.lightWidthFraction) < 0.0001)
    }

    @Test("the glow uses the pill badge's own colours")
    func glowTonesMatchTheBadges() {
        #expect(IslandAttentionGlow.Reason.completed.badgeTone == AIAgentCompactIndicator(state: .completed).badgeTone)
        #expect(
            IslandAttentionGlow.Reason.needsInput.badgeTone == AIAgentCompactIndicator(state: .waitingForUser).badgeTone
        )
        #expect(IslandAttentionGlow.Reason.failed.badgeTone == AIAgentCompactIndicator(state: .error).badgeTone)
    }

    @Test("the glow draws its Core Animation host while it runs")
    func glowRendersItsLayerHost() {
        let glow = IslandAttentionGlow(
            sessionIdentity: ActivityIdentity("session"),
            reason: .needsInput,
            startedAt: Date()
        )
        let hostingView = NSHostingView(rootView: IslandAttentionGlowView(glow: glow, surfaceSize: Self.surfaceSize))
        hostingView.frame = CGRect(x: 0, y: 0, width: 400, height: 80)
        hostingView.layoutSubtreeIfNeeded()

        #expect(Self.containsView(named: "AttentionGlowHostView", in: hostingView))
    }

    /// Per-frame SwiftUI animation in the island costs a measure-and-layout pass
    /// every frame; the glow's motion has to live in Core Animation.
    @Test("the glow is not driven frame by frame from SwiftUI")
    func glowIsNotClockDriven() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/KerNotchUI/IslandAttentionGlowView.swift"),
            encoding: .utf8
        )

        for driver in ["TimelineView(", "PhaseAnimator(", ".repeatForever(", "Timer."] {
            #expect(!source.contains(driver), "\(driver) would redraw the island every frame")
        }
        #expect(source.contains(#"CAKeyframeAnimation(keyPath: "locations")"#))
    }

    private static let start = Date(timeIntervalSinceReferenceDate: 7_000)

    /// An agent's five-crossing glow, `elapsed` seconds in.
    private static func progress(elapsed: TimeInterval) -> IslandAttentionGlowProgress {
        let glow = IslandAttentionGlow(
            sessionIdentity: ActivityIdentity("session"),
            reason: .needsInput,
            startedAt: start
        )
        return IslandAttentionGlowProgress(glow: glow, at: start.addingTimeInterval(elapsed))
    }

    private static func elements(of path: CGPath) -> [CGPathElementType] {
        var types: [CGPathElementType] = []
        path.applyWithBlock { types.append($0.pointee.type) }
        return types
    }

    private static func endPoints(of path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            let pointCount: Int
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: pointCount = 1
            case .addQuadCurveToPoint: pointCount = 2
            case .addCurveToPoint: pointCount = 3
            case .closeSubpath: pointCount = 0
            @unknown default: pointCount = 0
            }
            guard pointCount > 0 else { return }
            points.append(element.pointee.points[pointCount - 1])
        }
        return points
    }

    private static func containsView(named name: String, in view: NSView) -> Bool {
        if String(describing: type(of: view)).contains(name) {
            return true
        }
        return view.subviews.contains { containsView(named: name, in: $0) }
    }
}
