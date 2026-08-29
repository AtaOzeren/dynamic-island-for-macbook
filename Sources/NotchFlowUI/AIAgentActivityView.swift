import CoreGraphics
import NotchFlowCore
import SwiftUI

/// Everything the AI agent views draw, derived from `AIAgentActivity` alone.
///
/// The type is the privacy rule's last enforcement point: it exposes a glyph, a
/// pair of short strings, and an optional fraction, and it is built from an
/// activity that carries no prompt, no code, and no transcript to begin with.
/// `docs/07-ai-integration.md` forbids any of that reaching the screen, and a
/// view cannot render what this presentation has no field for.
public struct AIAgentPresentation: Equatable, Sendable {
    public let state: AIAgentState
    public let agentName: String
    /// The envelope's `detail` line, or `nil` when the agent sent an empty one —
    /// so the expanded view drops the line rather than drawing a blank row.
    public let detail: String?
    public let toolName: String?
    public let progress: Double?

    public init(activity: AIAgentActivity) {
        state = activity.state
        agentName = activity.agent.displayName
        detail = activity.detail.isEmpty ? nil : activity.detail
        toolName = activity.toolName
        progress = activity.progress
    }

    /// One glyph per state, and the three states that need the user's attention
    /// get shapes rather than sparkles: `docs/07-ai-integration.md` renders
    /// needs-input, completed, and error with their own marks so the pill says
    /// *which* of the seven states it is without being expanded.
    public var symbolName: String {
        switch state {
        case .idle: "sparkles"
        case .thinking: "brain"
        case .working: "gearshape.2.fill"
        case .usingTool: "wrench.and.screwdriver.fill"
        case .waitingForUser: "exclamationmark.bubble.fill"
        case .completed: "checkmark.circle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    /// The state in words, as the island says it.
    ///
    /// `usingTool` names the tool when the agent sent one — "Running Bash…"
    /// rather than the generic phrasing — which is the one place the tool name
    /// earns its space in the compact pill.
    public var statusText: String {
        switch state {
        case .idle: "Idle"
        case .thinking: "Thinking…"
        case .working: "Working…"
        case .usingTool: toolName.map { "Running \($0)…" } ?? "Running tool…"
        case .waitingForUser: "Needs your input"
        case .completed: "Task completed"
        case .error: "Task error"
        }
    }

    /// The compact pill's line, per the state table's compact column: the agent
    /// and its status, separated by the table's own middle dot.
    public var compactTitle: String {
        "\(agentName) · \(statusText)"
    }

    /// The expanded view's heading. The agent name alone, because the status and
    /// the detail get their own lines below it.
    public var title: String { agentName }

    /// Whether the state is one the user has to act on. Drives the accent the
    /// expanded view draws, so needs-input and error read as demands rather than
    /// as progress reports.
    public var needsAttention: Bool {
        state == .waitingForUser || state == .error
    }

    /// What VoiceOver reads for the whole activity: the compact line, with the
    /// detail appended when there is one to append.
    public var accessibilityLabel: String {
        guard let detail else { return compactTitle }
        return "\(compactTitle), \(detail)"
    }
}

/// The AI activity's compact slot: the state's own glyph rather than the shared
/// `.aiAgent` sparkles, so a finished task and a failed one are distinguishable
/// in the pill without expanding it.
public func aiAgentCompactSlot(for activity: AIAgentActivity) -> CompactSlot {
    let presentation = AIAgentPresentation(activity: activity)
    return CompactSlot(
        activity: activity,
        symbolName: presentation.symbolName,
        accessibilityLabel: presentation.accessibilityLabel
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
        glyphSize: CGFloat = 44,
        contentInset: CGFloat = 12,
        textSpacing: CGFloat = 2,
        columnSpacing: CGFloat = 12,
        titleSize: CGFloat = 13,
        detailSize: CGFloat = 11,
        progressBarHeight: CGFloat = 4,
        cornerRadius: CGFloat = 18,
        width: CGFloat = 320
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

/// The expanded agent row: the state glyph, the agent and its status, the detail
/// line, and a progress bar only when the agent reported a fraction.
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
            }

            if let progress = presentation.progress {
                progressBar(progress)
            }
        }
        .padding(metrics.contentInset)
        .frame(width: size.width, height: size.height, alignment: .leading)
        .foregroundStyle(surface.foreground.style)
        .background {
            surface.fill(in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var glyph: some View {
        RoundedRectangle(cornerRadius: metrics.textSpacing * 2, style: .continuous)
            .fill(presentation.needsAttention ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
            .frame(width: metrics.glyphSize, height: metrics.glyphSize)
            .overlay {
                Image(systemName: presentation.symbolName)
                    .font(.system(size: metrics.titleSize, weight: .medium))
            }
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
