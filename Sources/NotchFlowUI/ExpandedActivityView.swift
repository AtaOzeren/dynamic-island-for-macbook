import CoreGraphics
import NotchFlowCore
import SwiftUI

/// One row of the expanded list: an activity's icon, its title, and the primary
/// action affordance when the activity offers one.
///
/// There is no overflow counterpart to `CompactSlot` on purpose — the expanded
/// view never truncates, per `docs/05-activity-model.md`.
public struct ExpandedRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbolName: String
    public let title: String
    public let primaryAction: PrimaryAction?
    public let accessibilityLabel: String

    fileprivate init(activity: any Activity) {
        id = activity.identity.rawValue
        symbolName = compactSymbolName(activity.kind)
        title = compactAccessibilityLabel(activity.kind)
        primaryAction = activity.primaryAction
        accessibilityLabel = compactAccessibilityLabel(activity.kind)
    }
}

/// The expanded panel's fixed visual budget, the counterpart to
/// `CompactPillMetrics` — one edit changes the expanded density.
public struct ExpandedPanelMetrics: Equatable, Sendable {
    public static let `default` = ExpandedPanelMetrics()

    public let rowHeight: CGFloat
    public let rowSpacing: CGFloat
    public let contentInset: CGFloat
    public let symbolSize: CGFloat
    public let symbolColumnWidth: CGFloat
    public let cornerRadius: CGFloat
    public let width: CGFloat

    public init(
        rowHeight: CGFloat = 34,
        rowSpacing: CGFloat = 4,
        contentInset: CGFloat = 12,
        symbolSize: CGFloat = 15,
        symbolColumnWidth: CGFloat = 24,
        cornerRadius: CGFloat = 18,
        width: CGFloat = 320
    ) {
        self.rowHeight = rowHeight
        self.rowSpacing = rowSpacing
        self.contentInset = contentInset
        self.symbolSize = symbolSize
        self.symbolColumnWidth = symbolColumnWidth
        self.cornerRadius = cornerRadius
        self.width = width
    }
}

/// Which renderer the expanded panel uses for an activity.
///
/// A concrete payload type (`MusicActivity`, `TimerActivity`, …) earns its
/// dedicated view; anything else — including a stub in a test or a kind added
/// before it got a view — falls back to the generic row, never to nothing.
public enum ExpandedItemRenderer: Equatable, Sendable {
    case music
    case timer
    case aiAgent
    case charging
    case genericRow
}

public func expandedItemRenderer(for activity: any Activity) -> ExpandedItemRenderer {
    switch activity {
    case is MusicActivity: .music
    case is TimerActivity: .timer
    case is AIAgentActivity: .aiAgent
    case is ChargingActivity: .charging
    default: .genericRow
    }
}

/// Every metric set the expanded panel needs, so the height model and the view
/// cannot disagree about which numbers govern layout.
public struct ExpandedItemMetrics: Equatable, Sendable {
    public static let `default` = ExpandedItemMetrics()

    public let panel: ExpandedPanelMetrics
    public let music: MusicViewMetrics
    public let timer: TimerViewMetrics
    public let aiAgent: AIAgentViewMetrics

    public init(
        panel: ExpandedPanelMetrics = .default,
        music: MusicViewMetrics = .default,
        timer: TimerViewMetrics = .default,
        aiAgent: AIAgentViewMetrics = .default
    ) {
        self.panel = panel
        self.music = music
        self.timer = timer
        self.aiAgent = aiAgent
    }
}

