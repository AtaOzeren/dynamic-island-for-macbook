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

    public init(activity: AIAgentActivity) {
        state = activity.state
        agentID = activity.agent
        agentName = activity.agent.displayName
        detail = activity.detail.isEmpty ? nil : activity.detail
        toolName = activity.toolName
        progress = activity.progress
        primaryAction = activity.primaryAction
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

struct AIAgentActivityGroup: Identifiable, Equatable, Sendable {
    let agentID: IPCAgentID
    let sessions: [AIAgentActivity]

    init(session: AIAgentActivity) {
        agentID = session.agent
        sessions = [session]
    }

    private init(agentID: IPCAgentID, sessions: [AIAgentActivity]) {
        self.agentID = agentID
        self.sessions = sessions
    }

    var id: String { "notchflow.ai.expanded.\(agentID.rawValue)" }
    var showsDisclosure: Bool { sessions.count > 1 }

    var representative: AIAgentActivity {
        sessions.dropFirst().reduce(sessions[0]) { current, candidate in
            candidate.compactRepresentationPriority > current.compactRepresentationPriority
                ? candidate
                : current
        }
    }

    func appending(_ session: AIAgentActivity) -> Self {
        precondition(session.agent == agentID)
        return Self(agentID: agentID, sessions: sessions + [session])
    }
}

struct AIAgentGroupViewMetrics: Equatable, Sendable {
    static let `default` = AIAgentGroupViewMetrics()

    let detailRowHeight: CGFloat = 26
    let separatorHeight: CGFloat = 1
    let titleSize: CGFloat = 11
    let detailSize: CGFloat = 9
    let countControlHeight: CGFloat = 18

    private init() {}
}

func aiAgentGroupDisclosureHeight(sessionCount: Int, isDisclosed: Bool) -> CGFloat {
    guard isDisclosed, sessionCount > 1 else { return 0 }
    let metrics = AIAgentGroupViewMetrics.default
    return metrics.separatorHeight + CGFloat(sessionCount) * metrics.detailRowHeight
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
    let indicator: AIAgentCompactIndicator

    init(activity: AIAgentActivity) {
        agentID = activity.agent
        indicator = AIAgentCompactIndicator(state: activity.state)
    }
}

struct CompactAIAgentMetrics: Equatable, Sendable {
    static let `default` = CompactAIAgentMetrics()

    let dotDiameter: CGFloat = 3
    let travelDistance: CGFloat = 8
    let oneWayDuration: TimeInterval = 0.65
    let badgeDiameter: CGFloat = 7
    let badgeSymbolSize: CGFloat = 5

    private init() {}
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
public func aiAgentCompactSlot(for activity: AIAgentActivity) -> CompactSlot {
    let presentation = AIAgentPresentation(activity: activity)
    return CompactSlot(
        activity: activity,
        id: activity.compactGroupIdentity,
        accessibilityLabel: presentation.accessibilityLabel,
        aiAgentPresentation: CompactAIAgentSlotPresentation(activity: activity)
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

    public init(
        glyphSize: CGFloat = 36,
        contentInset: CGFloat = 10,
        textSpacing: CGFloat = 2,
        columnSpacing: CGFloat = 8,
        titleSize: CGFloat = 12,
        detailSize: CGFloat = 10,
        progressBarHeight: CGFloat = 3,
        cornerRadius: CGFloat = 16,
        width: CGFloat = 276
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
    }
}

/// The expanded AI view's drawn size, clamped to the window's allocated maximum
/// for the same reason `musicExpandedSize` clamps: the `NSPanel` frame is
/// allocated once and never resized, so anything past it is silently clipped.
public func aiAgentExpandedSize(
    hasProgress: Bool,
    metrics: AIAgentViewMetrics = .default,
    panelMetrics: PanelMetrics = .default
) -> CGSize {
    let progressHeight = hasProgress ? metrics.progressBarHeight + metrics.textSpacing : 0
    let contentHeight = metrics.glyphSize + progressHeight
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
    private let metrics: AIAgentViewMetrics
    private let panelMetrics: PanelMetrics
    private let onPrimaryAction: () -> Void

    public init(
        activity: AIAgentActivity,
        metrics: AIAgentViewMetrics = .default,
        panelMetrics: PanelMetrics = .default,
        onPrimaryAction: @escaping () -> Void = {}
    ) {
        presentation = AIAgentPresentation(activity: activity)
        self.metrics = metrics
        self.panelMetrics = panelMetrics
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
        }
        .padding(metrics.contentInset)
        .foregroundStyle(surface.foreground.style)
        .islandCard(
            width: size.width,
            height: size.height,
            cornerRadius: metrics.cornerRadius,
            surface: surface
        )
        .environment(\.colorScheme, surface.preferredColorScheme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
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

struct AIAgentActivityGroupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let group: AIAgentActivityGroup
    let metrics: ExpandedPanelMetrics
    let isDisclosed: Bool
    let onToggleDisclosure: () -> Void
    let onPrimaryAction: () -> Void

    private let groupMetrics = AIAgentGroupViewMetrics.default

    var body: some View {
        let surface = islandExpandedSurface(
            scheme: colorScheme.islandColorScheme,
            reduceTransparency: reduceTransparency
        )

        VStack(spacing: 0) {
            header
            if group.showsDisclosure, isDisclosed {
                Divider()
                    .frame(height: groupMetrics.separatorHeight)
                    .opacity(0.18)
                ForEach(Array(group.sessions.enumerated()), id: \.element.sessionID) { index, session in
                    sessionRow(index: index, session: session)
                }
            }
        }
        .foregroundStyle(surface.foreground.style)
        .islandCard(
            width: metrics.width,
            height: metrics.rowHeight
                + aiAgentGroupDisclosureHeight(
                    sessionCount: group.sessions.count,
                    isDisclosed: isDisclosed
                ),
            alignment: .top,
            cornerRadius: metrics.cornerRadius,
            surface: surface
        )
        .environment(\.colorScheme, surface.preferredColorScheme)
    }

    private var header: some View {
        let presentation = AIAgentPresentation(activity: group.representative)

        return HStack(spacing: metrics.columnSpacing) {
            AIAgentIcon(agentID: group.agentID, size: metrics.symbolSize)
                .frame(width: metrics.symbolColumnWidth)

            Text(presentation.compactTitle)
                .font(.system(size: groupMetrics.titleSize, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            if group.showsDisclosure {
                Button(action: onToggleDisclosure) {
                    HStack(spacing: 3) {
                        Text("\(group.sessions.count)")
                        Image(systemName: isDisclosed ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: groupMetrics.detailSize, weight: .semibold))
                    .padding(.horizontal, 5)
                    .frame(height: groupMetrics.countControlHeight)
                    .background(.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    localized(isDisclosed ? "Hide agent sessions" : "Show agent sessions")
                )
            }

            if let action = presentation.primaryAction {
                Button(action: onPrimaryAction) {
                    Image(systemName: action.symbolName)
                        .font(.system(size: metrics.symbolSize - 2, weight: .semibold))
                        .frame(width: metrics.symbolColumnWidth, height: metrics.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }
        }
        .padding(.horizontal, metrics.contentInset)
        .frame(height: metrics.rowHeight)
    }

    private func sessionRow(index: Int, session: AIAgentActivity) -> some View {
        let presentation = AIAgentPresentation(activity: session)
        let indicator = AIAgentCompactIndicator(state: session.state)

        return HStack(spacing: 6) {
            Circle()
                .fill(statusColor(indicator))
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(index + 1) · \(presentation.statusText)")
                    .font(.system(size: groupMetrics.detailSize, weight: .medium))
                    .lineLimit(1)

                if let detail = presentation.detail {
                    Text(detail)
                        .font(.system(size: groupMetrics.detailSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.contentInset)
        .frame(height: groupMetrics.detailRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func statusColor(_ indicator: AIAgentCompactIndicator) -> Color {
        switch indicator {
        case .none: .gray
        case .working: .white
        case .question: .yellow
        case .error: .red
        case .completed: .green
        }
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

    var body: some View {
        HStack(spacing: 1) {
            iconAndWorkingIndicator
            if let symbolName = presentation.indicator.symbolName,
                let badgeTone = presentation.indicator.badgeTone
            {
                badge(symbolName: symbolName, tone: badgeTone)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var iconAndWorkingIndicator: some View {
        if presentation.indicator == .working {
            ZStack(alignment: .top) {
                AIAgentIcon(agentID: presentation.agentID, size: iconSize)
                workingDot
                    .offset(y: iconSize + 1)
            }
            .frame(
                width: max(iconSize, metrics.travelDistance + metrics.dotDiameter),
                height: iconSize + metrics.dotDiameter + 1,
                alignment: .top
            )
        } else {
            AIAgentIcon(agentID: presentation.agentID, size: iconSize)
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
