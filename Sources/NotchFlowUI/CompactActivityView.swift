import CoreGraphics
import NotchFlowCore
import SwiftUI

/// One drawn element of the compact pill: either an activity's icon or the
/// single overflow indicator that stands in for everything past the capacity in
/// `docs/05-activity-model.md`.
public struct CompactSlot: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbolName: String
    public let label: String?
    public let overflowCount: Int?
    public let accessibilityLabel: String

    /// Draws moving equaliser bars in place of the glyph. Carried as a flag
    /// rather than as a second symbol name because the bars are not a symbol:
    /// they animate, and only while something is actually playing.
    public let isPlayingMusic: Bool

    fileprivate init(activity: any Activity) {
        id = activity.identity.rawValue
        symbolName = compactSymbolName(activity.kind)
        label = nil
        overflowCount = nil
        accessibilityLabel = compactAccessibilityLabel(activity.kind)
        isPlayingMusic = false
    }

    /// For activities whose per-instance detail outgrows what the kind alone can
    /// say — music announces "Windowlicker — Aphex Twin" rather than "Music", and
    /// charging draws a full battery rather than the shared bolt once the charge
    /// is done. Omitting `symbolName` keeps the kind's glyph.
    init(
        activity: any Activity,
        symbolName: String? = nil,
        accessibilityLabel: String,
        isPlayingMusic: Bool = false
    ) {
        id = activity.identity.rawValue
        self.symbolName = symbolName ?? compactSymbolName(activity.kind)
        label = nil
        overflowCount = nil
        self.accessibilityLabel = accessibilityLabel
        self.isPlayingMusic = isPlayingMusic
    }

    fileprivate init(overflowCount: Int) {
        id = Self.overflowIdentifier
        symbolName = "ellipsis"
        label = "+\(overflowCount)"
        self.overflowCount = overflowCount
        accessibilityLabel = localized("\(overflowCount) more activities")
        isPlayingMusic = false
    }

    private static let overflowIdentifier = "notchflow.compact.overflow"
}

/// How the pill's slots divide around the notch. The notch itself is opaque
/// hardware, so the pill can only draw to either side of it, and reading order
/// fills the leading side first — the highest-priority activity is the one the
/// eye reaches first.
public struct CompactSlotLayout: Equatable, Sendable {
    public let leading: [CompactSlot]
    public let trailing: [CompactSlot]
}

/// The pill's fixed visual budget. Every size the compact view draws comes from
/// here, so a change to the island's density is one edit, not a sweep.
public struct CompactPillMetrics: Equatable, Sendable {
    public static let `default` = CompactPillMetrics()

    public let slotWidth: CGFloat
    public let slotSpacing: CGFloat
    public let edgeInset: CGFloat
    public let symbolSize: CGFloat
    public let cornerRadius: CGFloat

    public init(
        slotWidth: CGFloat = 22,
        slotSpacing: CGFloat = 6,
        edgeInset: CGFloat = 10,
        symbolSize: CGFloat = 13,
        cornerRadius: CGFloat = 12
    ) {
        self.slotWidth = slotWidth
        self.slotSpacing = slotSpacing
        self.edgeInset = edgeInset
        self.symbolSize = symbolSize
        self.cornerRadius = cornerRadius
    }
}

/// One activity's slot, routed to the kind that knows how to describe itself.
///
/// Music and charging both announce per-instance detail the shared kind label
/// cannot carry — the actual track, and a full battery once charging completes.
private func compactSlot(for activity: any Activity) -> CompactSlot {
    switch activity {
    case let music as MusicActivity: musicCompactSlot(for: music)
    case let charging as ChargingActivity: chargingCompactSlot(for: charging)
    default: CompactSlot(activity: activity)
    }
}

/// The ordered slots for `presentation`, which has already applied the priority
/// ordering and the capacity limit in `ActivityManager`.
public func compactSlots(for presentation: CompactActivityPresentation) -> [CompactSlot] {
    let slots = presentation.activities.map(compactSlot(for:))
    guard presentation.overflowCount > 0 else { return slots }
    return slots + [CompactSlot(overflowCount: presentation.overflowCount)]
}

/// Splits the slots around the notch, filling the leading side first so the
/// overflow indicator — always last — lands on the trailing side.
public func compactSlotLayout(for presentation: CompactActivityPresentation) -> CompactSlotLayout {
    let slots = compactSlots(for: presentation)
    let leadingCount = (slots.count + 1) / 2
    return CompactSlotLayout(
        leading: Array(slots.prefix(leadingCount)),
        trailing: Array(slots.dropFirst(leadingCount))
    )
}

/// The pill's drawn size: exactly as tall as the notch it hugs, and wide enough
/// for the notch plus the slots flanking it, per the compact row of the state
/// table in `docs/04-overlay-window.md`.
public func compactPillSize(
    slotCount: Int,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    let slots = max(slotCount, 0)
    // With no slots the pill would be exactly the notch, and a pill the size of
    // the opaque hardware it hugs is invisible. The empty perch the "keep the
    // bar always visible" setting asks for therefore still pays the edge inset,
    // so it reads as a bar flanking the notch rather than as nothing at all.
    guard slots > 0 else {
        return CGSize(
            width: notchSize.width + metrics.edgeInset * 2,
            height: notchSize.height
        )
    }

    let slotsWidth = CGFloat(slots) * metrics.slotWidth
    let spacing = CGFloat(slots) * metrics.slotSpacing
    return CGSize(
        width: notchSize.width + slotsWidth + spacing + metrics.edgeInset * 2,
        height: notchSize.height
    )
}

