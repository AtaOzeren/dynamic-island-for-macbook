import AppKit
import CoreGraphics
import NotchFlowCore
import SwiftUI

public enum MusicSourceIdentity: Equatable, Sendable {
    case spotify
    case appleMusic
    case other

    public init(applicationName: String?) {
        let normalized =
            applicationName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if normalized.contains("spotify") {
            self = .spotify
        } else if normalized == "music"
            || normalized.contains("apple music")
            || normalized.contains("com.apple.music")
        {
            self = .appleMusic
        } else {
            self = .other
        }
    }
}

/// One transport button: the command it sends, the glyph it draws, and the label
/// VoiceOver reads.
///
/// A value rather than a `Button`, on the same rationale as `PrimaryAction` —
/// the set of controls a given playback state offers is then assertable without
/// rendering anything.
public struct MusicTransportControl: Identifiable, Equatable, Sendable {
    public let command: MusicTransportCommand
    public let symbolName: String
    public let accessibilityLabel: String

    public var id: String { accessibilityLabel }
}

/// Everything the music views draw, derived from `MusicActivity` alone.
///
/// This is the type that keeps the view layer backend-agnostic: it reads a
/// `MusicActivity` and nothing else, so no backend framework's vocabulary can
/// reach a view. Swapping the backend cannot change a pixel.
public struct MusicPresentation: Equatable, Sendable {
    /// Shown when a backend reports playback it cannot otherwise name — the
    /// island still says something true rather than drawing an empty pill.
    public static var untitledLabel: String { localized("Now Playing") }

    public let title: String
    public let subtitle: String?
    public let playbackState: MusicPlaybackState
    public let primaryAction: PrimaryAction?
    public let artworkData: Data?
    public let sourceIdentity: MusicSourceIdentity

    public init(activity: MusicActivity) {
        let nowPlaying = activity.nowPlaying

        title = Self.firstNonEmpty(
            nowPlaying.title,
            nowPlaying.sourceApplicationName,
            Self.untitledLabel
        )
        subtitle = nowPlaying.artist.isEmpty ? nil : nowPlaying.artist
        playbackState = nowPlaying.playbackState
        primaryAction = activity.primaryAction
        artworkData = nowPlaying.artworkData
        sourceIdentity = MusicSourceIdentity(
            applicationName: nowPlaying.sourceApplicationName
        )
    }

    /// Previous, play/pause, next — in reading order, with the middle control
    /// following the playback state.
    public var transportControls: [MusicTransportControl] {
        [
            MusicTransportControl(
                command: .previousTrack,
                symbolName: "backward.fill",
                accessibilityLabel: localized("Previous track")
            ),
            playPauseControl,
            MusicTransportControl(
                command: .nextTrack,
                symbolName: "forward.fill",
                accessibilityLabel: localized("Next track")
            ),
        ]
    }

    /// What VoiceOver reads for the whole activity: the track, prefixed with the
    /// state only when it is not the expected one.
    public var accessibilityLabel: String {
        let track = [title, subtitle].compactMap(\.self).joined(separator: " — ")
        switch playbackState {
        case .playing: return track
        case .paused: return localized("Paused: \(track)")
        }
    }

    private var playPauseControl: MusicTransportControl {
        switch playbackState {
        case .playing:
            MusicTransportControl(
                command: .playPause,
                symbolName: "pause.fill",
                accessibilityLabel: localized("Pause")
            )
        case .paused:
            MusicTransportControl(
                command: .playPause,
                symbolName: "play.fill",
                accessibilityLabel: localized("Play")
            )
        }
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String {
        candidates.compactMap(\.self).first { $0.isEmpty == false } ?? untitledLabel
    }
}

/// The music activity's compact slot: the shared music glyph, but announcing the
/// actual track rather than the generic "Music" the kind-based label produces.
public func musicCompactSlot(for activity: MusicActivity) -> CompactSlot {
    let presentation = MusicPresentation(activity: activity)
    return CompactSlot(
        activity: activity,
        accessibilityLabel: presentation.accessibilityLabel,
        musicPresentation: CompactMusicSlotPresentation(activity: activity)
    )
}

/// The expanded music view's visual budget, the music counterpart to
/// `ExpandedPanelMetrics` — one edit changes the music row's density.
public struct MusicViewMetrics: Equatable, Sendable {
    public static let `default` = MusicViewMetrics()

    public let artworkSize: CGFloat
    public let contentInset: CGFloat
    public let textSpacing: CGFloat
    public let columnSpacing: CGFloat
    public let titleSize: CGFloat
    public let subtitleSize: CGFloat
    public let transportSymbolSize: CGFloat
    public let transportButtonSize: CGFloat
    public let transportSpacing: CGFloat
    public let cornerRadius: CGFloat
    public let width: CGFloat

