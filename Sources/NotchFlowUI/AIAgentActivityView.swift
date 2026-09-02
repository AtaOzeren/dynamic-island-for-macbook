import AppKit
import CoreGraphics
import Foundation
import NotchFlowCore
import SwiftUI

/// Everything the AI agent views draw, derived from `AIAgentActivity` alone.
///
/// The type is the privacy rule's last enforcement point: it exposes agent
/// identity, short status text, and an optional fraction, and it is built from an
/// activity that carries no prompt, no code, and no transcript to begin with.
/// `docs/07-ai-integration.md` forbids any of that reaching the screen, and a
/// view cannot render what this presentation has no field for.
public struct AIAgentPresentation: Equatable, Sendable {
    public let state: AIAgentState
    public let agentID: IPCAgentID
    public let agentName: String
    /// The envelope's `detail` line, or `nil` when the agent sent an empty one —
    /// so the expanded view drops the line rather than drawing a blank row.
    public let detail: String?
    public let toolName: String?
    public let progress: Double?
    public let primaryAction: PrimaryAction?

    /// `instanceOrdinal` numbers this instance among the concurrent instances of
    /// the same agent, and is `nil` when the agent has only one — two cards both
    /// reading "OpenCode · Working…" are two cards the user cannot tell apart,
    /// while a lone agent has nothing to be distinguished from.
    public init(activity: AIAgentActivity, instanceOrdinal: Int? = nil) {
        state = activity.state
        agentID = activity.agent
        agentName = Self.name(of: activity.agent, instanceOrdinal: instanceOrdinal)
        detail = activity.detail.isEmpty ? nil : activity.detail
        toolName = activity.toolName
        progress = activity.progress
        primaryAction = activity.primaryAction
    }

    private static func name(of agentID: IPCAgentID, instanceOrdinal: Int?) -> String {
        guard let instanceOrdinal else { return agentID.displayName }
        return localized(
            "activity.ai.sessionName",
            default: "\(agentID.displayName) \(instanceOrdinal)"
        )
    }

    /// The state in words, as the island says it.
    ///
    /// `usingTool` names the tool when the agent sent one — "Running Bash…"
    /// rather than the generic phrasing.
    public var statusText: String {
        switch state {
        case .idle: localized("Idle")
        case .thinking: localized("Thinking…")
        case .working: localized("Working…")
        case .usingTool: toolName.map { localized("Running \($0)…") } ?? localized("Running tool…")
        case .waitingForUser: localized("Needs your input")
        case .completed: localized("Task completed")
        case .error: localized("Task error")
        }
    }

    /// The minimal card's status line: agent and state separated by a middle dot.
    public var compactTitle: String {
        localized("activity.ai.compactTitle", default: "\(agentName) · \(statusText)")
    }

    /// What VoiceOver reads for the whole activity: the compact line, with the
    /// detail appended when there is one to append.
    public var accessibilityLabel: String {
        guard let detail else { return compactTitle }
        return localized("activity.accessibility.headlineAndDetail", default: "\(compactTitle), \(detail)")
    }
}

/// One thing the user started — a terminal, an editor window, a conversation —
/// together with every sub-agent it spawned.
///
/// The expanded panel draws one card per instance rather than one per session,
/// because a session an agent created to delegate work is not something the user
/// started and does not deserve a card of its own. Those sessions live in the
/// list this card can disclose.
struct AIAgentInstance: Identifiable, Equatable, Sendable {
    let agentID: IPCAgentID
    let rootSessionID: UUID
    /// Every session belonging to this instance, guaranteed non-empty.
    ///
    /// The instance exists because a session reported it, so there is always at
    /// least one; taking that as an initialiser precondition is what lets
    /// `representative` be a value rather than an optional every call site has
    /// to unwrap into a fallback it cannot supply.
    let sessions: [AIAgentActivity]
    /// This instance's number among the concurrent instances of the same agent,
    /// absent when the agent is running only one.
    let ordinal: Int?

