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
    /// How long the island's own shape moves before its contents follow it.
    ///
    /// The shape and what is drawn inside it used to move on two different
    /// clocks — the icons animated, the black surface behind them jumped — so
    /// an icon arriving looked like the island snapping wider and the glyph
    /// catching up afterwards. They now share one curve, and this is the only
    /// thing left between them: enough for the island to visibly lead, far too
    /// little to read as a second movement.
    public let contentLead: Double
    /// How much the pill grows under the pointer.
    ///
    /// Scale is the peek's only signal. The pill used to dim to 94% as well,
    /// which let the desktop show through what has to read as the notch's own
    /// black — so hovering made the island visibly grey beside the hardware.
    public let peekScale: CGFloat

    public init(
        springResponse: Double = 0.35,
        springDamping: Double = 0.8,
        peekDuration: Double = 0.15,
        reducedMotionCrossFadeDuration: Double = 0.1,
        hoverExpansionDelay: Double = 0.25,
        hoverCollapseGrace: Double = 0.5,
        contentLead: Double = 0.08,
        peekScale: CGFloat = 1.03
    ) {
        self.springResponse = springResponse
        self.springDamping = springDamping
        self.peekDuration = peekDuration
        self.reducedMotionCrossFadeDuration = reducedMotionCrossFadeDuration
        self.hoverExpansionDelay = hoverExpansionDelay
        self.hoverCollapseGrace = hoverCollapseGrace
        self.contentLead = contentLead
        self.peekScale = peekScale
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

/// Which way a change moves the island.
public enum IslandExtentChange: Equatable, Sendable {
    case growing
    case shrinking
}

/// Whether a change makes the island bigger or smaller.
///
/// Either axis counts. A pill that gains an icon grows sideways and an expanded
/// panel that gains a card grows downwards, and both are the island opening up
/// to make room for something new.
public func islandExtentChange(from oldSize: CGSize, to newSize: CGSize) -> IslandExtentChange {
    let grew = newSize.width > oldSize.width || newSize.height > oldSize.height
    return grew ? .growing : .shrinking
}

/// How one change to what the island shows is drawn: the island's own shape and
/// its contents, on one curve, a hair apart.
///
/// Which of the two waits is the whole point. Opening, the shape goes first, so
/// an icon never appears in a space the island has not made yet. Closing, the
/// contents go first, so the shape never closes across something still drawn
/// inside it — which is what used to clip a leaving icon in half.
public struct IslandContentMotion: Equatable, Sendable {
    /// No animation at all, for a hidden or degraded island.
    public static let still = IslandContentMotion(curve: .none, lead: 0, change: .growing)

    public let curve: IslandAnimationCurve
    public let lead: Double
    public let change: IslandExtentChange

    public init(curve: IslandAnimationCurve, lead: Double, change: IslandExtentChange) {
        self.curve = curve
        self.lead = lead
        self.change = change
    }

    /// The island's own shape: its surface, the mask that clips its contents,
    /// and its offset onto the notch.
    public var container: Animation? { animation(delayedBy: containerDelay) }

    /// What is drawn inside it: the pill's icons, the panel's cards.
    public var content: Animation? { animation(delayedBy: contentDelay) }

    public var containerDelay: Double { change == .shrinking ? effectiveLead : 0 }

    public var contentDelay: Double { change == .growing ? effectiveLead : 0 }

    /// The same motion for a change in the other direction — what a control
    /// inside the island uses, since it knows which way it is about to move
    /// before anything has moved.
    public func changing(to change: IslandExtentChange) -> Self {
        Self(curve: curve, lead: lead, change: change)
    }

    /// A curve that only fades has nothing to lead with: Reduce Motion removes
    /// the travel, and staggering two fades would read as a flicker rather than
    /// as one thing following another.
    private var effectiveLead: Double { curve.movesGeometry ? lead : 0 }

    private func animation(delayedBy delay: Double) -> Animation? {
        guard let animation = curve.animation else { return nil }
        return delay > 0 ? animation.delay(delay) : animation
    }
}

/// The motion for a change to what the island is showing.
///
/// The same spring the island opens and closes with, so the island has one feel
/// however it happens to be changing. A hidden island animates nothing, per the
/// idle budget in `docs/02-performance-contract.md`, and neither does one the
/// CPU watchdog has stood still: both are states where motion is precisely what
/// must not be scheduled.
public func islandContentMotion(
    in state: PresentationState,
    change: IslandExtentChange,
    motion: IslandMotion = .default,
    reduceMotion: Bool = false,
    isMotionSuspended: Bool = false
) -> IslandContentMotion {
    guard state != .hidden, isMotionSuspended == false else { return .still }
    guard reduceMotion == false else {
        return IslandContentMotion(
            curve: .crossFade(duration: motion.reducedMotionCrossFadeDuration),
            lead: motion.contentLead,
            change: change
        )
    }
    return IslandContentMotion(
        curve: .spring(response: motion.springResponse, dampingFraction: motion.springDamping),
        lead: motion.contentLead,
        change: change
    )
}

private struct IslandContentMotionKey: EnvironmentKey {
    static let defaultValue = IslandContentMotion.still
}

extension EnvironmentValues {
    /// How the change being drawn right now is animated. Set by the island's
    /// root view from the presenter's own reading, so every view inside the
    /// island moves on the clock the island itself is moving on.
    public var islandContentMotion: IslandContentMotion {
        get { self[IslandContentMotionKey.self] }
        set { self[IslandContentMotionKey.self] = newValue }
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
    public private(set) var preferenceOverride: Bool?
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
