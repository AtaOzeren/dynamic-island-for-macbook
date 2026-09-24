import AppKit
import Foundation
import SwiftUI
import Testing

@testable import KerNotch
@testable import KerNotchCore
@testable import KerNotchUI

/// The pet lives on the island whether it is compact or open — on the open
/// island in the strip beside the notch — and a hidden panel has nothing to
/// draw.
@Suite("IslandRootView pet")
@MainActor
struct IslandRootViewPetTests {
    @Test("the compact island draws the pet")
    func compactIslandDrawsThePet() {
        #expect(Self.rendersPet(in: .compact))
    }

    @Test("the open island draws the pet too")
    func expandedIslandDrawsThePet() {
        #expect(Self.rendersPet(in: .expanded))
    }

    @Test("a hidden island draws no pet")
    func hiddenIslandDrawsNoPet() {
        #expect(Self.rendersPet(in: .hidden) == false)
    }

    @Test("the model sizes the pill with the pet it draws")
    func extentFollowsThePet() {
        let model = Self.model(state: .compact)
        let withPet = islandCompactPillGeometry(model.extentInput).size.width
        model.pet = nil
        let without = islandCompactPillGeometry(model.extentInput).size.width

        #expect(withPet > without)
    }

    private static func model(state: PresentationState) -> IslandViewModel {
        let model = IslandViewModel(
            compact: ActivityManager().compactPresentation,
            notchSize: CGSize(width: 200, height: 32),
            layout: .minimalist
        )
        model.state = state
        var tracker = PetRoutineTracker()
        var dice = PetDice(seed: 1)
        tracker.follow(
            PetScene(stage: .roaming, geometry: IslandPet.shiba.stageGeometry()),
            at: ProcessInfo.processInfo.systemUptime,
            dice: &dice
        )
        model.pet = tracker.performance.map { IslandPetPresentation(pet: .shiba, performance: $0) }
        return model
    }

    private static func rendersPet(in state: PresentationState) -> Bool {
        let hostingView = NSHostingView(rootView: IslandRootView(model: model(state: state)))
        hostingView.frame = CGRect(x: 0, y: 0, width: 640, height: 260)
        hostingView.layoutSubtreeIfNeeded()
        return containsView(named: "PetLayerHostView", in: hostingView)
    }

    private static func containsView(named name: String, in view: NSView) -> Bool {
        if String(describing: type(of: view)).contains(name) {
            return true
        }
        return view.subviews.contains { containsView(named: name, in: $0) }
    }
}