public func compactSymbolName(_ kind: ActivityKind) -> String {
    switch kind {
    case .music: "music.note"
    case .timer: "timer"
    case .recording: "record.circle"
    case .charging: "bolt.fill"
    case .aiAgent: "sparkles"
    case .fileTransfer: "arrow.down.circle"
    }
}

public func compactAccessibilityLabel(_ kind: ActivityKind) -> String {
    switch kind {
    case .music: localized("Music")
    case .timer: localized("Timer")
    case .recording: localized("Recording")
    case .charging: localized("Charging")
    case .aiAgent: localized("AI agent")
    case .fileTransfer: localized("Transfer")
    }
}

/// The compact pill: activity icons hugging both edges of the notch, with the
/// notch's own width held open between them.
public struct CompactActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let presentation: CompactActivityPresentation
    private let notchSize: CGSize
    private let metrics: CompactPillMetrics
    private let motion: IslandMotion

    public init(
        presentation: CompactActivityPresentation,
        notchSize: CGSize,
        metrics: CompactPillMetrics = .default,
        motion: IslandMotion = .default
    ) {
        self.presentation = presentation
        self.notchSize = notchSize
        self.metrics = metrics
        self.motion = motion
    }

    public var body: some View {
        let layout = compactSlotLayout(for: presentation)
        let size = compactPillSize(
            slotCount: layout.leading.count + layout.trailing.count,
            notchSize: notchSize,
            metrics: metrics
        )

        let surface = islandCompactSurface(scheme: colorScheme.islandColorScheme)

        HStack(spacing: metrics.slotSpacing) {
            slotRow(layout.leading)
            Color.clear.frame(width: notchSize.width)
            slotRow(layout.trailing)
        }
        .padding(.horizontal, metrics.edgeInset)
        .frame(width: size.width, height: size.height)
        .foregroundStyle(surface.foreground.style)
        .background {
            surface.fill(in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        }
        .environment(\.colorScheme, surface.foreground == .onDark ? .dark : .light)
    }

    private func slotRow(_ slots: [CompactSlot]) -> some View {
        HStack(spacing: metrics.slotSpacing) {
            ForEach(slots) { slot in
                slotView(slot)
                    .transition(slotTransition)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(slotAnimation, value: slots)
    }

    /// Slots grow out of, and shrink back into, the notch's edge rather than
    /// appearing at full size, so an activity starting reads as the island
    /// extending rather than as a glyph blinking into place.
    private var slotTransition: AnyTransition {
        guard reduceMotion == false else { return .opacity }
        return .scale(scale: 0.6).combined(with: .opacity)
    }

    private var slotAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: motion.reducedMotionCrossFadeDuration)
            : .spring(response: motion.springResponse, dampingFraction: motion.springDamping)
    }

    private func slotView(_ slot: CompactSlot) -> some View {
        Group {
            if let label = slot.label {
                Text(label)
                    .font(.system(size: metrics.symbolSize, weight: .semibold, design: .rounded))
            } else if slot.isPlayingMusic {
                MusicEqualiserSlotView(metrics: metrics, symbolName: slot.symbolName)
            } else {
                Image(systemName: slot.symbolName)
                    .font(.system(size: metrics.symbolSize, weight: .medium))
            }
        }
        .frame(width: metrics.slotWidth)
        .accessibilityLabel(slot.accessibilityLabel)
    }
}

/// The moving equaliser drawn in the music slot while a track is playing.
///
/// Settles into the static glyph after `animationDuration`, so the island does
/// not keep an animation running for the entire length of an album — the idle
/// budget in `docs/02-performance-contract.md` is the whole reason the pill is
/// cheap to leave on screen. The motion is announcement, not status.
struct MusicEqualiserSlotView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    @State private var hasSettled = false

    /// How long the bars move before settling to the glyph.
    static let animationDuration: Duration = .seconds(3)

    private static let barScales: [CGFloat] = [0.45, 1.0, 0.7]
    private static let barPhaseOffsets: [Double] = [0, 0.18, 0.36]

    let metrics: CompactPillMetrics
    let symbolName: String

    var body: some View {
        content
            .task {
                guard reduceMotion == false else { return }
                isAnimating = true
                try? await Task.sleep(for: Self.animationDuration)
                isAnimating = false
                hasSettled = true
            }
    }

    @ViewBuilder
    private var content: some View {
        if reduceMotion || hasSettled {
            Image(systemName: symbolName)
                .font(.system(size: metrics.symbolSize, weight: .medium))
                .transition(.opacity)
        } else {
            bars
        }
    }

    private var bars: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(Self.barScales.enumerated()), id: \.offset) { index, restingScale in
                Capsule()
                    .frame(width: barWidth, height: metrics.symbolSize * restingScale)
                    .scaleEffect(y: isAnimating ? 1 : 0.35, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.42)
                            .repeatForever(autoreverses: true)
                            .delay(Self.barPhaseOffsets[index]),
                        value: isAnimating
                    )
            }
        }
        .frame(height: metrics.symbolSize)
    }

    private var barWidth: CGFloat { metrics.symbolSize / 5 }
    private var barSpacing: CGFloat { metrics.symbolSize / 6 }
}
