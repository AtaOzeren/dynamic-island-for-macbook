import AppKit
import KerNotchCore
import SwiftUI

/// The music slot while a track plays: three bars that keep moving for exactly
/// as long as it does.
///
/// The motion is the playback status — it gives way to the still note the
/// moment the track pauses — so it has to be affordable for a whole album.
/// Animating the bars in SwiftUI re-evaluated the island every frame; the bars
/// are animated by Core Animation instead, in the render server, with the body
/// evaluated once. That is the same arrangement the agent's working dot uses,
/// for the same measured reason.
struct MusicEqualiserSlotView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandMotionSuspended) private var islandMotionSuspended

    let metrics: CompactPillMetrics
    let symbolName: String
    let sourceIdentity: MusicSourceIdentity

    var body: some View {
        if reduceMotion || islandMotionSuspended {
            Image(systemName: symbolName)
                .font(.system(size: metrics.symbolSize, weight: .medium))
                .foregroundStyle(musicAccentColor(sourceIdentity))
        } else {
            MusicEqualiserLayerView(
                geometry: MusicEqualiserGeometry(symbolSize: metrics.symbolSize),
                color: musicAccentColor(sourceIdentity)
            )
            .frame(width: metrics.symbolSize, height: metrics.symbolSize)
            .allowsHitTesting(false)
        }
    }
}

/// Where the bars sit and how they move, in the slot's square of
/// `symbolSize` points.
struct MusicEqualiserGeometry: Equatable, Sendable {
    /// Each bar's height at full stroke, as a fraction of the symbol size.
    static let restingBarScales: [CGFloat] = [0.45, 1.0, 0.7]
    /// How far behind the first bar each bar starts, so they never move as one.
    static let barPhaseOffsets: [CFTimeInterval] = [0, 0.18, 0.36]
    /// One compression or extension of a bar.
    static let strokeDuration: CFTimeInterval = 0.42
    /// How far a bar shrinks at the bottom of its stroke.
    static let compressedScale: CGFloat = 0.35

    let symbolSize: CGFloat

    var barWidth: CGFloat { symbolSize / 5 }
    var barSpacing: CGFloat { symbolSize / 6 }

    /// The bars, centred both ways in the square. Vertical centring makes the
    /// frames the same in AppKit's upward and SwiftUI's downward coordinates,
    /// so no flip is needed between them.
    func barFrames() -> [CGRect] {
        let barCount = CGFloat(Self.restingBarScales.count)
        let rowWidth = barCount * barWidth + (barCount - 1) * barSpacing
        let rowOriginX = (symbolSize - rowWidth) / 2

        return Self.restingBarScales.enumerated().map { index, scale in
            let height = symbolSize * scale
            return CGRect(
                x: rowOriginX + CGFloat(index) * (barWidth + barSpacing),
                y: (symbolSize - height) / 2,
                width: barWidth,
                height: height
            )
        }
    }
}

private struct MusicEqualiserLayerView: NSViewRepresentable {
    let geometry: MusicEqualiserGeometry
    let color: Color

    func makeNSView(context: Context) -> MusicEqualiserHostView {
        let view = MusicEqualiserHostView(
            frame: CGRect(x: 0, y: 0, width: geometry.symbolSize, height: geometry.symbolSize)
        )
        view.configure(configuration(in: context))
        return view
    }

    func updateNSView(_ view: MusicEqualiserHostView, context: Context) {
        view.configure(configuration(in: context))
    }

    private func configuration(in context: Context) -> MusicEqualiserHostView.Configuration {
        MusicEqualiserHostView.Configuration(
            geometry: geometry,
            color: color.resolve(in: context.environment)
        )
    }
}

private final class MusicEqualiserHostView: NSView {
    struct Configuration: Equatable {
        let geometry: MusicEqualiserGeometry
        let color: Color.Resolved
    }

    private static let animationKey = "kernotch.musicEqualiser.stroke"

    private var bars: [CALayer] = []
    private var configuration: Configuration?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// Clicks belong to the pill, which expands the island on a tap.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// Re-arms the strokes on every update, changed or not: arming is a no-op
    /// while they run, and it restores them if Core Animation dropped them
    /// without the view ever leaving its window.
    func configure(_ configuration: Configuration) {
        if self.configuration != configuration {
            self.configuration = configuration
            rebuildBars(for: configuration)
        }
        startStrokesIfNeeded()
    }

    /// Core Animation drops a layer's animations when it leaves the render tree,
    /// which the bars do whenever the island expands or the panel is ordered
    /// out, so the strokes are re-armed whenever the view lands in a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startStrokesIfNeeded()
    }

    private func rebuildBars(for configuration: Configuration) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for bar in bars {
            bar.removeFromSuperlayer()
        }
        bars = configuration.geometry.barFrames().map { frame in
            let bar = CALayer()
            bar.frame = frame
            bar.cornerRadius = frame.width / 2
            bar.backgroundColor = configuration.color.cgColor
            layer?.addSublayer(bar)
            return bar
        }
    }

    private func startStrokesIfNeeded() {
        guard window != nil else { return }
        let now = CACurrentMediaTime()
        for (bar, phaseOffset) in zip(bars, MusicEqualiserGeometry.barPhaseOffsets)
        where bar.animation(forKey: Self.animationKey) == nil {
            bar.add(Self.stroke(beginningAt: now + phaseOffset), forKey: Self.animationKey)
        }
    }

    private static func stroke(beginningAt beginTime: CFTimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.scale.y")
        animation.fromValue = MusicEqualiserGeometry.compressedScale
        animation.toValue = 1
        animation.duration = MusicEqualiserGeometry.strokeDuration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.beginTime = beginTime
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = false
        return animation
    }
}