/// The drawn height of one expanded item, at its real content height rather
/// than a `rowHeight` multiple — per-kind views are taller and more variable
/// than the uniform generic row, and sizing them as rows would clip their
/// bottoms.
public func expandedItemHeight(
    for activity: any Activity,
    metrics: ExpandedItemMetrics = .default,
    panelMetrics: PanelMetrics = .default
) -> CGFloat {
    switch expandedItemRenderer(for: activity) {
    case .music:
        return musicExpandedSize(metrics: metrics.music, panelMetrics: panelMetrics).height
    case .timer:
        return timerExpandedSize(metrics: metrics.timer, panelMetrics: panelMetrics).height
    case .aiAgent:
        let hasProgress = (activity as? AIAgentActivity)?.progress != nil
        return aiAgentExpandedSize(
            hasProgress: hasProgress,
            metrics: metrics.aiAgent,
            panelMetrics: panelMetrics
        ).height
    case .charging, .genericRow:
        return metrics.panel.rowHeight
    }
}

/// One row per active activity, in the manager's priority-then-registration
/// order. Unlike `compactSlots(for:)` this applies no capacity limit: expansion
/// exists precisely so nothing is truncated.
public func expandedRows(for activities: [any Activity]) -> [ExpandedRow] {
    activities.map(ExpandedRow.init(activity:))
}

/// The expanded panel's drawn size for a mixed set, clamped to the window's
/// allocated maximum.
///
/// The clamp matters because the `NSPanel` frame is allocated once at
/// `PanelMetrics.maximumExpandedSize` and never resized (`docs/04-overlay-window.md`);
/// a list that grew past it would be drawn outside the window and silently
/// clipped, which is the one way the "never truncates" rule could be broken by
/// geometry rather than by policy.
public func expandedPanelSize(
    for activities: [any Activity],
    metrics: ExpandedItemMetrics = .default,
    panelMetrics: PanelMetrics = .default,
    topInset: CGFloat = 0
) -> CGSize {
    guard !activities.isEmpty else { return .zero }

    let heights = activities.map { expandedItemHeight(for: $0, metrics: metrics, panelMetrics: panelMetrics) }
    let spacing = CGFloat(activities.count - 1) * metrics.panel.rowSpacing
    let height = heights.reduce(0, +) + spacing + metrics.panel.contentInset * 2

    // The inset is applied on both axes by the view's `.padding`, so the width
    // has to carry it too. Sizing the frame to the bare card width squeezes
    // every card by twice the inset — enough to push a trailing control button
    // outside the frame and make it unclickable.
    let widest =
        activities.map { expandedItemWidth(for: $0, metrics: metrics, panelMetrics: panelMetrics) }
        .max() ?? metrics.panel.width
    let width = widest + metrics.panel.contentInset * 2

    let availableHeight = max(panelMetrics.maximumExpandedSize.height - max(topInset, 0), 0)
    return CGSize(
        width: min(width, panelMetrics.maximumExpandedSize.width),
        height: min(height, availableHeight)
    )
}

func expandedItemWidth(
    for activity: any Activity,
    metrics: ExpandedItemMetrics = .default,
    panelMetrics: PanelMetrics = .default
) -> CGFloat {
    switch expandedItemRenderer(for: activity) {
    case .music:
        musicExpandedSize(metrics: metrics.music, panelMetrics: panelMetrics).width
    case .timer:
        timerExpandedSize(metrics: metrics.timer, panelMetrics: panelMetrics).width
    case .aiAgent:
        aiAgentExpandedSize(hasProgress: false, metrics: metrics.aiAgent, panelMetrics: panelMetrics).width
    case .charging, .genericRow:
        metrics.panel.width
    }
}

/// The expanded panel's drawn size when every row is a generic row — the
/// original shape, kept for callers that have only a row count.
public func expandedPanelSize(
    rowCount: Int,
    metrics: ExpandedPanelMetrics = .default,
    panelMetrics: PanelMetrics = .default
) -> CGSize {
    let rows = max(rowCount, 0)
    guard rows > 0 else { return .zero }

    let rowsHeight = CGFloat(rows) * metrics.rowHeight
    let spacing = CGFloat(rows - 1) * metrics.rowSpacing
    let height = rowsHeight + spacing + metrics.contentInset * 2

    return CGSize(
        width: min(metrics.width, panelMetrics.maximumExpandedSize.width),
        height: min(height, panelMetrics.maximumExpandedSize.height)
    )
}

