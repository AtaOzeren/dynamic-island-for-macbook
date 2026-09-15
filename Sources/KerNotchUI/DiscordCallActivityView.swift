import KerNotchCore
import SwiftUI

/// Everything the Discord call views draw, derived from `DiscordCallActivity`
/// alone.
public struct DiscordCallPresentation: Equatable, Sendable {
    public let title: String
    /// The server the channel belongs to, when the RPC connection named one.
    public let detail: String?
    public let isMuted: Bool
    public let leaveAction: PrimaryAction?

    public init(activity: DiscordCallActivity) {
        title = Self.title(for: activity.channel)
        detail = activity.channel?.serverName
        // Unknown reads as live: without the RPC connection KerNotch cannot tell,
        // and claiming a muted microphone that is not would be the worse lie.
        isMuted = activity.isMuted ?? false
        leaveAction = activity.primaryAction
    }

    public var microphoneSymbolName: String {
        isMuted ? "mic.slash.fill" : "mic.fill"
    }

    public var accessibilityLabel: String {
        let place =
            detail.map { localized("activity.accessibility.headlineAndDetail", default: "\(title), \($0)") } ?? title
        return isMuted ? localized("Muted: \(place)") : place
    }

    private static func title(for channel: DiscordVoiceChannel?) -> String {
        guard let channel else { return localized("In a Discord call") }
        return channel.name.isEmpty ? localized("Private call") : channel.name
    }
}

public func discordCallCompactSlot(for activity: DiscordCallActivity) -> CompactSlot {
    CompactSlot(discordCall: activity, presentation: DiscordCallPresentation(activity: activity))
}

/// The microphone as Discord holds it, with Discord's badge on its corner.
///
/// Red while live, like the microphone indicator it stands in for, and dimmed
/// with a slash while muted: a muted call is still a call, but not a microphone
/// anyone can hear. Three breaths announce the call, then the glyph holds still
/// so a long call keeps no render loop.
struct DiscordCallIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var symbolScale: CGFloat = 1

    private static let pulseCount = 3
    private static let pulseDuration = Duration.milliseconds(300)
    private static let badgeScale: CGFloat = 0.62

    let isMuted: Bool
    let size: CGFloat
    let animatesArrival: Bool

    var body: some View {
        Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            .scaleEffect(symbolScale)
            .overlay(alignment: .bottomTrailing) {
                DiscordBadge(diameter: size * Self.badgeScale)
                    .offset(x: size * 0.28, y: size * 0.18)
            }
            .task {
                guard animatesArrival, reduceMotion == false else { return }
                for _ in 0..<Self.pulseCount {
                    withAnimation(.easeOut(duration: 0.3)) {
                        symbolScale = 1.12
                    }
                    // Cancellation — the slot leaving the hierarchy mid-breath —
                    // is the only error Task.sleep throws, and the isCancelled
                    // guards convert it to a clean exit. Applies to both sleeps.
                    try? await Task.sleep(for: Self.pulseDuration)
                    guard Task.isCancelled == false else { return }

                    withAnimation(.easeIn(duration: 0.3)) {
                        symbolScale = 0.88
                    }
                    try? await Task.sleep(for: Self.pulseDuration)
                    guard Task.isCancelled == false else { return }
                }

                withAnimation(.easeOut(duration: 0.2)) {
                    symbolScale = 1
                }
            }
            .accessibilityHidden(true)
    }
}

/// Expanded Discord call row: the badged microphone, the channel and its server
/// on one line, and — when the RPC connection can do it — a button that leaves
/// the channel.
public struct DiscordCallActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public let presentation: DiscordCallPresentation
    private let metrics: ExpandedPanelMetrics
    private let onLeave: () -> Void

    public init(
        activity: DiscordCallActivity,
        metrics: ExpandedPanelMetrics = .default,
        onLeave: @escaping () -> Void = {}
    ) {
        presentation = DiscordCallPresentation(activity: activity)
        self.metrics = metrics
        self.onLeave = onLeave
    }

    /// Exposed so a test can drive the path a press takes without rendering.
    public func leave() {
        guard presentation.leaveAction != nil else { return }
        onLeave()
    }

    public var body: some View {
        let surface = islandExpandedSurface(
            scheme: colorScheme.islandColorScheme,
            reduceTransparency: reduceTransparency
        )

        HStack(spacing: metrics.columnSpacing) {
            DiscordCallIcon(isMuted: presentation.isMuted, size: metrics.symbolSize * 0.88, animatesArrival: false)
                .frame(width: metrics.symbolColumnWidth)

            Text(presentation.title)
                .font(.system(size: metrics.titleSize, weight: .medium))
                .lineLimit(1)
                .layoutPriority(1)

            if let detail = presentation.detail {
                Text(detail)
                    .font(.system(size: metrics.detailSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let action = presentation.leaveAction {
                Button(action: leave) {
                    Image(systemName: action.symbolName)
                        .font(.system(size: metrics.symbolSize - 4, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: metrics.symbolColumnWidth, height: metrics.symbolColumnWidth)
                        .background(Circle().fill(.red))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