    init(
        agentID: IPCAgentID,
        rootSessionID: UUID,
        sessions: [AIAgentActivity],
        ordinal: Int? = nil
    ) {
        precondition(sessions.isEmpty == false, "an instance is created by a session reporting")
        self.agentID = agentID
        self.rootSessionID = rootSessionID
        self.sessions = sessions
        self.ordinal = ordinal
    }

    var id: String { identity.rawValue }

    var identity: ActivityIdentity {
        AIAgentActivity.instanceIdentity(agent: agentID, rootSessionID: rootSessionID)
    }

    /// The session the user started, when the island has actually seen it.
    ///
    /// `nil` is a real case, not a defensive one: a sub-agent's messages can
    /// arrive before its parent's — a fresh turn that delegates immediately
    /// sends `usingTool` for the child before the parent says anything — and a
    /// card that refused to draw until the parent reported would leave the
    /// island blank while work was plainly running.
    var root: AIAgentActivity? { sessions.first { $0.isSubagent == false } }

    /// The sessions the agent spawned, in the order they first appeared.
    var subagents: [AIAgentActivity] { sessions.filter(\.isSubagent) }

    /// Whether the card offers a list to open. A card with nothing behind it
    /// draws no control, so the user never clicks one open onto nothing.
    var showsDisclosure: Bool { subagents.isEmpty == false }

    /// The session the card speaks for: the most urgent of them, sub-agents
    /// included.
    ///
    /// A sub-agent waiting on a permission prompt blocks the whole instance, so
    /// the card has to say so without being opened first — surfacing that is the
    /// entire reason the island watches agents at all.
    var representative: AIAgentActivity {
        sessions.dropFirst().reduce(sessions[0]) { current, candidate in
            candidate.compactRepresentationPriority > current.compactRepresentationPriority
                ? candidate
                : current
        }
    }
}

/// One row of an instance's sub-agent list.
struct AIAgentSubagentPresentation: Equatable, Sendable {
    let name: String
    let statusText: String
    let detail: String?
    let indicator: AIAgentCompactIndicator

    /// `fallbackOrdinal` names a sub-agent whose agent did not send one — the
    /// row still has to say *which* sub-agent it is.
    init(activity: AIAgentActivity, fallbackOrdinal: Int) {
        let presentation = AIAgentPresentation(activity: activity)
        name =
            activity.sessionName?.isEmpty == false
            ? activity.sessionName ?? ""
            : localized("activity.ai.subagentFallbackName", default: "Agent \(fallbackOrdinal)")
        statusText = presentation.statusText
        detail = presentation.detail
        indicator = AIAgentCompactIndicator(state: activity.state)
    }

    var title: String {
        localized("activity.ai.compactTitle", default: "\(name) · \(statusText)")
    }

    var accessibilityLabel: String {
        guard let detail else { return title }
        return localized("activity.accessibility.headlineAndDetail", default: "\(title), \(detail)")
    }
}

enum AIAgentCompactBadgeTone: Equatable, Sendable {
    case yellow
    case red
    case green
}

enum AIAgentCompactIndicator: Equatable, Sendable {
    case none
    case working
    case question
    case error
    case completed

    init(state: AIAgentState) {
        switch state {
        case .idle:
            self = .none
        case .thinking, .working, .usingTool:
            self = .working
        case .waitingForUser:
            self = .question
        case .error:
            self = .error
        case .completed:
            self = .completed
        }
    }

    var symbolName: String? {
        switch self {
        case .question: "questionmark"
        case .error: "exclamationmark"
        case .completed: "checkmark"
        case .none, .working: nil
        }
    }

    var badgeTone: AIAgentCompactBadgeTone? {
        switch self {
        case .question: .yellow
        case .error: .red
        case .completed: .green
        case .none, .working: nil
        }
    }
}