/// Whether the set's real content heights still fit the allocated window.
/// Once this goes false the list scrolls rather than being cut off.
public func expandedPanelOverflowsWindow(
    for activities: [any Activity],
    metrics: ExpandedItemMetrics = .default,
    panelMetrics: PanelMetrics = .default,
    topInset: CGFloat = 0
) -> Bool {
    guard !activities.isEmpty else { return false }

    let heights = activities.map { expandedItemHeight(for: $0, metrics: metrics, panelMetrics: panelMetrics) }
    let spacing = CGFloat(activities.count - 1) * metrics.panel.rowSpacing
    let availableHeight = max(panelMetrics.maximumExpandedSize.height - max(topInset, 0), 0)
    return heights.reduce(0, +) + spacing + metrics.panel.contentInset * 2 > availableHeight
}

/// Whether `rowCount` generic rows still fit the allocated window at these
/// metrics. Once this goes false the list scrolls rather than being cut off.
public func expandedPanelOverflowsWindow(
    rowCount: Int,
    metrics: ExpandedPanelMetrics = .default,
    panelMetrics: PanelMetrics = .default
) -> Bool {
    let rows = max(rowCount, 0)
    guard rows > 0 else { return false }

    let rowsHeight = CGFloat(rows) * metrics.rowHeight
    let spacing = CGFloat(rows - 1) * metrics.rowSpacing
    return rowsHeight + spacing + metrics.contentInset * 2 > panelMetrics.maximumExpandedSize.height
}

/// The expanded list: every active activity in priority order, each rendered by
/// its per-kind view — real detail, not the generic glyph-and-label row —
/// growing downward from the notch, per the expanded row of the state table in
/// `docs/04-overlay-window.md`.
///
/// Each item draws its own surface, so the panel reads as a stack of cards
/// rather than one sheet with rows scratched into it; kinds without a dedicated
/// view keep the generic row so nothing ever renders as blank space.
public struct ExpandedActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let activities: [any Activity]
    private let metrics: ExpandedItemMetrics
    private let panelMetrics: PanelMetrics
    private let topInset: CGFloat
    private let onPrimaryAction: (ActivityIdentity) -> Void
    private let onMusicTransport: (MusicTransportCommand) -> Void
    private let onTimerCommand: (TimerControlCommand) -> Void

    public init(
        activities: [any Activity],
        metrics: ExpandedItemMetrics = .default,
        panelMetrics: PanelMetrics = .default,
        topInset: CGFloat = 0,
        onPrimaryAction: @escaping (ActivityIdentity) -> Void = { _ in },
        onMusicTransport: @escaping (MusicTransportCommand) -> Void = { _ in },
        onTimerCommand: @escaping (TimerControlCommand) -> Void = { _ in }
    ) {
        self.activities = activities
        self.metrics = metrics
        self.panelMetrics = panelMetrics
        self.topInset = topInset
        self.onPrimaryAction = onPrimaryAction
        self.onMusicTransport = onMusicTransport
        self.onTimerCommand = onTimerCommand
    }

    public var body: some View {
        let surface = islandExpandedSurface(
            scheme: colorScheme.islandColorScheme,
            reduceTransparency: reduceTransparency
        )
        let size = expandedPanelSize(
            for: activities,
            metrics: metrics,
            panelMetrics: panelMetrics,
            topInset: topInset
        )
        let scrolls = expandedPanelOverflowsWindow(
            for: activities,
            metrics: metrics,
            panelMetrics: panelMetrics,
            topInset: topInset
        )

        itemStack
            .padding(metrics.panel.contentInset)
            .frame(width: size.width, height: size.height, alignment: .top)
            .modifier(ScrollWhenTaller(isEnabled: scrolls))
            .foregroundStyle(surface.foreground.style)
            .background {
                surface.fill(
                    in: RoundedRectangle(
                        cornerRadius: metrics.panel.cornerRadius,
                        style: .continuous
                    )
                )
            }
            .environment(\.colorScheme, surface.preferredColorScheme)
    }

    private var itemStack: some View {
        VStack(alignment: .leading, spacing: metrics.panel.rowSpacing) {
            ForEach(activities, id: \.identity) { activity in
                item(for: activity)
            }
        }
    }

    @ViewBuilder
    private func item(for activity: any Activity) -> some View {
        switch expandedItemRenderer(for: activity) {
        case .music:
            if let music = activity as? MusicActivity {
                MusicExpandedView(
                    activity: music,
                    metrics: metrics.music,
                    panelMetrics: panelMetrics,
                    onTransport: onMusicTransport,
                    onPrimaryAction: { onPrimaryAction(activity.identity) }
                )
            } else {
                genericRow(for: activity)
            }
        case .timer:
            if let timer = activity as? TimerActivity {
                TimerExpandedView(
                    activity: timer,
                    metrics: metrics.timer,
                    panelMetrics: panelMetrics,
                    onCommand: onTimerCommand
                )
            } else {
                genericRow(for: activity)
            }
        case .aiAgent:
            if let agent = activity as? AIAgentActivity {
                AIAgentActivityView(
                    activity: agent,
                    metrics: metrics.aiAgent,
                    panelMetrics: panelMetrics,
                    onPrimaryAction: { onPrimaryAction(activity.identity) }
                )
            } else {
                genericRow(for: activity)
            }
        case .charging:
            if let charging = activity as? ChargingActivity {
                ChargingActivityView(activity: charging, metrics: metrics.panel)
            } else {
                genericRow(for: activity)
            }
        case .genericRow:
            genericRow(for: activity)
        }
    }

    private func genericRow(for activity: any Activity) -> some View {
        GenericActivityRowView(
            row: ExpandedRow(activity: activity),
            metrics: metrics.panel,
            colorScheme: colorScheme,
            reduceTransparency: reduceTransparency,
            onPrimaryAction: onPrimaryAction
        )
    }
}

