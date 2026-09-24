import AppKit
import Foundation

@testable import KerNotchCore
@testable import KerNotchUI

/// What the suites that draw the pet share.
@MainActor
enum PetFixtures {
    static let placement = PetPlacement(pet: .shiba, pillHeight: 32, metrics: .default)

    /// The Shiba roaming an empty flank, having just walked on.
    static func roamingPresentation() -> IslandPetPresentation {
        let geometry = IslandPet.shiba.stageGeometry()
        let routine = PetRoutine(
            stage: .roaming,
            from: PetPose(position: geometry.offstagePosition, facing: .right, frame: .stand),
            geometry: geometry
        )
        return IslandPetPresentation(
            pet: .shiba,
            performance: PetPerformance(routine: routine, startedAt: ProcessInfo.processInfo.systemUptime)
        )
    }

    /// The view that hosts the pet's layer, wherever SwiftUI put it.
    static func petHost(in view: NSView) -> PetLayerHostView? {
        if let host = view as? PetLayerHostView {
            return host
        }
        return view.subviews.lazy.compactMap { petHost(in: $0) }.first
    }

    /// `view` in a borderless window that is never shown, laid out and drawn
    /// once, so its platform views have landed in a window.
    static func windowed(_ hostingView: NSView, size: CGSize) -> NSWindow {
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        // Closed by the test while it still holds the window.
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        return window
    }
}
