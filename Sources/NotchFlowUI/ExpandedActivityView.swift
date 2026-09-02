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
        let recording = (activity as? RecordingActivity).map(RecordingPresentation.init)
        symbolName = recording?.symbolName ?? compactSymbolName(activity.kind)
        title = recording?.title ?? compactAccessibilityLabel(activity.kind)
        primaryAction = activity.primaryAction
        accessibilityLabel =
            recording?.accessibilityLabel
            ?? compactAccessibilityLabel(activity.kind)
    }
}

/// One drawn item of the expanded panel: an ordinary activity, or one AI agent
/// instance standing for its root session and every sub-agent under it.
struct ExpandedActivityItem: Identifiable {
    let id: String
    let activity: (any Activity)?
    let aiAgentInstance: AIAgentInstance?

    fileprivate init(activity: any Activity) {
        id = activity.identity.rawValue
        self.activity = activity
        aiAgentInstance = nil
    }

    fileprivate init(aiAgentInstance: AIAgentInstance) {
        id = aiAgentInstance.id
        activity = nil
        self.aiAgentInstance = aiAgentInstance
    }

    /// Holds an instance's place in the list while its sessions are still being
    /// collected, so the panel's order follows first appearance rather than
    /// dictionary order.
    fileprivate init(placeholderInstanceIdentity: ActivityIdentity) {
        id = placeholderInstanceIdentity.rawValue
        activity = nil
        aiAgentInstance = nil
    }
}

/// The expanded panel's fixed visual budget, the counterpart to
/// `CompactPillMetrics` — one edit changes the expanded density.
public struct ExpandedPanelMetrics: Equatable, Sendable {
    public static let `default` = ExpandedPanelMetrics()

    public let rowHeight: CGFloat
    /// The vertical gap between two items: the space between cards when each
    /// draws its own surface, and the band the hairline separator sits in when
    /// they share one.
    public let rowSpacing: CGFloat
    /// The horizontal gap inside one row, between its glyph, its text, and its
    /// trailing control. Separate from `rowSpacing` because the two answer to
    /// different things — a divider needs room to breathe, a glyph and its label
    /// need to stay together.
    public let columnSpacing: CGFloat
    public let contentInset: CGFloat
    public let symbolSize: CGFloat
    public let symbolColumnWidth: CGFloat
    public let cornerRadius: CGFloat
    public let width: CGFloat

