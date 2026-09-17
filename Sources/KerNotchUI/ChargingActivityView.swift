import KerNotchCore
import SwiftUI

/// Everything the charging views draw, derived from `ChargingActivity` alone.
///
/// The level reaches the screen as the width of a fill, never as digits: the
/// title is a statement about the transition, and only VoiceOver, which cannot
/// see the fill, is told the number.
public struct ChargingPresentation: Equatable, Sendable {
    /// At or below this, a battery the charger just left is drawn red, as the
    /// system draws a battery about to run out.
    static let lowLevelThreshold = 0.2

    public let state: ChargingState
    public let level: BatteryLevel

    public init(activity: ChargingActivity) {
        state = activity.state
        level = activity.level
    }

    /// A completed statement about the transition rather than a reading that
    /// invites watching — the difference between a notification and a gauge.
    public var title: String {
        switch state {
        case .onBattery: localized("Unplugged")
        case .pluggedIn: localized("Plugged In")
        case .charging: localized("Charging")
        case .fullyCharged: localized("Fully Charged")
        }
    }

    public var accessibilityLabel: String {
        let percentage = level.fraction.formatted(.percent.precision(.fractionLength(0)))
        return localized("activity.accessibility.headlineAndDetail", default: "\(title), \(percentage)")
    }

    /// Only while the battery is filling: a machine holding at its charge limit
    /// is connected, but nothing is going in.
    var showsChargingBolt: Bool { state == .charging }

    var fillTone: BatteryFillTone {
        if state.isConnectedToPower { return .connected }
        return level.fraction <= Self.lowLevelThreshold ? .low : .standard
    }
}

enum BatteryFillTone: Equatable, Sendable {
    case connected
    case standard
    case low
}

/// The charging activity's compact slot: the battery at its level, so plugging
/// in and unplugging are distinguishable in the pill without expanding it.
public func chargingCompactSlot(for activity: ChargingActivity) -> CompactSlot {
    CompactSlot(charging: activity, presentation: ChargingPresentation(activity: activity))
}

/// The battery drawn the way the menu bar draws it: an outline, a fill as wide
/// as the charge, and a bolt while it is filling.
///
/// Drawn rather than taken from SF Symbols because the battery symbols come in
/// quarter steps and only the full one has a bolt variant, so a battery charging
/// at 41% could only be drawn full or without its bolt.
struct BatteryLevelGlyph: View {
    let presentation: ChargingPresentation
    let size: CGFloat

    var body: some View {
        let bodySize = CGSize(width: size * 1.45, height: size * 0.72)
        let outlineWidth = max(size * 0.08, 1)
        let fillInset = outlineWidth + max(size * 0.06, 0.5)
        let fillHeight = bodySize.height - fillInset * 2
        let fillWidth = (bodySize.width - fillInset * 2) * presentation.level.fraction

        HStack(spacing: size * 0.05) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: bodySize.height * 0.3, style: .continuous)
                    .strokeBorder(.secondary, lineWidth: outlineWidth)
                RoundedRectangle(cornerRadius: fillHeight * 0.25, style: .continuous)
                    .fill(fillStyle)
                    .frame(width: fillWidth, height: fillHeight)
                    .padding(.leading, fillInset)
            }
            .frame(width: bodySize.width, height: bodySize.height)
            .overlay {
                if presentation.showsChargingBolt {
                    chargingBolt(height: bodySize.height)
                }
            }

            UnevenRoundedRectangle(
                bottomTrailingRadius: size * 0.05,
                topTrailingRadius: size * 0.05,
                style: .continuous
            )
            .fill(.secondary)
            .frame(width: size * 0.1, height: bodySize.height * 0.36)
        }
        .accessibilityHidden(true)
    }

    private var fillStyle: AnyShapeStyle {
        switch presentation.fillTone {
        case .connected: AnyShapeStyle(Color.green)
        case .standard: AnyShapeStyle(.primary)
        case .low: AnyShapeStyle(Color.red)
        }
    }

    /// White on a slightly larger black bolt, so it stays legible over the
    /// green fill and the empty outline alike.
    private func chargingBolt(height: CGFloat) -> some View {
        ZStack {
            Image(systemName: "bolt.fill")
                .font(.system(size: height * 1.05, weight: .black))
                .foregroundStyle(.black)
            Image(systemName: "bolt.fill")
                .font(.system(size: height * 0.85, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// The charging row: the battery glyph and a statement, and deliberately nothing
/// else.
///
/// There is no progress bar and no percentage, per
/// `docs/06-activity-providers.md` — the activity reports that the power
/// situation changed, then dismisses itself. A view that grew a live gauge would
/// turn a four-second notification into the permanent battery readout the design
/// exists to avoid.
public struct ChargingActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let presentation: ChargingPresentation
    private let metrics: ExpandedPanelMetrics

    public init(
        activity: ChargingActivity,
        metrics: ExpandedPanelMetrics = .default
    ) {
        presentation = ChargingPresentation(activity: activity)
        self.metrics = metrics
    }

    public var body: some View {
        let surface = islandExpandedSurface(
            scheme: colorScheme.islandColorScheme,
            reduceTransparency: reduceTransparency
        )

        HStack(spacing: 0) {
            BatteryLevelGlyph(presentation: presentation, size: metrics.symbolSize * 0.8)
                .frame(width: metrics.symbolColumnWidth)

            Text(presentation.title)
                .font(.system(size: metrics.titleSize, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.contentInset)
        .foregroundStyle(surface.foreground.style)
        .islandCard(
            width: metrics.width,
            height: metrics.rowHeight,
            cornerRadius: metrics.cornerRadius,
            surface: surface
        )
        .environment(\.colorScheme, surface.preferredColorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
