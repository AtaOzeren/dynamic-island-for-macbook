import AppKit
import Foundation
import SwiftUI
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// KerNotch's own Motion choice in General reaches every island animation, not
/// only the transitions' curves.
///
/// An explicit choice outranks the system's Reduce Motion either way, which is
/// what makes both answers testable on any machine: the system setting cannot
/// be changed from a test, but it no longer decides.
@Suite("Island reduced motion")
@MainActor
struct IslandReducedMotionTests {
    @Test(
        "an explicit Motion choice wins over the system, and without one the system decides",
        arguments: [
            (false, nil as Bool?, false),
            (true, nil, true),
            (false, true, true),
            (true, false, false),
        ]
    )
    func choiceOverridesTheSystem(system: Bool, override: Bool?, reduces: Bool) {
        #expect(islandReducesMotion(system: system, override: override) == reduces)
    }

    @Test("the island's reduced motion reads the choice through the environment", arguments: [true, false])
    func environmentCarriesTheChoice(reduces: Bool) {
        var environment = EnvironmentValues()
        environment.islandReducedMotionOverride = reduces

        #expect(environment.prefersReducedIslandMotion == reduces)
    }

    @Test("without a choice the island follows the system")
    func noChoiceFollowsTheSystem() {
        let environment = EnvironmentValues()

        #expect(environment.islandReducedMotionOverride == nil)
        #expect(environment.prefersReducedIslandMotion == environment.accessibilityReduceMotion)
    }

    @Test("the equaliser moves or stands still as the Motion choice says", arguments: [true, false])
    func equaliserFollowsTheChoice(reduces: Bool) {
        let manager = ActivityManager()
        manager.register(
            MusicActivity(
                nowPlaying: NowPlaying(
                    title: "Windowlicker",
                    artist: "Aphex Twin",
                    playbackState: .playing,
                    sourceApplicationName: "Spotify"
                )
            )
        )
        let view = CompactActivityView(
            presentation: manager.compactPresentation,
            notchSize: CGSize(width: 200, height: 32)
        )
        .environment(\.islandReducedMotionOverride, reduces)

        #expect(Self.renders("MusicEqualiserHostView", in: view) == !reduces)
    }

    @Test("the agent's working dot moves or stands still as the Motion choice says", arguments: [true, false])
    func workingDotFollowsTheChoice(reduces: Bool) {
        let icon = CompactAIAgentIcon(
            presentation: CompactAIAgentSlotPresentation(
                activity: AIAgentActivity(
                    agent: .claudeCode,
                    sessionID: UUID(),
                    state: .working,
                    detail: "Editing src/App.swift"
                )
            ),
            iconSize: 13
        )
        .environment(\.islandReducedMotionOverride, reduces)

        #expect(Self.renders("WorkingDotHostView", in: icon) == !reduces)
    }

    /// Reading `accessibilityReduceMotion` directly is how the equaliser, the
    /// glow and the working dot came to ignore the user's choice. Only the one
    /// place that combines the two may read it.
    @Test("no island view reads the system's Reduce Motion directly")
    func onlyOnePlaceReadsTheSystemSetting() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/KerNotchUI")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "IslandReducedMotion.swift" }

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(
                source.contains("@Environment(\\.accessibilityReduceMotion)") == false,
                "\(file.lastPathComponent) reads the system setting instead of the island's"
            )
        }
    }

    private static func renders(_ viewName: String, in view: some View) -> Bool {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 64)
        hostingView.layoutSubtreeIfNeeded()
        return contains(viewName, in: hostingView)
    }

    private static func contains(_ viewName: String, in view: NSView) -> Bool {
        if String(describing: type(of: view)).contains(viewName) {
            return true
        }
        return view.subviews.contains { contains(viewName, in: $0) }
    }
}