    public init(
        rowHeight: CGFloat = 34,
        rowSpacing: CGFloat = 9,
        columnSpacing: CGFloat = 4,
        contentInset: CGFloat = 12,
        symbolSize: CGFloat = 15,
        symbolColumnWidth: CGFloat = 24,
        cornerRadius: CGFloat = 18,
        width: CGFloat = 320
    ) {
        self.rowHeight = rowHeight
        self.rowSpacing = rowSpacing
        self.columnSpacing = columnSpacing
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
    case recording
    case genericRow
}

public func expandedItemRenderer(for activity: any Activity) -> ExpandedItemRenderer {
    switch activity {
    case is MusicActivity: .music
    case is TimerActivity: .timer
    case is AIAgentActivity: .aiAgent
    case is ChargingActivity: .charging
    case is RecordingActivity: .recording
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
        // The agent card is a glyph-height card, not a text row, and drawing it
        // at `rowHeight` under-reports it by the difference. The panel is sized
        // from these numbers, so the shortfall lands as clipping at the bottom
        // of the island rather than as a smaller card.
        return aiAgentExpandedSize(
            hasProgress: (activity as? AIAgentActivity)?.progress != nil,
            metrics: metrics.aiAgent,
            panelMetrics: panelMetrics
        ).height
    case .charging, .recording, .genericRow:
        return metrics.panel.rowHeight
    }
}

/// The panel's items: every non-AI activity as itself, and every AI session
/// folded into the instance that owns it.
///
/// Instances appear in the order their most urgent session does, so an instance
/// whose sub-agent is waiting on the user rises to the top of the panel without
/// the sub-agent getting a card of its own.
func expandedActivityItems(
    for activities: [any Activity],
    registrationTimes: [ActivityIdentity: Date] = [:]
) -> [ExpandedActivityItem] {
    var instanceIndexes: [ActivityIdentity: Int] = [:]
    var items: [ExpandedActivityItem] = []
    var sessionsByInstance: [ActivityIdentity: [AIAgentActivity]] = [:]

    for activity in activities {
        guard let session = activity as? AIAgentActivity else {
            items.append(ExpandedActivityItem(activity: activity))
            continue
        }

        let instanceIdentity = session.compactInstanceIdentity
        sessionsByInstance[instanceIdentity, default: []].append(session)
        if instanceIndexes[instanceIdentity] == nil {
            instanceIndexes[instanceIdentity] = items.count
            items.append(ExpandedActivityItem(placeholderInstanceIdentity: instanceIdentity))
        }
    }

    let ordinals = aiAgentInstanceOrdinals(
        for: sessionsByInstance,
        registrationTimes: registrationTimes
    )

    for (instanceIdentity, sessions) in sessionsByInstance {
        guard let index = instanceIndexes[instanceIdentity], let first = sessions.first else {
            continue
        }
        items[index] = ExpandedActivityItem(
            aiAgentInstance: AIAgentInstance(
                agentID: first.agent,
                rootSessionID: first.rootSessionID,
                sessions: sessions,
                ordinal: ordinals[instanceIdentity]
            )
        )
    }

    return items
}

/// A stable number for each concurrent instance of the same agent, absent for
/// any agent running only one.
///
/// Ordered by the instance's earliest registration rather than by the list
/// order, which sorts by urgency: numbering from the list would renumber the
/// cards whenever one instance changed state, so "OpenCode 1" would become
/// "OpenCode 2" without any instance having started or ended. An instance that
/// ends does still close its number and shift the ones after it — unavoidable
/// for an ordinal, and rare beside a state change.
func aiAgentInstanceOrdinals(
    for sessionsByInstance: [ActivityIdentity: [AIAgentActivity]],
    registrationTimes: [ActivityIdentity: Date]
) -> [ActivityIdentity: Int] {
    func startTime(of sessions: [AIAgentActivity]) -> Date {
        sessions.compactMap { registrationTimes[$0.identity] }.min() ?? .distantPast
    }

    var instancesByAgent: [IPCAgentID: [(identity: ActivityIdentity, sessions: [AIAgentActivity])]] =
        [:]
    for (identity, sessions) in sessionsByInstance {
        guard let agent = sessions.first?.agent else { continue }
        instancesByAgent[agent, default: []].append((identity, sessions))
    }

    var ordinals: [ActivityIdentity: Int] = [:]
    for instances in instancesByAgent.values where instances.count > 1 {
        let ordered = instances.sorted { left, right in
            let leftTime = startTime(of: left.sessions)
            let rightTime = startTime(of: right.sessions)
            guard leftTime == rightTime else { return leftTime < rightTime }
            // Two instances registered in the same instant still need a stable
            // order, or their numbers swap between renders of identical state.
            return left.identity.rawValue < right.identity.rawValue
        }
        for (index, instance) in ordered.enumerated() {
            ordinals[instance.identity] = index + 1
        }
    }
    return ordinals
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
    disclosedInstances: Set<ActivityIdentity> = [],
    registrationTimes: [ActivityIdentity: Date] = [:],
    metrics: ExpandedItemMetrics = .default,
    panelMetrics: PanelMetrics = .default,
    topInset: CGFloat = 0
) -> CGSize {
    let items = expandedActivityItems(for: activities, registrationTimes: registrationTimes)
    guard !items.isEmpty else { return .zero }

    let heights = items.map {
        expandedItemHeight(
            for: $0,
            disclosedInstances: disclosedInstances,
            metrics: metrics,
            panelMetrics: panelMetrics
        )
    }
    let spacing = CGFloat(items.count - 1) * metrics.panel.rowSpacing
    let height = heights.reduce(0, +) + spacing + metrics.panel.contentInset * 2

    // The inset is applied on both axes by the view's `.padding`, so the width
    // has to carry it too. Sizing the frame to the bare card width squeezes
    // every card by twice the inset — enough to push a trailing control button
    // outside the frame and make it unclickable.
    let widest =
        items.map { expandedItemWidth(for: $0, metrics: metrics, panelMetrics: panelMetrics) }
        .max() ?? metrics.panel.width
    let width = widest + metrics.panel.contentInset * 2

    let availableHeight = max(panelMetrics.maximumExpandedSize.height - max(topInset, 0), 0)
    return CGSize(
        width: min(width, panelMetrics.maximumExpandedSize.width),
        height: min(height, availableHeight)
    )
}

private func expandedItemHeight(
    for item: ExpandedActivityItem,
    disclosedInstances: Set<ActivityIdentity>,
    metrics: ExpandedItemMetrics,
    panelMetrics: PanelMetrics
) -> CGFloat {
    if let instance = item.aiAgentInstance {
        return aiAgentExpandedSize(
            hasProgress: instance.representative.progress != nil,
            subagentCount: instance.subagents.count,
            isDisclosed: disclosedInstances.contains(instance.identity),
            metrics: metrics.aiAgent,
            panelMetrics: panelMetrics
        ).height
    }
    guard let activity = item.activity else { return 0 }
    return expandedItemHeight(for: activity, metrics: metrics, panelMetrics: panelMetrics)
}

private func expandedItemWidth(
    for item: ExpandedActivityItem,
    metrics: ExpandedItemMetrics,
    panelMetrics: PanelMetrics
) -> CGFloat {
    if item.aiAgentInstance != nil {
        return aiAgentExpandedSize(
            hasProgress: false,
            metrics: metrics.aiAgent,
            panelMetrics: panelMetrics
        ).width
    }
    guard let activity = item.activity else { return 0 }
    return expandedItemWidth(for: activity, metrics: metrics, panelMetrics: panelMetrics)
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
    case .charging, .recording, .genericRow:
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
    disclosedInstances: Set<ActivityIdentity> = [],
    registrationTimes: [ActivityIdentity: Date] = [:],
    metrics: ExpandedItemMetrics = .default,
    panelMetrics: PanelMetrics = .default,
    topInset: CGFloat = 0
) -> Bool {
    let items = expandedActivityItems(for: activities, registrationTimes: registrationTimes)
    guard !items.isEmpty else { return false }

    let heights = items.map {
        expandedItemHeight(
            for: $0,
            disclosedInstances: disclosedInstances,
            metrics: metrics,
            panelMetrics: panelMetrics
        )
    }
    let spacing = CGFloat(items.count - 1) * metrics.panel.rowSpacing
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.drawsOwnIslandSurface) private var drawsOwnSurface

