import AppKit
import CoreGraphics
import SwiftUI
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// How the pet holds up on screen: sampled pixel for pixel, unscaled by the
/// hover peek, and standing still when the user asked for less motion.
@Suite("Island pet on screen", .serialized)
@MainActor
struct IslandPetScreenTests {
    /// Shown pixel for pixel on a Retina panel, the art is never magnified;
    /// halved on a 1x display, it is averaged rather than thinned out.
    @Test("the art is sampled pixel for pixel, and averaged when halved")
    func artSampling() {
        let host = PetLayerHostView(frame: CGRect(origin: .zero, size: PetFixtures.placement.canvasSize))

        #expect(host.sprite.magnificationFilter == .nearest)
        #expect(host.sprite.minificationFilter == .linear)
    }

    /// The peek scales the whole island; the pet's art must stay one image
    /// pixel per device pixel through it, or the dog is resampled while the
    /// pointer rests on the island.
    @Test("the hover peek moves the pet but leaves it at its own size", arguments: [1.03, 1.5])
    func peekLeavesThePetUnscaled(peekScale: CGFloat) throws {
        let stage = IslandPetStage(pet: PetFixtures.roamingPresentation(), pillHeight: 32, metrics: .default)
            .environment(\.islandMotionSuspended, true)
            .environment(\.islandHoverScale, peekScale)
            .frame(width: 200, height: 60, alignment: .topLeading)
            .scaleEffect(peekScale, anchor: .top)
        let hostingView = NSHostingView(rootView: stage)
        let window = PetFixtures.windowed(hostingView, size: CGSize(width: 200, height: 60))
        defer { window.close() }
        let host = try #require(PetFixtures.petHost(in: hostingView))
        let onScreen = host.convert(host.bounds, to: nil)

        #expect(abs(onScreen.width - host.bounds.width) < 0.01)
        #expect(abs(onScreen.height - host.bounds.height) < 0.01)
    }

    @Test("the peek's counter-scale undoes the peek", arguments: [1.0, 1.03, 1.5, 0.92])
    func counterScaleUndoesThePeek(scale: CGFloat) {
        #expect(abs(scale * islandPeekCounterScale(for: scale) - 1) < 0.000_001)
    }

    /// KerNotch's own Motion choice outranks the system's either way, which
    /// is what makes both answers testable on any machine.
    @Test("KerNotch's own Motion choice decides whether the pet may move", arguments: [true, false])
    func motionChoiceReachesThePet(reducesMotion: Bool) throws {
        let view = IslandPetView(presentation: PetFixtures.roamingPresentation(), placement: PetFixtures.placement)
            .environment(\.islandReducedMotionOverride, reducesMotion)
        let hostingView = NSHostingView(rootView: view)
        let window = PetFixtures.windowed(hostingView, size: PetFixtures.placement.canvasSize)
        defer { window.close() }
        let host = try #require(PetFixtures.petHost(in: hostingView))

        #expect((host.sprite.animationKeys() ?? []).isEmpty == reducesMotion)
    }
}