struct CompactAIAgentSlotPresentation: Equatable, Sendable {
    let agentID: IPCAgentID
    let state: AIAgentState
    let indicator: AIAgentCompactIndicator
    /// How many concurrent sessions of this agent the slot stands for.
    ///
    /// One compact icon covers every session of one agent, so without this the
    /// pill cannot tell a single terminal apart from three — and the state it
    /// draws is only the most urgent session's, which says nothing about the
    /// others still running behind it.
    let sessionCount: Int

    init(activity: AIAgentActivity, sessionCount: Int = 1) {
        agentID = activity.agent
        state = activity.state
        indicator = AIAgentCompactIndicator(state: activity.state)
        self.sessionCount = max(1, sessionCount)
    }

    /// Whether the slot draws the count badge at all.
    ///
    /// A badge reading "1" on the overwhelmingly common single-session case
    /// would be a number the user has to read to learn nothing.
    var showsSessionCount: Bool { sessionCount > 1 }
}

/// The drawn box for one agent's compact slot: the logo, room beneath it for the
/// status indicator, and the corner the session-count badge hangs in.
///
/// The same for every state and every session count on purpose. The status
/// indicator always sits under the icon and the count badge's corner is always
/// reserved, so the slot never changes size with what the agent happens to be
/// doing or with how many of it are running — a pill that reflowed each time an
/// agent asked a question, or each time a second terminal opened, was a pill
/// whose icons appeared to jump sideways.
func compactAIAgentIconSize(iconSize: CGFloat, state _: AIAgentState) -> CGSize {
    let metrics = CompactAIAgentMetrics.default
    return CGSize(
        width: max(
            iconSize + metrics.countBadgeOverhang * 2,
            metrics.travelDistance + metrics.dotDiameter
        ),
        height: metrics.countBadgeOverhang + iconSize + metrics.badgeDiameter + 1
    )
}

struct CompactAIAgentMetrics: Equatable, Sendable {
    static let `default` = CompactAIAgentMetrics()

    let dotDiameter: CGFloat = 3
    let travelDistance: CGFloat = 8
    let oneWayDuration: TimeInterval = 0.65
    let badgeDiameter: CGFloat = 7
    let badgeSymbolSize: CGFloat = 5
    /// The session-count badge that rides the icon's top-right corner.
    ///
    /// Bigger than the status badge below the icon because it carries a numeral
    /// rather than a glyph, and a numeral drawn at the status badge's size is
    /// unreadable at the notch's distance.
    let countBadgeDiameter: CGFloat = 10
    let countBadgeTextSize: CGFloat = 7
    /// The ring that separates the badge from the logo underneath it.
    ///
    /// Drawn in the pill's own black rather than left off: OpenCode's logo is a
    /// white square, and a white badge sitting on it merged into one shape with
    /// no edge at all. A dark ring reads against every agent's artwork because
    /// it is the surface the pill is already made of.
    let countBadgeRingWidth: CGFloat = 1
    /// How far the count badge hangs past the icon on the top and trailing
    /// edges. Reserved in the slot's box whether or not a badge is drawn, so a
    /// second session appearing never shifts the icons already on screen.
    let countBadgeOverhang: CGFloat = 3
    /// The highest count the badge spells out before falling back to "9+".
    let countBadgeCeiling = 9

    private init() {}
}

/// What the count badge reads.
///
/// Capped rather than allowed to grow, because the badge is a fixed circle: a
/// three-digit count would either overflow the pill or shrink to illegibility,
/// and past a handful of sessions the exact number stops being actionable —
/// "more than nine" is the same instruction as "twelve".
func compactAIAgentCountBadgeText(_ sessionCount: Int) -> String {
    sessionCount > CompactAIAgentMetrics.default.countBadgeCeiling
        ? localized("activity.ai.sessionCountOverflow", default: "9+")
        : "\(sessionCount)"
}

