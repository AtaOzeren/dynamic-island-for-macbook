import NotchFlowCore
import SwiftUI

/// Everything the charging views draw, derived from `ChargingActivity` alone.
///
/// Its shape is the no-persistent-percentage rule made structural at the last
/// boundary: the presentation exposes a glyph and a label and no numeric field
/// at all, and it is built from an activity that carries no capacity to begin
/// with. A view cannot draw a percentage it was never given, and nothing in this
/// file has anywhere to fetch one from.
public struct ChargingPresentation: Equatable, Sendable {
    public let state: ChargingState

    public init(activity: ChargingActivity) {
        state = activity.state
    }

    /// The glyph carries the whole distinction between the three states, which
    /// is why the states can be words rather than digits: a bolt reads as "power
    /// is going in" at a glance, and a full battery reads as done.
    public var symbolName: String {
        switch state {
        case .pluggedIn: "powerplug.fill"
        case .charging: "battery.100.bolt"
        case .fullyCharged: "battery.100"
        }
    }

    /// What both the island and VoiceOver say. Each is a completed statement
    /// about a transition rather than a reading that invites watching — the
    /// difference between a notification and a gauge.
    public var title: String {
        switch state {
        case .pluggedIn: localized("Plugged In")
        case .charging: localized("Charging")
        case .fullyCharged: localized("Fully Charged")
        }
    }

    public var accessibilityLabel: String { title }
}

/// The charging activity's compact slot: the state's own glyph rather than the
/// shared `.charging` one, so a full battery and an active charge are
/// distinguishable in the pill without expanding it.
public func chargingCompactSlot(for activity: ChargingActivity) -> CompactSlot {
    let presentation = ChargingPresentation(activity: activity)

    return CompactSlot(
        activity: activity,
        symbolName: presentation.symbolName,
        accessibilityLabel: presentation.accessibilityLabel
    )
}

/// The charging row: a glyph and a statement, and deliberately nothing else.
///
/// There is no progress bar and no percentage, per
/// `docs/06-activity-providers.md` — the activity reports that the power
/// situation changed, then dismisses itself. A view that grew a gauge would turn
/// a four-second notification into the permanent battery readout the design
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
            Image(systemName: presentation.symbolName)
                .font(.system(size: metrics.symbolSize))
                .frame(width: metrics.symbolColumnWidth)

            Text(presentation.title)
                .font(.system(size: metrics.symbolSize))
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