    private let activities: [any Activity]
    private let metrics: ExpandedItemMetrics
    private let panelMetrics: PanelMetrics
    private let topInset: CGFloat
    private let onPrimaryAction: (ActivityIdentity) -> Void
    private let onMusicTransport: (MusicTransportCommand) -> Void
    private let onTimerCommand: (TimerControlCommand) -> Void

    /// When each activity registered, used only to number the concurrent
    /// instances of one agent in the order they appeared.
    ///
    /// Supplied from outside rather than derived here because the view is handed
    /// activities, not the manager that has been keeping their start times.
    private let registrationTimes: [ActivityIdentity: Date]

    /// Which instances are showing their sub-agents.
    ///
    /// Bound from outside rather than held here as `@State`: the island's black
    /// surface is sized by an ancestor, and while this view owned the set
    /// privately that ancestor sized the surface for closed cards. Opening one
    /// then drew its sub-agent rows past the bottom of the island onto the
    /// desktop.
    @Binding private var disclosedInstances: Set<ActivityIdentity>

    public init(
        activities: [any Activity],
        registrationTimes: [ActivityIdentity: Date] = [:],
        disclosedInstances: Binding<Set<ActivityIdentity>> = .constant([]),
        metrics: ExpandedItemMetrics = .default,
        panelMetrics: PanelMetrics = .default,
        topInset: CGFloat = 0,
        onPrimaryAction: @escaping (ActivityIdentity) -> Void = { _ in },
        onMusicTransport: @escaping (MusicTransportCommand) -> Void = { _ in },
        onTimerCommand: @escaping (TimerControlCommand) -> Void = { _ in }
    ) {
        self.activities = activities
        self.registrationTimes = registrationTimes
        _disclosedInstances = disclosedInstances
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
            disclosedInstances: disclosedInstances,
            registrationTimes: registrationTimes,
            metrics: metrics,
            panelMetrics: panelMetrics,
            topInset: topInset
        )
        let scrolls = expandedPanelOverflowsWindow(
            for: activities,
            disclosedInstances: disclosedInstances,
            registrationTimes: registrationTimes,
            metrics: metrics,
            panelMetrics: panelMetrics,
            topInset: topInset
        )