func compactAIAgentWorkingDotOffset(
    at elapsedTime: TimeInterval,
    reduceMotion: Bool
) -> CGFloat {
    guard reduceMotion == false else { return 0 }

    let metrics = CompactAIAgentMetrics.default
    let cycleDuration = metrics.oneWayDuration * 2
    var cycleTime = elapsedTime.truncatingRemainder(dividingBy: cycleDuration)
    if cycleTime < 0 {
        cycleTime += cycleDuration
    }

    let outwardProgress = cycleTime / metrics.oneWayDuration
    let linearProgress = outwardProgress <= 1 ? outwardProgress : 2 - outwardProgress
    let easedProgress = (1 - cos(.pi * linearProgress)) / 2
    return -metrics.travelDistance / 2 + metrics.travelDistance * CGFloat(easedProgress)
}

/// The AI activity's compact slot carries the originating agent identity so the
/// pill can render Claude, Codex, or OpenCode instead of generic AI sparkles.
///
/// `sessionCount` is how many concurrent sessions of this agent the slot stands
/// in for; the drawn `activity` is only the most urgent of them.
public func aiAgentCompactSlot(
    for activity: AIAgentActivity,
    sessionCount: Int = 1
) -> CompactSlot {
    let presentation = AIAgentPresentation(activity: activity)
    let slotPresentation = CompactAIAgentSlotPresentation(
        activity: activity,
        sessionCount: sessionCount
    )
    return CompactSlot(
        activity: activity,
        id: activity.compactGroupIdentity,
        accessibilityLabel: aiAgentCompactAccessibilityLabel(
            presentation: presentation,
            slotPresentation: slotPresentation
        ),
        aiAgentPresentation: slotPresentation
    )
}

/// What VoiceOver reads for one agent slot.
///
/// The count is spoken rather than left to the badge, because the badge is the
/// only place the other sessions exist on the compact pill and a hidden numeral
/// is a session the screen reader never mentions.
private func aiAgentCompactAccessibilityLabel(
    presentation: AIAgentPresentation,
    slotPresentation: CompactAIAgentSlotPresentation
) -> String {
    guard slotPresentation.showsSessionCount else { return presentation.accessibilityLabel }
    let sessionCount = localized("\(slotPresentation.sessionCount) sessions")
    return localized(
        "activity.accessibility.headlineAndDetail",
        default: "\(presentation.accessibilityLabel), \(sessionCount)"
    )
}

/// The expanded AI view's visual budget, the AI counterpart to
/// `MusicViewMetrics` — one edit changes the agent row's density.
public struct AIAgentViewMetrics: Equatable, Sendable {
    public static let `default` = AIAgentViewMetrics()

    public let glyphSize: CGFloat
    public let contentInset: CGFloat
    public let textSpacing: CGFloat
    public let columnSpacing: CGFloat
    public let titleSize: CGFloat
    public let detailSize: CGFloat
    public let progressBarHeight: CGFloat
    public let cornerRadius: CGFloat
    public let width: CGFloat
    /// One sub-agent row in the disclosed list.
    public let subagentRowHeight: CGFloat
    public let subagentSeparatorHeight: CGFloat
    public let subagentNameSize: CGFloat
    public let subagentDetailSize: CGFloat
    public let disclosureControlHeight: CGFloat

    public init(
        glyphSize: CGFloat = 24,
        contentInset: CGFloat = 8,
        textSpacing: CGFloat = 2,
        columnSpacing: CGFloat = 8,
        titleSize: CGFloat = IslandTypeScale.default.title,
        detailSize: CGFloat = IslandTypeScale.default.detail,
        progressBarHeight: CGFloat = 3,
        cornerRadius: CGFloat = 16,
        width: CGFloat = 276,
        subagentRowHeight: CGFloat = 24,
        subagentSeparatorHeight: CGFloat = 1,
        subagentNameSize: CGFloat = IslandTypeScale.default.nestedTitle,
        subagentDetailSize: CGFloat = IslandTypeScale.default.nestedDetail,
        disclosureControlHeight: CGFloat = 18
    ) {
        self.glyphSize = glyphSize
        self.contentInset = contentInset
        self.textSpacing = textSpacing
        self.columnSpacing = columnSpacing
        self.titleSize = titleSize
        self.detailSize = detailSize
        self.progressBarHeight = progressBarHeight
        self.cornerRadius = cornerRadius
        self.width = width
        self.subagentRowHeight = subagentRowHeight
        self.subagentSeparatorHeight = subagentSeparatorHeight
        self.subagentNameSize = subagentNameSize
        self.subagentDetailSize = subagentDetailSize
        self.disclosureControlHeight = disclosureControlHeight
    }
}

