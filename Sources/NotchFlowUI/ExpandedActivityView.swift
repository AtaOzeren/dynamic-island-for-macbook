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

/// One row per active activity, in the manager's priority-then-registration
/// order. Unlike `compactSlots(for:)` this applies no capacity limit: expansion
/// exists precisely so nothing is truncated.
public func expandedRows(for activities: [any Activity]) -> [ExpandedRow] {
    activities.map(ExpandedRow.init(activity:))
}

/// The expanded panel's drawn size, clamped to the window's allocated maximum.
///
/// The clamp matters because the `NSPanel` frame is allocated once at
/// `PanelMetrics.maximumExpandedSize` and never resized (`docs/04-overlay-window.md`);
/// a list that grew past it would be drawn outside the window and silently
/// clipped, which is the one way the "never truncates" rule could be broken by
/// geometry rather than by policy.
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

/// Whether `rowCount` rows still fit the allocated window at these metrics.
/// Once this goes false the list scrolls rather than being cut off.
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

/// The expanded list: every active activity in priority order, growing downward
/// from the notch, per the expanded row of the state table in
/// `docs/04-overlay-window.md`.
public struct ExpandedActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let activities: [any Activity]
    private let metrics: ExpandedPanelMetrics
    private let panelMetrics: PanelMetrics
    private let onPrimaryAction: (ActivityIdentity) -> Void

    public init(
        activities: [any Activity],
        metrics: ExpandedPanelMetrics = .default,
        panelMetrics: PanelMetrics = .default,
        onPrimaryAction: @escaping (ActivityIdentity) -> Void = { _ in }
    ) {
        self.activities = activities
        self.metrics = metrics
        self.panelMetrics = panelMetrics
        self.onPrimaryAction = onPrimaryAction
    }

    public var body: some View {
        let rows = expandedRows(for: activities)
        let size = expandedPanelSize(
            rowCount: rows.count,
            metrics: metrics,
            panelMetrics: panelMetrics
        )
        let scrolls = expandedPanelOverflowsWindow(
            rowCount: rows.count,
            metrics: metrics,
            panelMetrics: panelMetrics
        )

        let surface = islandExpandedSurface(
            scheme: colorScheme.islandColorScheme,
            reduceTransparency: reduceTransparency
        )

        rowList(rows)
            .padding(metrics.contentInset)
            .frame(width: size.width, height: size.height, alignment: .top)
            .foregroundStyle(surface.foreground.style)
            .background {
                surface.fill(in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            }
            .modifier(ScrollWhenTaller(isEnabled: scrolls))
    }

    private func rowList(_ rows: [ExpandedRow]) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            ForEach(rows) { row in
                rowView(row)
            }
        }
    }

    private func rowView(_ row: ExpandedRow) -> some View {
        HStack(spacing: metrics.rowSpacing) {
            Image(systemName: row.symbolName)
                .font(.system(size: metrics.symbolSize, weight: .medium))
                .frame(width: metrics.symbolColumnWidth)

            Text(row.title)
                .font(.system(size: metrics.symbolSize, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)

            if let action = row.primaryAction {
                primaryActionButton(action, for: row)
            }
        }
        .frame(height: metrics.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private func primaryActionButton(_ action: PrimaryAction, for row: ExpandedRow) -> some View {
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