/// The fallback card: the generic glyph-and-label row with its own surface, so
/// a set of unknown kinds reads as the same stack of cards as the per-kind
/// views beside it.
private struct GenericActivityRowView: View {
    let row: ExpandedRow
    let metrics: ExpandedPanelMetrics
    let colorScheme: ColorScheme
    let reduceTransparency: Bool
    let onPrimaryAction: (ActivityIdentity) -> Void

    var body: some View {
        let surface = islandExpandedSurface(
            scheme: colorScheme.islandColorScheme,
            reduceTransparency: reduceTransparency
        )

        HStack(spacing: metrics.rowSpacing) {
            Image(systemName: row.symbolName)
                .font(.system(size: metrics.symbolSize, weight: .medium))
                .frame(width: metrics.symbolColumnWidth)

            Text(row.title)
                .font(.system(size: metrics.symbolSize, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)

            if let action = row.primaryAction {
                Button {
                    onPrimaryAction(ActivityIdentity(row.id))
                } label: {
                    Label(action.title, systemImage: action.symbolName)
                        .font(.system(size: metrics.symbolSize - 2, weight: .semibold))
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }
        }
        .padding(metrics.contentInset)
        .frame(height: metrics.rowHeight)
        .foregroundStyle(surface.foreground.style)
        .background {
            surface.fill(in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        }
        .environment(\.colorScheme, surface.preferredColorScheme)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// Makes the list scrollable only once it is taller than the allocated window.
/// Wrapping unconditionally would give every expanded panel a scroll view's
/// clipping and bounce behaviour even when everything already fits.
private struct ScrollWhenTaller: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            ScrollView(.vertical) { content }
        } else {
            content
        }
    }
}