/// How much taller a card gets when its sub-agent list is open.
///
/// Zero for a closed card and for one with nothing to disclose, so the panel's
/// height model needs no special case for the ordinary single-session instance.
public func aiAgentDisclosureHeight(
    subagentCount: Int,
    isDisclosed: Bool,
    metrics: AIAgentViewMetrics = .default
) -> CGFloat {
    guard isDisclosed, subagentCount > 0 else { return 0 }
    return metrics.subagentSeparatorHeight + CGFloat(subagentCount) * metrics.subagentRowHeight
}

/// The expanded AI view's drawn size, clamped to the window's allocated maximum
/// for the same reason `musicExpandedSize` clamps: the `NSPanel` frame is
/// allocated once and never resized, so anything past it is silently clipped.
public func aiAgentExpandedSize(
    hasProgress: Bool,
    subagentCount: Int = 0,
    isDisclosed: Bool = false,
    metrics: AIAgentViewMetrics = .default,
    panelMetrics: PanelMetrics = .default
) -> CGSize {
    let progressHeight = hasProgress ? metrics.progressBarHeight + metrics.textSpacing : 0
    let disclosureHeight = aiAgentDisclosureHeight(
        subagentCount: subagentCount,
        isDisclosed: isDisclosed,
        metrics: metrics
    )
    let contentHeight = metrics.glyphSize + progressHeight + disclosureHeight
    return CGSize(
        width: min(metrics.width, panelMetrics.maximumExpandedSize.width),
        height: min(
            contentHeight + metrics.contentInset * 2,
            panelMetrics.maximumExpandedSize.height
        )
    )
}

