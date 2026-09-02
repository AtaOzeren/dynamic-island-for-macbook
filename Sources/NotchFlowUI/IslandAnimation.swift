import AppKit
import CoreGraphics
import SwiftUI

/// The island's motion budget, straight from the animation table in
/// `docs/04-overlay-window.md`. Every duration the island animates with comes
/// from here, so retuning the island's feel is one edit rather than a sweep
/// through the view layer.
public struct IslandMotion: Equatable, Sendable {
    public static let `default` = IslandMotion()

    /// Spring response for expand and collapse. Tuned to feel snappy without
    /// the overshoot that would visually collide with the notch's hard edges.
    public let springResponse: Double
    /// Spring damping for expand and collapse. Below ~0.8 the pill visibly
    /// bounces past the notch cutout, which reads as a rendering glitch rather
    /// than as motion.
    public let springDamping: Double
    /// Hover peek. Short enough to read as hover feedback rather than as a
    /// committed state change.
    public let peekDuration: Double
    /// The Reduce Motion substitute. Not zero: `docs/04-overlay-window.md`
    /// removes the motion component of a transition but never skips the
    /// transition outright, because the state still has to visually change.
    public let reducedMotionCrossFadeDuration: Double
    /// How long the pointer must rest on the pill before it expands. Hover is
    /// the only gesture that opens the island, so this is what separates a
    /// deliberate rest from a pointer crossing the notch on its way elsewhere.
    public let hoverExpansionDelay: Double
    /// How long the expanded island waits after the pointer leaves before it
    /// collapses.
    ///
    /// The panel is a target the pointer has to travel to, and the path from the
    /// notch to a row crosses the island's own edge. Collapsing the instant the
    /// pointer slipped off meant a hand that overshot had to start the hover
    /// again from scratch. Coming back inside the grace period simply cancels
    /// the collapse — the island never closes, so there is nothing to reopen and
    /// nothing to flicker.
    public let hoverCollapseGrace: Double

    public init(
        springResponse: Double = 0.35,
        springDamping: Double = 0.8,
        peekDuration: Double = 0.15,
        reducedMotionCrossFadeDuration: Double = 0.1,
        hoverExpansionDelay: Double = 0.25,
        hoverCollapseGrace: Double = 0.5
    ) {
        self.springResponse = springResponse
        self.springDamping = springDamping
        self.peekDuration = peekDuration
        self.reducedMotionCrossFadeDuration = reducedMotionCrossFadeDuration
        self.hoverExpansionDelay = hoverExpansionDelay
        self.hoverCollapseGrace = hoverCollapseGrace
    }
}

/// How a single island transition is drawn.
///
/// Modelled as a value rather than as a SwiftUI `Animation` so the policy that
/// picks it is a pure function a test can assert on without a screen — the
/// zero-animation-while-hidden rule in `docs/02-performance-contract.md` is only
/// enforceable if `.none` is an inspectable outcome.
public enum IslandAnimationCurve: Equatable, Sendable {
    /// No animation at all. The state change is applied in one frame and no
    /// CoreAnimation work is scheduled.
    case none
    /// The primary expand/collapse spring.
    case spring(response: Double, dampingFraction: Double)
    /// The hover peek.
    case easeOut(duration: Double)
    /// The Reduce Motion substitute: opacity only, no geometry travel.
    case crossFade(duration: Double)

    /// The SwiftUI animation to apply, or `nil` to apply the change without one.
    ///
    /// `nil` rather than a zero-duration animation because a zero-duration
    /// `Animation` still enters the animation machinery for a frame, which is
    /// exactly the idle work a resting compact or hidden state must avoid.
    public var animation: Animation? {
        switch self {
        case .none:
            nil
        case .spring(let response, let dampingFraction):
            .spring(response: response, dampingFraction: dampingFraction)
        case .easeOut(let duration):
            .easeOut(duration: duration)
        case .crossFade(let duration):
            .linear(duration: duration)
        }
    }

    /// Whether this curve moves geometry rather than only opacity. The signal a
    /// Reduce Motion assertion checks, since the accessibility setting bans
    /// travel, not change.
    public var movesGeometry: Bool {
        switch self {
        case .spring, .easeOut: true
        case .none, .crossFade: false
        }
    }
}

/// The curve for a transition between two presentation states.
///
/// Any transition with `hidden` at either end is unanimated. Ordering out must
/// leave nothing running behind it, and an activity arriving while hidden orders
/// the window in at its resting compact geometry first — only a *later* state
/// change animates. That is the whole of the idle-animation budget in
/// `docs/02-performance-contract.md`, expressed as one rule.
public func islandAnimationCurve(
    from oldState: PresentationState,
    to newState: PresentationState,
    motion: IslandMotion = .default,
    reduceMotion: Bool = false
) -> IslandAnimationCurve {
    guard oldState != newState else { return .none }
    guard oldState != .hidden, newState != .hidden else { return .none }
    guard reduceMotion == false else {
        return .crossFade(duration: motion.reducedMotionCrossFadeDuration)
    }
    return .spring(response: motion.springResponse, dampingFraction: motion.springDamping)
}

/// The curve for the pill peeking under the pointer.
///
/// Peek is a compact-only affordance: expanded content is already at full
/// detail, and a hidden window has nothing to peek. Both cases fall through to
/// `.none` rather than animating something the user cannot see.
public func islandPeekCurve(
    in state: PresentationState,
    motion: IslandMotion = .default,
    reduceMotion: Bool = false
) -> IslandAnimationCurve {
    guard state == .compact else { return .none }
    guard reduceMotion == false else {
        return .crossFade(duration: motion.reducedMotionCrossFadeDuration)
    }
    return .easeOut(duration: motion.peekDuration)
}

/// The seam between the island's animation policy and the system's Reduce Motion
/// setting. Production reads `NSWorkspace`; tests substitute a fake so both
/// branches are assertable without touching System Settings.
@MainActor
public protocol ReduceMotionQuerying: Sendable {
    var prefersReducedMotion: Bool { get }
}

/// Reads Reduce Motion from `NSWorkspace` at the moment a transition is about to
/// start.
///
/// Queried on demand rather than observed, because a transition is the only
/// thing that can consume the answer: subscribing would keep a live registration
/// alive across the hidden state to learn something nothing is asking for.
@MainActor
public struct SystemReduceMotion: ReduceMotionQuerying {
    public init() {}

    public var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Runtime motion preference: explicit user choice wins, `nil` follows macOS.
@MainActor
public final class ConfigurableReduceMotion: ReduceMotionQuerying {
    private var preferenceOverride: Bool?
    private let system: any ReduceMotionQuerying

    public init(
        override preferenceOverride: Bool?,
        system: any ReduceMotionQuerying = SystemReduceMotion()
    ) {
        self.preferenceOverride = preferenceOverride
        self.system = system
    }

    public var prefersReducedMotion: Bool {
        preferenceOverride ?? system.prefersReducedMotion
    }

    public func updateOverride(_ preferenceOverride: Bool?) {
        self.preferenceOverride = preferenceOverride
    }
}
