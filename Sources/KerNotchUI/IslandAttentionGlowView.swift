import AppKit
import SwiftUI

/// How the glow may move, given the viewer's settings and the watchdog.
enum IslandAttentionGlowMotion: Equatable, Sendable {
    /// The light travels along the edge.
    case travelling
    /// Reduce Motion: the rim fades in and out in place, on the same beat.
    case pulsing
    /// The CPU watchdog has suspended motion: a still rim, nothing animated.
    case resting
}

/// The glow's drawn dimensions.
enum IslandAttentionGlowMetrics {
    /// How much coloured edge shows outside the island.
    static let visibleRimWidth: CGFloat = 2
    /// Twice the visible width: the rim is drawn behind the island's black
    /// surface, which covers the inner half and keeps the pill itself black.
    static var strokeWidth: CGFloat { visibleRimWidth * 2 }
    static let haloRadius: CGFloat = 6
    static let haloOpacity: Float = 0.85
    /// Room around the island for the halo to spread into. None above it: the
    /// island's top is the top of the screen.
    static let haloPadding: CGFloat = 14
    /// How much of the island's width the travelling light covers at once.
    static let lightWidthFraction: CGFloat = 0.32
    /// The light's brightness across its width, dark at both ends so it has no
    /// hard edge.
    static let lightProfileAlphas: [CGFloat] = [0, 0.45, 1, 0.45, 0]
    static let restingOpacity: Float = 0.6
}

/// Where the rim runs, in the glow's own canvas.
struct IslandAttentionGlowGeometry: Equatable, Sendable {
    let surfaceSize: CGSize

    /// The island's surface plus halo room on the sides and bottom.
    var canvasSize: CGSize {
        CGSize(
            width: surfaceSize.width + 2 * IslandAttentionGlowMetrics.haloPadding,
            height: surfaceSize.height + IslandAttentionGlowMetrics.haloPadding
        )
    }

    /// The island's open outline in layer coordinates.
    ///
    /// The outline is built downward from the top, as SwiftUI draws; a layer's
    /// origin is at the bottom. The flip is explicit here, so the rim's position
    /// is a value a test can check, not a property of whatever view hosts it.
    func rimPath() -> CGPath {
        guard surfaceSize.width > 0, surfaceSize.height > 0 else { return CGMutablePath() }
        let edge = ConnectedIslandGeometry.flaredEdge(in: CGRect(origin: .zero, size: surfaceSize))
        let flipIntoCanvas = CGAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: -1,
            tx: IslandAttentionGlowMetrics.haloPadding,
            ty: canvasSize.height
        )
        return edge.applying(flipIntoCanvas).cgPath
    }
}

/// Where a glow's sequence stands at the moment an animation is attached to it.
struct IslandAttentionGlowProgress: Equatable {
    /// How far into the sequence the glow already is, so a view created
    /// mid-glow — the island collapsing back to compact — joins the sequence
    /// where it stands instead of starting it again.
    let elapsed: TimeInterval
    let passCount: Int

    init(glow: IslandAttentionGlow, at now: Date) {
        elapsed = now.timeIntervalSince(glow.startedAt)
        passCount = glow.passCount
    }

    var isFinished: Bool {
        elapsed >= IslandAttentionGlowTiming.duration(ofPasses: passCount)
    }
}

/// The glow's Core Animation timing, built as values so the beat is testable.
enum IslandAttentionGlowAnimation {
    static let key = "kernotch.attentionGlow.passes"

    /// Gradient stop positions for a light whose leading edge is at `start`, in
    /// the unit space of the island's width — so a pill that changes width
    /// mid-glow needs no new animation.
    static func lightLocations(leadingEdgeAt start: CGFloat) -> [NSNumber] {
        let width = IslandAttentionGlowMetrics.lightWidthFraction
        let lastStop = CGFloat(IslandAttentionGlowMetrics.lightProfileAlphas.count - 1)
        return IslandAttentionGlowMetrics.lightProfileAlphas.indices.map { index in
            NSNumber(value: Double(start + width * CGFloat(index) / lastStop))
        }
    }

    /// Wholly off the left edge: the trailing stop sits exactly at zero.
    static var parkedLeft: [NSNumber] {
        lightLocations(leadingEdgeAt: -IslandAttentionGlowMetrics.lightWidthFraction)
    }