    public init(
        artworkSize: CGFloat = 40,
        contentInset: CGFloat = 10,
        textSpacing: CGFloat = 2,
        columnSpacing: CGFloat = 8,
        titleSize: CGFloat = IslandTypeScale.default.title,
        subtitleSize: CGFloat = IslandTypeScale.default.detail,
        transportSymbolSize: CGFloat = 11,
        transportButtonSize: CGFloat = 24,
        transportSpacing: CGFloat = 2,
        cornerRadius: CGFloat = 16,
        width: CGFloat = 276
    ) {
        self.artworkSize = artworkSize
        self.contentInset = contentInset
        self.textSpacing = textSpacing
        self.columnSpacing = columnSpacing
        self.titleSize = titleSize
        self.subtitleSize = subtitleSize
        self.transportSymbolSize = transportSymbolSize
        self.transportButtonSize = transportButtonSize
        self.transportSpacing = transportSpacing
        self.cornerRadius = cornerRadius
        self.width = width
    }
}

/// The expanded music view's drawn size, clamped to the window's allocated
/// maximum for the same reason `expandedPanelSize` clamps: the `NSPanel` frame
/// is allocated once and never resized, so anything past it is silently clipped.
public func musicExpandedSize(
    metrics: MusicViewMetrics = .default,
    panelMetrics: PanelMetrics = .default
) -> CGSize {
    let contentHeight = max(metrics.artworkSize, metrics.transportButtonSize)
    return CGSize(
        width: min(metrics.width, panelMetrics.maximumExpandedSize.width),
        height: min(
            contentHeight + metrics.contentInset * 2,
            panelMetrics.maximumExpandedSize.height
        )
    )
}

/// The expanded music row: artwork placeholder, track and artist, and transport.
///
/// Takes the activity rather than a provider, which is what keeps the view layer
/// backend-agnostic; sending the command is the composition root's job.
public struct MusicExpandedView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public let presentation: MusicPresentation
    private let metrics: MusicViewMetrics
    private let panelMetrics: PanelMetrics
    private let onTransport: (MusicTransportCommand) -> Void
    private let onPrimaryAction: () -> Void

    public init(
        activity: MusicActivity,
        metrics: MusicViewMetrics = .default,
        panelMetrics: PanelMetrics = .default,
        onTransport: @escaping (MusicTransportCommand) -> Void = { _ in },
        onPrimaryAction: @escaping () -> Void = {}
    ) {
        presentation = MusicPresentation(activity: activity)
        self.metrics = metrics
        self.panelMetrics = panelMetrics
        self.onTransport = onTransport
        self.onPrimaryAction = onPrimaryAction
    }

    /// Dispatches a control's command. Exposed so a test can drive the same path
    /// a tap takes without rendering into a window server.
    public func perform(_ control: MusicTransportControl) {
        onTransport(control.command)
    }

    public func performPrimaryAction() {
        onPrimaryAction()
    }

    public var body: some View {
        let size = musicExpandedSize(metrics: metrics, panelMetrics: panelMetrics)
        let surface = islandExpandedSurface(
            scheme: colorScheme.islandColorScheme,
            reduceTransparency: reduceTransparency
        )

        HStack(spacing: metrics.columnSpacing) {
            artwork
            trackText
            Spacer(minLength: 0)
            transport
        }
        .padding(metrics.contentInset)
        .foregroundStyle(surface.foreground.style)
        .islandCard(
            width: size.width,
            height: size.height,
            alignment: .center,
            cornerRadius: metrics.cornerRadius,
            surface: surface
        )
        .environment(\.colorScheme, surface.preferredColorScheme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private var artwork: some View {
        if let action = presentation.primaryAction {
            Button(action: performPrimaryAction) {
                artworkContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.title)
        } else {
            artworkContent
                .accessibilityHidden(true)
        }
    }

    private var artworkContent: some View {
        RoundedRectangle(cornerRadius: metrics.textSpacing * 2, style: .continuous)
            .fill(musicAccentColor(presentation.sourceIdentity).opacity(0.24))
            .frame(width: metrics.artworkSize, height: metrics.artworkSize)
            .overlay {
                if let artworkData = presentation.artworkData,
                    let artworkImage = NSImage(data: artworkData)
                {
                    Image(nsImage: artworkImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: compactSymbolName(.music))
                        .font(.system(size: metrics.titleSize, weight: .medium))
                        .foregroundStyle(musicAccentColor(presentation.sourceIdentity))
                }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: metrics.textSpacing * 2, style: .continuous)
            )
    }

    private var trackText: some View {
        VStack(alignment: .leading, spacing: metrics.textSpacing) {
            Text(presentation.title)
                .font(.system(size: metrics.titleSize, weight: .semibold))
                .lineLimit(1)

            if let subtitle = presentation.subtitle {
                Text(subtitle)
                    .font(.system(size: metrics.subtitleSize, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .layoutPriority(1)
        .accessibilityHidden(true)
    }

    private var transport: some View {
        HStack(spacing: metrics.transportSpacing) {
            ForEach(presentation.transportControls) { control in
                Button {
                    perform(control)
                } label: {
                    Image(systemName: control.symbolName)
                        .font(.system(size: metrics.transportSymbolSize, weight: .medium))
                        .frame(width: metrics.transportButtonSize, height: metrics.transportButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(control.accessibilityLabel)
            }

        }
    }
}

func musicAccentColor(_ sourceIdentity: MusicSourceIdentity) -> Color {
    switch sourceIdentity {
    case .spotify:
        Color(red: 29.0 / 255.0, green: 185.0 / 255.0, blue: 84.0 / 255.0)
    case .appleMusic:
        Color(red: 250.0 / 255.0, green: 36.0 / 255.0, blue: 60.0 / 255.0)
    case .other:
        .white
    }
}