        // Height goes on the scroll container, never on the content: forcing the
        // content to the clamped height left the scroll view with nothing longer
        // than itself to scroll, so a list that overflowed was simply cut off at
        // both ends instead of scrolling.
        itemStack
            .padding(metrics.panel.contentInset)
            .frame(width: size.width, alignment: .top)
            .modifier(ScrollWhenTaller(isEnabled: scrolls, height: size.height))
            .foregroundStyle(surface.foreground.style)
            .background {
                if drawsOwnSurface {
                    surface.fill(
                        in: RoundedRectangle(
                            cornerRadius: metrics.panel.cornerRadius,
                            style: .continuous
                        )
                    )
                }
            }
            .environment(\.colorScheme, surface.preferredColorScheme)
            .animation(disclosureAnimation, value: disclosedInstances)
    }

    /// The items, separated the way the surface they sit on calls for.
    ///
    /// Sharing the island's surface, the panel is one sheet and the items are
    /// its rows: a hairline between them reads as a list. Drawing their own
    /// surfaces they are cards, and a gap is what separates cards. The gap is
    /// `rowSpacing` either way, so the panel's height model does not change with
    /// the treatment.
    ///
    /// One item per instance, not per session: the sub-agents an instance
    /// spawned live in the list its card can open, because a session the agent
    /// created to delegate work is not a second agent the user is running.
    private var itemStack: some View {
        let items = expandedActivityItems(
            for: activities,
            registrationTimes: registrationTimes
        )

        return VStack(alignment: .leading, spacing: drawsOwnSurface ? metrics.panel.rowSpacing : 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if drawsOwnSurface == false, index > 0 {
                    IslandItemSeparator(height: metrics.panel.rowSpacing)
                }
                itemView(for: item)
            }
        }
    }

    @ViewBuilder
    private func itemView(for item: ExpandedActivityItem) -> some View {
        if let instance = item.aiAgentInstance {
            AIAgentActivityView(
                instance: instance,
                metrics: metrics.aiAgent,
                panelMetrics: panelMetrics,
                isDisclosed: disclosedInstances.contains(instance.identity),
                onToggleDisclosure: { toggleDisclosure(for: instance.identity) },
                onPrimaryAction: { onPrimaryAction(instance.representative.identity) }
            )
        } else if let activity = item.activity {
            itemView(for: activity)
        }
    }

    private var disclosureAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    private func toggleDisclosure(for instance: ActivityIdentity) {
        if disclosedInstances.contains(instance) {
            disclosedInstances.remove(instance)
        } else {
            disclosedInstances.insert(instance)
        }
    }

    @ViewBuilder
    private func itemView(for activity: any Activity) -> some View {
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
        case .recording:
            if let recording = activity as? RecordingActivity {
                RecordingActivityView(activity: recording, metrics: metrics.panel)
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

        HStack(spacing: metrics.columnSpacing) {
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
        .foregroundStyle(surface.foreground.style)
        .islandCard(
            width: metrics.width,
            height: metrics.rowHeight,
            cornerRadius: metrics.cornerRadius,
            surface: surface
        )
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
    /// The visible height. Applied to the scroll container, never to the content
    /// inside it — content clamped to the viewport is content with nothing left
    /// to scroll.
    let height: CGFloat

    func body(content: Content) -> some View {
        if isEnabled {
            ScrollView(.vertical) { content }
                .frame(height: height)
                // Hidden: an overlay this small reads as chrome-free, and a
                // scroller pinned inside a rounded black card looks like a
                // scratch on it. The list scrolls on trackpad and wheel either
                // way.
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
        } else {
            content.frame(height: height, alignment: .top)
        }
    }
}