    /// Wholly off the right edge: the leading stop sits exactly at one.
    static var parkedRight: [NSNumber] {
        lightLocations(leadingEdgeAt: 1)
    }

    /// One pass per interval: across the island, then held off the right edge
    /// until the next pass begins.
    static func travellingLight(_ progress: IslandAttentionGlowProgress, now: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "locations")
        animation.values = [parkedLeft, parkedRight, parkedRight]
        animation.keyTimes = [
            0,
            NSNumber(value: IslandAttentionGlowTiming.passDuration / IslandAttentionGlowTiming.passInterval),
            1,
        ]
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .linear),
        ]
        applySequenceTiming(to: animation, progress: progress, now: now)
        return animation
    }

    /// The Reduce Motion substitute: the same beat, faded in place.
    static func pulse(_ progress: IslandAttentionGlowProgress, now: CFTimeInterval) -> CAKeyframeAnimation {
        let passShare = IslandAttentionGlowTiming.passDuration / IslandAttentionGlowTiming.passInterval
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0.0, 1.0, 0.0, 0.0]
        animation.keyTimes = [0, NSNumber(value: passShare / 2), NSNumber(value: passShare), 1]
        applySequenceTiming(to: animation, progress: progress, now: now)
        return animation
    }

    private static func applySequenceTiming(
        to animation: CAKeyframeAnimation,
        progress: IslandAttentionGlowProgress,
        now: CFTimeInterval
    ) {
        animation.duration = IslandAttentionGlowTiming.passInterval
        animation.repeatCount = Float(progress.passCount)
        animation.beginTime = now - progress.elapsed
    }
}

/// The glow around the compact island.
///
/// Drawn behind the island's surface and outside its clip: the surface hides
/// the inner half of the rim, so the pill stays the notch's own black and only
/// the light around it shows.
public struct IslandAttentionGlowView: View {
    @Environment(\.prefersReducedIslandMotion) private var reduceMotion
    @Environment(\.islandMotionSuspended) private var islandMotionSuspended

    private let glow: IslandAttentionGlow
    private let geometry: IslandAttentionGlowGeometry

    public init(glow: IslandAttentionGlow, surfaceSize: CGSize) {
        self.glow = glow
        geometry = IslandAttentionGlowGeometry(surfaceSize: surfaceSize)
    }

    public var body: some View {
        AttentionGlowLayerView(
            geometry: geometry,
            tone: aiAgentBadgeColor(glow.reason.badgeTone),
            glow: glow,
            motion: motion
        )
        .frame(width: geometry.canvasSize.width, height: geometry.canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var motion: IslandAttentionGlowMotion {
        if islandMotionSuspended {
            return .resting
        }
        return reduceMotion ? .pulsing : .travelling
    }
}

private struct AttentionGlowLayerView: NSViewRepresentable {
    let geometry: IslandAttentionGlowGeometry
    let tone: Color
    let glow: IslandAttentionGlow
    let motion: IslandAttentionGlowMotion

    func makeNSView(context: Context) -> AttentionGlowHostView {
        let view = AttentionGlowHostView(frame: CGRect(origin: .zero, size: geometry.canvasSize))
        view.configure(configuration(in: context))
        return view
    }

    func updateNSView(_ view: AttentionGlowHostView, context: Context) {
        view.configure(configuration(in: context))
    }

    private func configuration(in context: Context) -> AttentionGlowHostView.Configuration {
        AttentionGlowHostView.Configuration(
            geometry: geometry,
            tone: tone.resolve(in: context.environment),
            glow: glow,
            motion: motion
        )
    }
}

/// Hosts the glow's layers.
///
/// ```
/// view layer
///  └─ rim            (masked by the travelling light while travelling)
///      └─ edge       (the stroked outline, casting the halo)
/// ```
private final class AttentionGlowHostView: NSView {
    struct Configuration: Equatable {
        let geometry: IslandAttentionGlowGeometry
        let tone: Color.Resolved
        let glow: IslandAttentionGlow
        let motion: IslandAttentionGlowMotion
    }

    private let rim = CALayer()
    private let edge = CAShapeLayer()
    private let travellingLight = CAGradientLayer()
    private var configuration: Configuration?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        edge.fillColor = nil
        edge.lineWidth = IslandAttentionGlowMetrics.strokeWidth
        edge.lineCap = .butt
        edge.lineJoin = .round
        edge.shadowOpacity = IslandAttentionGlowMetrics.haloOpacity
        edge.shadowRadius = IslandAttentionGlowMetrics.haloRadius
        edge.shadowOffset = .zero

        travellingLight.startPoint = CGPoint(x: 0, y: 0.5)
        travellingLight.endPoint = CGPoint(x: 1, y: 0.5)
        travellingLight.colors = IslandAttentionGlowMetrics.lightProfileAlphas.map {
            NSColor.white.withAlphaComponent($0).cgColor
        }

        rim.addSublayer(edge)
        layer?.addSublayer(rim)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// The glow is light, not a control: the pill beneath it keeps its clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            // Starting is a no-op while the sequence runs, and resumes it at its
            // elapsed point if Core Animation dropped it in the meantime.
            startSequenceIfNeeded()
            return
        }
        let restartsSequence =
            self.configuration?.glow != configuration.glow
            || self.configuration?.motion != configuration.motion
        self.configuration = configuration

        applyShape(configuration)
        if restartsSequence {
            restart(for: configuration.motion)
        }
        startSequenceIfNeeded()
    }