/// The expanded agent row: the agent logo and status, the detail line, and a
/// progress bar only when the agent reported a fraction.
///
/// Takes the activity rather than a transport, which is what keeps the view
/// layer ignorant of whether the state arrived over the URL scheme or the
/// loopback listener; activating the agent's app is the composition root's job.
public struct AIAgentActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let presentation: AIAgentPresentation
    private let subagents: [AIAgentSubagentPresentation]
    private let metrics: AIAgentViewMetrics
    private let panelMetrics: PanelMetrics
    private let isDisclosed: Bool
    private let onToggleDisclosure: () -> Void
    private let onPrimaryAction: () -> Void

    /// One session with nothing under it — the shape every agent but a
    /// delegating one ever takes.
    public init(
        activity: AIAgentActivity,
        instanceOrdinal: Int? = nil,
        metrics: AIAgentViewMetrics = .default,
        panelMetrics: PanelMetrics = .default,
        onPrimaryAction: @escaping () -> Void = {}
    ) {
        presentation = AIAgentPresentation(activity: activity, instanceOrdinal: instanceOrdinal)
        subagents = []
        self.metrics = metrics
        self.panelMetrics = panelMetrics
        isDisclosed = false
        onToggleDisclosure = {}
        self.onPrimaryAction = onPrimaryAction
    }

    /// One instance and the sub-agents it spawned.
    ///
    /// The card speaks for the instance's most urgent session, so a sub-agent
    /// waiting on the user turns the whole card yellow without the list having
    /// to be open.
    init(
        instance: AIAgentInstance,
        metrics: AIAgentViewMetrics = .default,
        panelMetrics: PanelMetrics = .default,
        isDisclosed: Bool = false,
        onToggleDisclosure: @escaping () -> Void = {},
        onPrimaryAction: @escaping () -> Void = {}
    ) {
        presentation = AIAgentPresentation(
            activity: instance.representative,
            instanceOrdinal: instance.ordinal
        )
        subagents = instance.subagents.enumerated().map { index, session in
            AIAgentSubagentPresentation(activity: session, fallbackOrdinal: index + 1)
        }
        self.metrics = metrics
        self.panelMetrics = panelMetrics
        self.isDisclosed = isDisclosed
        self.onToggleDisclosure = onToggleDisclosure
        self.onPrimaryAction = onPrimaryAction
    }

    /// Activates the originating app. Exposed so a test can drive the same path
    /// a tap takes without rendering into a window server.
    public func performPrimaryAction() {
        onPrimaryAction()
    }

    public var body: some View {
        let size = aiAgentExpandedSize(
            hasProgress: presentation.progress != nil,
            subagentCount: subagents.count,
            isDisclosed: isDisclosed,
            metrics: metrics,
            panelMetrics: panelMetrics
        )
        let surface = islandExpandedSurface(
            scheme: colorScheme.islandColorScheme,
            reduceTransparency: reduceTransparency
        )

        VStack(alignment: .leading, spacing: metrics.textSpacing) {
            HStack(spacing: metrics.columnSpacing) {
                glyph
                text
                Spacer(minLength: 0)
                disclosureControl
                if let action = presentation.primaryAction {
                    Button(action: performPrimaryAction) {
                        Image(systemName: action.symbolName)
                            .frame(width: metrics.glyphSize, height: metrics.glyphSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                }
            }

            if let progress = presentation.progress {
                progressBar(progress)
            }

            if isDisclosed, subagents.isEmpty == false {
                subagentList
            }
        }
        .padding(metrics.contentInset)
        .foregroundStyle(surface.foreground.style)
        .islandCard(
            width: size.width,
            height: size.height,
            alignment: .top,
            cornerRadius: metrics.cornerRadius,
            surface: surface
        )
        .environment(\.colorScheme, surface.preferredColorScheme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    /// The control that opens the sub-agent list, labelled with how many there
    /// are — the count the user asked the card for in the first place.
    @ViewBuilder
    private var disclosureControl: some View {
        if subagents.isEmpty == false {
            Button(action: onToggleDisclosure) {
                HStack(spacing: 3) {
                    Text(localized("\(subagents.count) agents"))
                    Image(systemName: isDisclosed ? "chevron.up" : "chevron.down")
                }
                .font(.system(size: metrics.subagentDetailSize, weight: .semibold))
                .padding(.horizontal, 5)
                .frame(height: metrics.disclosureControlHeight)
                .background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                localized(isDisclosed ? "Hide sub-agents" : "Show sub-agents")
            )
        }
    }

    private var subagentList: some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: metrics.subagentSeparatorHeight)
                .opacity(0.18)

            ForEach(Array(subagents.enumerated()), id: \.offset) { _, subagent in
                subagentRow(subagent)
            }
        }
    }

    private func subagentRow(_ subagent: AIAgentSubagentPresentation) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(aiAgentIndicatorColor(subagent.indicator))
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 0) {
                Text(subagent.title)
                    .font(.system(size: metrics.subagentNameSize, weight: .medium))
                    .lineLimit(1)

                if let detail = subagent.detail {
                    Text(detail)
                        .font(.system(size: metrics.subagentDetailSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: metrics.subagentRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subagent.accessibilityLabel)
    }

    private var glyph: some View {
        AIAgentIcon(agentID: presentation.agentID, size: metrics.glyphSize)
            .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: metrics.textSpacing) {
            Text(presentation.compactTitle)
                .font(.system(size: metrics.titleSize, weight: .medium))
                .lineLimit(1)

            if let detail = presentation.detail {
                Text(detail)
                    .font(.system(size: metrics.detailSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func progressBar(_ progress: Double) -> some View {
        ProgressView(value: progress)
            .progressViewStyle(.linear)
            .frame(height: metrics.progressBarHeight)
            .accessibilityHidden(true)
    }
}

struct AIAgentIcon: View {
    let agentID: IPCAgentID
    let size: CGFloat

    var body: some View {
        Group {
            if let image = AIAgentIconResolver.image(for: agentID) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: size * aiAgentIconArtworkScale(for: agentID),
                        height: size * aiAgentIconArtworkScale(for: agentID)
                    )
            } else {
                fallback
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    @ViewBuilder
    private var fallback: some View {
        switch agentID {
        case .claudeCode:
            ZStack {
                Color(red: 0.84, green: 0.42, blue: 0.27)
                Image(systemName: "asterisk")
                    .font(.system(size: size * 0.56, weight: .medium))
                    .foregroundStyle(.white)
            }
        case .codex:
            ZStack {
                Color(red: 0.29, green: 0.35, blue: 0.96)
                HStack(spacing: size * 0.04) {
                    Image(systemName: "chevron.right")
                    Rectangle().frame(width: size * 0.28, height: size * 0.08)
                }
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(.white)
            }
        case .opencode:
            OpenCodeLogo()
        }
    }
}

func aiAgentIconArtworkScale(for agentID: IPCAgentID) -> CGFloat {
    switch agentID {
    case .codex: 1.24
    case .claudeCode, .opencode: 1
    }
}

struct CompactAIAgentIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: CompactAIAgentSlotPresentation
    let iconSize: CGFloat

    private let metrics = CompactAIAgentMetrics.default

    /// The agent's logo, its status directly beneath it, and — when more than
    /// one session of that agent is running — how many, in the top-right corner.
    ///
    /// Every *state* reports in the same place. Needing input and failing used
    /// to hang a badge off the icon's side while working put a dot underneath,
    /// so the slot changed width with the state and the eye had two places to
    /// check. One position below the icon reads as a single status light.
    ///
    /// The count is deliberately the one thing that does *not* share that
    /// position: it answers a different question ("how many of this agent") from
    /// the status light ("what is it doing"), and stacking the two would make
    /// each state change look like a change in the number of sessions.
    var body: some View {
        let size = compactAIAgentIconSize(iconSize: iconSize, state: presentation.state)

        return ZStack(alignment: .top) {
            AIAgentIcon(agentID: presentation.agentID, size: iconSize)
                .overlay(alignment: .topTrailing) { sessionCountBadge }
            statusIndicator
                .offset(y: iconSize + 1)
        }
        .padding(.top, metrics.countBadgeOverhang)
        .frame(width: size.width, height: size.height, alignment: .top)
        .accessibilityHidden(true)
    }

    /// The count, white on the island's black so it reads as a quantity rather
    /// than as another status.
    ///
    /// Deliberately not one of the status tones: yellow, red, and green already
    /// mean "asking", "failed", and "done" in this pill, and colouring a count
    /// with any of them would claim a state the number does not describe.
    @ViewBuilder
    private var sessionCountBadge: some View {
        if presentation.showsSessionCount {
            Circle()
                .fill(.white)
                .overlay {
                    Text(compactAIAgentCountBadgeText(presentation.sessionCount))
                        .font(
                            .system(
                                size: metrics.countBadgeTextSize,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .overlay {
                    Circle().strokeBorder(.black, lineWidth: metrics.countBadgeRingWidth)
                }
                .frame(width: metrics.countBadgeDiameter, height: metrics.countBadgeDiameter)
                .offset(
                    x: metrics.countBadgeOverhang,
                    y: -metrics.countBadgeOverhang
                )
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch presentation.indicator {
        case .none:
            EmptyView()
        case .working:
            workingDot
        case .question, .error, .completed:
            if let symbolName = presentation.indicator.symbolName,
                let tone = presentation.indicator.badgeTone
            {
                badge(symbolName: symbolName, tone: tone)
            }
        }
    }

    @ViewBuilder
    private var workingDot: some View {
        if reduceMotion {
            dot(offset: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                dot(
                    offset: compactAIAgentWorkingDotOffset(
                        at: context.date.timeIntervalSinceReferenceDate,
                        reduceMotion: false
                    )
                )
            }
        }
    }

    private func dot(offset: CGFloat) -> some View {
        Circle()
            .fill(.white)
            .frame(width: metrics.dotDiameter, height: metrics.dotDiameter)
            .offset(x: offset)
    }

    private func badge(
        symbolName: String,
        tone: AIAgentCompactBadgeTone
    ) -> some View {
        Circle()
            .fill(badgeColor(tone))
            .frame(width: metrics.badgeDiameter, height: metrics.badgeDiameter)
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: metrics.badgeSymbolSize, weight: .black))
                    .foregroundStyle(badgeForegroundColor(tone))
            }
    }

    private func badgeColor(_ tone: AIAgentCompactBadgeTone) -> Color {
        switch tone {
        case .yellow: .yellow
        case .red: .red
        case .green: .green
        }
    }

    private func badgeForegroundColor(_ tone: AIAgentCompactBadgeTone) -> Color {
        tone == .yellow ? .black : .white
    }
}

private struct OpenCodeLogo: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let x = (geometry.size.width - size) / 2
            let y = (geometry.size.height - size) / 2

            ZStack(alignment: .topLeading) {
                Color.black
                Group {
                    Rectangle().frame(width: size * 0.8, height: size * 0.2)
                    Rectangle().frame(width: size * 0.8, height: size * 0.2)
                        .offset(y: size * 0.8)
                    Rectangle().frame(width: size * 0.2, height: size * 0.6)
                        .offset(y: size * 0.2)
                    Rectangle().frame(width: size * 0.2, height: size * 0.6)
                        .offset(x: size * 0.6, y: size * 0.2)
                }
                .foregroundStyle(Color(white: 0.94))
                .offset(x: size * 0.1)

                Rectangle()
                    .fill(Color(white: 0.29))
                    .frame(width: size * 0.4, height: size * 0.4)
                    .offset(x: size * 0.3, y: size * 0.4)
            }
            .frame(width: size, height: size)
            .offset(x: x, y: y)
        }
    }
}

@MainActor
private enum AIAgentIconResolver {
    private static var cachedImages: [IPCAgentID: NSImage] = [:]
    private static var resolvedAgentIDs: Set<IPCAgentID> = []

    static func image(for agentID: IPCAgentID) -> NSImage? {
        guard resolvedAgentIDs.insert(agentID).inserted else {
            return cachedImages[agentID]
        }
        let image = loadImage(for: agentID)
        cachedImages[agentID] = image
        return image
    }

    private static func loadImage(for agentID: IPCAgentID) -> NSImage? {
        switch agentID {
        case .claudeCode:
            return applicationIcon(bundleIdentifiers: ["com.anthropic.claudefordesktop"])
        case .codex:
            return codexIcon()
                ?? applicationIcon(bundleIdentifiers: ["com.openai.codex", "com.openai.chat"])
        case .opencode:
            return applicationIcon(bundleIdentifiers: ["dev.opencode.app"])
        }
    }

    private static func codexIcon() -> NSImage? {
        for bundleIdentifier in ["com.openai.codex", "com.openai.chat"] {
            guard
                let applicationURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: bundleIdentifier
                ), let bundle = Bundle(url: applicationURL),
                let iconURL = bundle.url(forResource: "icon-codex-dark-color", withExtension: "png"),
                let image = NSImage(contentsOf: iconURL)
            else {
                continue
            }
            return image
        }
        return nil
    }

    private static func applicationIcon(bundleIdentifiers: [String]) -> NSImage? {
        for bundleIdentifier in bundleIdentifiers {
            guard
                let applicationURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: bundleIdentifier
                )
            else {
                continue
            }
            return NSWorkspace.shared.icon(forFile: applicationURL.path)
        }
        return nil
    }
}

/// The dot colour for one sub-agent's state, the same language the compact
/// pill's status light speaks so a row and an icon never disagree.
func aiAgentIndicatorColor(_ indicator: AIAgentCompactIndicator) -> Color {
    switch indicator {
    case .none: .gray
    case .working: .white
    case .question: .yellow
    case .error: .red
    case .completed: .green
    }
}