    /// Core Animation drops a layer's animations when it leaves the render
    /// tree, so the sequence is resumed — at its elapsed point — whenever the
    /// view lands in a window again.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        matchWindowScale()
        startSequenceIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        matchWindowScale()
    }

    /// Layers created by hand do not follow the window's scale on their own, and
    /// a two-point stroke rendered at 1x reads as a blur on a Retina panel.
    private func matchWindowScale() {
        guard let scale = window?.backingScaleFactor else { return }
        for sublayer in [rim, edge, travellingLight] {
            sublayer.contentsScale = scale
        }
    }

    private func applyShape(_ configuration: Configuration) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let canvas = CGRect(origin: .zero, size: configuration.geometry.canvasSize)
        let rimPath = configuration.geometry.rimPath()
        rim.frame = canvas
        edge.frame = canvas
        travellingLight.frame = canvas
        edge.path = rimPath
        edge.shadowPath = rimPath.copy(
            strokingWithWidth: IslandAttentionGlowMetrics.strokeWidth,
            lineCap: .butt,
            lineJoin: .round,
            miterLimit: 1
        )
        edge.strokeColor = configuration.tone.cgColor
        edge.shadowColor = configuration.tone.cgColor
    }

    /// Drops whatever the previous glow was doing and sets the resting values
    /// the new motion starts from.
    private func restart(for motion: IslandAttentionGlowMotion) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        travellingLight.removeAnimation(forKey: IslandAttentionGlowAnimation.key)
        rim.removeAnimation(forKey: IslandAttentionGlowAnimation.key)
        travellingLight.locations = IslandAttentionGlowAnimation.parkedLeft

        switch motion {
        case .travelling:
            rim.mask = travellingLight
            rim.opacity = 1
        case .pulsing:
            rim.mask = nil
            rim.opacity = 0
        case .resting:
            rim.mask = nil
            rim.opacity = IslandAttentionGlowMetrics.restingOpacity
        }
    }

    private func startSequenceIfNeeded() {
        guard let configuration, window != nil else { return }
        let progress = IslandAttentionGlowProgress(glow: configuration.glow, at: Date())
        guard progress.isFinished == false else { return }

        let now = CACurrentMediaTime()
        switch configuration.motion {
        case .travelling where travellingLight.animation(forKey: IslandAttentionGlowAnimation.key) == nil:
            travellingLight.add(
                IslandAttentionGlowAnimation.travellingLight(progress, now: now),
                forKey: IslandAttentionGlowAnimation.key
            )
        case .pulsing where rim.animation(forKey: IslandAttentionGlowAnimation.key) == nil:
            rim.add(
                IslandAttentionGlowAnimation.pulse(progress, now: now),
                forKey: IslandAttentionGlowAnimation.key
            )
        case .travelling, .pulsing, .resting:
            break
        }
    }
}
