import CoreGraphics
import NotchFlowCore
import SwiftUI

public struct CompactMusicSlotPresentation: Equatable, Sendable {
    public let isPlaying: Bool
    public let sourceIdentity: MusicSourceIdentity
    public let animationIdentity: String

    public init(activity: MusicActivity) {
        isPlaying = activity.nowPlaying.playbackState == .playing
        sourceIdentity = MusicSourceIdentity(
            applicationName: activity.nowPlaying.sourceApplicationName
        )
        animationIdentity = [
            activity.nowPlaying.title,
            activity.nowPlaying.artist,
            isPlaying ? "playing" : "paused",
        ].joined(separator: "|")
    }
}

/// One drawn element of the compact pill: either an activity's icon or the
/// single overflow indicator that stands in for everything past the capacity in
/// `docs/05-activity-model.md`.
public struct CompactSlot: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbolName: String
    public let label: String?
    public let overflowCount: Int?
    public let accessibilityLabel: String

    /// Draws moving equaliser bars in place of the glyph. Carried as a flag
    /// rather than as a second symbol name because the bars are not a symbol:
    /// they animate, and only while something is actually playing.
    public let isPlayingMusic: Bool
    public let musicSourceIdentity: MusicSourceIdentity?
    public let animationIdentity: String?
    public let recordingSource: RecordingSource?
    let aiAgentPresentation: CompactAIAgentSlotPresentation?
    public var aiAgentID: IPCAgentID? { aiAgentPresentation?.agentID }

    fileprivate init(activity: any Activity) {
        id = activity.identity.rawValue
        symbolName = compactSymbolName(activity.kind)
        label = nil
        overflowCount = nil
        accessibilityLabel = compactAccessibilityLabel(activity.kind)
        isPlayingMusic = false
        musicSourceIdentity = nil
        animationIdentity = nil
        recordingSource = nil
        aiAgentPresentation = nil
    }

    /// For activities whose per-instance detail outgrows what the kind alone can
    /// say — music announces "Windowlicker — Aphex Twin" rather than "Music", and
    /// charging draws a full battery rather than the shared bolt once the charge
    /// is done. Omitting `symbolName` keeps the kind's glyph.
    init(
        activity: any Activity,
        id: ActivityIdentity? = nil,
        symbolName: String? = nil,
        accessibilityLabel: String,
        musicPresentation: CompactMusicSlotPresentation? = nil,
        aiAgentPresentation: CompactAIAgentSlotPresentation? = nil
    ) {
        self.id = (id ?? activity.identity).rawValue
        self.symbolName = symbolName ?? compactSymbolName(activity.kind)
        label = nil
        overflowCount = nil
        self.accessibilityLabel = accessibilityLabel
        isPlayingMusic = musicPresentation?.isPlaying ?? false
        musicSourceIdentity = musicPresentation?.sourceIdentity
        animationIdentity = musicPresentation?.animationIdentity
        recordingSource = nil
        self.aiAgentPresentation = aiAgentPresentation
    }

    init(
        recording activity: RecordingActivity,
        presentation: RecordingPresentation
    ) {
        id = activity.identity.rawValue
        symbolName = presentation.symbolName
        label = nil
        overflowCount = nil
        accessibilityLabel = presentation.accessibilityLabel
        isPlayingMusic = false
        musicSourceIdentity = nil
        animationIdentity = nil
        recordingSource = activity.source
        aiAgentPresentation = nil
    }

    fileprivate init(overflowCount: Int) {
        id = Self.overflowIdentifier
        symbolName = "ellipsis"
        label = "+\(overflowCount)"
        self.overflowCount = overflowCount
        accessibilityLabel = localized("\(overflowCount) more activities")
        isPlayingMusic = false
        musicSourceIdentity = nil
        animationIdentity = nil
        recordingSource = nil
        aiAgentPresentation = nil
    }

    private static let overflowIdentifier = "notchflow.compact.overflow"
}

/// How the pill's slots divide around the notch. The notch itself is opaque
/// hardware, so the pill can only draw to either side of it, and reading order
/// fills the leading side first — the highest-priority activity is the one the
/// eye reaches first.
public struct CompactSlotLayout: Equatable, Sendable {
    public let leading: [CompactSlot]
    public let trailing: [CompactSlot]
}

/// One activity's slot, routed to the kind that knows how to describe itself.
///
/// Music and charging both announce per-instance detail the shared kind label
/// cannot carry — the actual track, and a full battery once charging completes.
private func compactSlot(for activity: any Activity) -> CompactSlot {
    switch activity {
    case let music as MusicActivity: musicCompactSlot(for: music)
    case let recording as RecordingActivity: recordingCompactSlot(for: recording)
    case let charging as ChargingActivity: chargingCompactSlot(for: charging)
    case let aiAgent as AIAgentActivity: aiAgentCompactSlot(for: aiAgent)
    default: CompactSlot(activity: activity)
    }
}

/// The ordered slots for `presentation`, which has already applied the priority
/// ordering and the capacity limit in `ActivityManager`.
public func compactSlots(for presentation: CompactActivityPresentation) -> [CompactSlot] {
    let slots = presentation.activities.map(compactSlot(for:))
    guard presentation.overflowCount > 0 else { return slots }
    return slots + [CompactSlot(overflowCount: presentation.overflowCount)]
}

/// Splits the slots around the notch, filling the leading side first so the
/// overflow indicator — always last — lands on the trailing side.
public func compactSlotLayout(for presentation: CompactActivityPresentation) -> CompactSlotLayout {
    compactSlotLayout(for: compactSlots(for: presentation))
}

private func compactSlotLayout(for slots: [CompactSlot]) -> CompactSlotLayout {
    let leadingCount = (slots.count + 1) / 2
    return CompactSlotLayout(
        leading: Array(slots.prefix(leadingCount)),
        trailing: Array(slots.dropFirst(leadingCount))
    )
}

struct CompactMusicIconVisibility: Equatable, Sendable {
    static let visibleDuration: Duration = .seconds(5)

    private var announcedSlotIDs: Set<String> = []
    private var hiddenSlotIDs: Set<String> = []

    init() {}

    mutating func synchronize(activeSlots: [CompactSlot]) -> [String] {
        let activeMusicSlotIDs = Set(
            activeSlots.lazy
                .filter { $0.musicSourceIdentity != nil }
                .map(\.id)
        )
        announcedSlotIDs.formIntersection(activeMusicSlotIDs)
        hiddenSlotIDs.formIntersection(activeMusicSlotIDs)

        let newSlotIDs = activeMusicSlotIDs.subtracting(announcedSlotIDs)
        announcedSlotIDs.formUnion(newSlotIDs)
        return newSlotIDs.sorted()
    }

    mutating func hide(slotID: String) {
        guard announcedSlotIDs.contains(slotID) else { return }
        hiddenSlotIDs.insert(slotID)
    }

    func visibleSlots(from slots: [CompactSlot]) -> [CompactSlot] {
        slots.filter { !hiddenSlotIDs.contains($0.id) }
    }
}

public func compactSymbolName(_ kind: ActivityKind) -> String {
    switch kind {
    case .music: "music.note"
    case .timer: "timer"
    case .recording: "record.circle"
    case .charging: "bolt.fill"
    case .aiAgent: "sparkles"
    case .fileTransfer: "arrow.down.circle"
    }
}

public func compactAccessibilityLabel(_ kind: ActivityKind) -> String {
    switch kind {
    case .music: localized("Music")
    case .timer: localized("Timer")
    case .recording: localized("Recording")
    case .charging: localized("Charging")
    case .aiAgent: localized("AI agent")
    case .fileTransfer: localized("Transfer")
    }
}

/// The compact pill: activity icons hugging both edges of the notch, with the
/// notch's own width held open between them.
public struct CompactActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.drawsOwnIslandSurface) private var drawsOwnSurface

    private let presentation: CompactActivityPresentation
    private let notchSize: CGSize
    private let metrics: CompactPillMetrics
    private let motion: IslandMotion

    @State private var musicIconVisibility = CompactMusicIconVisibility()

    public init(
        presentation: CompactActivityPresentation,
        notchSize: CGSize,
        metrics: CompactPillMetrics = .default,
        motion: IslandMotion = .default
    ) {
        self.presentation = presentation
        self.notchSize = notchSize
        self.metrics = metrics
        self.motion = motion
    }

    public var body: some View {
        let slots = compactSlots(for: presentation)
        let visibleSlots = musicIconVisibility.visibleSlots(from: slots)
        let layout = compactSlotLayout(for: visibleSlots)
        let size = compactPillSize(
            slotCount: layout.leading.count + layout.trailing.count,
            notchSize: notchSize,
            metrics: metrics
        )

        let surface = islandCompactSurface(scheme: colorScheme.islandColorScheme)

        HStack(spacing: metrics.slotSpacing) {
            slotRow(layout.leading)
            Color.clear.frame(width: notchSize.width)
            slotRow(layout.trailing)
        }
        .padding(.horizontal, metrics.edgeInset)
        .frame(width: size.width, height: size.height)
        .foregroundStyle(surface.foreground.style)
        .background {
            if drawsOwnSurface {
                surface.fill(
                    in: RoundedRectangle(
                        cornerRadius: compactPillCornerRadius(for: size),
                        style: .continuous
                    )
                )
            }
        }
        .environment(\.colorScheme, surface.preferredColorScheme)
        .animation(slotAnimation, value: visibleSlots)
        .task(id: musicSlotIDs(in: slots)) {
            await scheduleMusicIconDismissals(for: slots)
        }
    }

    private func slotRow(_ slots: [CompactSlot]) -> some View {
        HStack(spacing: metrics.slotSpacing) {
            ForEach(slots) { slot in
                slotView(slot)
                    .transition(slotTransition)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(slotAnimation, value: slots)
    }

    /// Slots grow out of, and shrink back into, the notch's edge rather than
    /// appearing at full size, so an activity starting reads as the island
    /// extending rather than as a glyph blinking into place.
    private var slotTransition: AnyTransition {
        guard reduceMotion == false else { return .opacity }
        return .scale(scale: 0.6).combined(with: .opacity)
    }

    private var slotAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: motion.reducedMotionCrossFadeDuration)
            : .spring(response: motion.springResponse, dampingFraction: motion.springDamping)
    }

    private func slotView(_ slot: CompactSlot) -> some View {
        Group {
            if let label = slot.label {
                Text(label)
                    .font(.system(size: metrics.symbolSize, weight: .semibold, design: .rounded))
            } else if slot.recordingSource == .screen {
                AnimatedScreenRecordingIcon(size: metrics.symbolSize * 0.84)
            } else if slot.recordingSource == .audio {
                AnimatedMicrophoneRecordingIcon(size: metrics.symbolSize * 0.84)
            } else if let aiAgentPresentation = slot.aiAgentPresentation {
                CompactAIAgentIcon(
                    presentation: aiAgentPresentation,
                    iconSize: metrics.symbolSize
                )
            } else if let sourceIdentity = slot.musicSourceIdentity {
                if slot.isPlayingMusic {
                    MusicEqualiserSlotView(
                        metrics: metrics,
                        symbolName: slot.symbolName,
                        sourceIdentity: sourceIdentity
                    )
                    .id(slot.animationIdentity)
                } else {
                    Image(systemName: slot.symbolName)
                        .font(.system(size: metrics.symbolSize, weight: .medium))
                        .foregroundStyle(musicAccentColor(sourceIdentity))
                }
            } else {
                Image(systemName: slot.symbolName)
                    .font(.system(size: metrics.symbolSize, weight: .medium))
            }
        }
        .frame(width: metrics.slotWidth)
        .accessibilityLabel(slot.accessibilityLabel)
    }

    private func musicSlotIDs(in slots: [CompactSlot]) -> [String] {
        slots.filter { $0.musicSourceIdentity != nil }.map(\.id).sorted()
    }

    private func scheduleMusicIconDismissals(for slots: [CompactSlot]) async {
        let newSlotIDs = musicIconVisibility.synchronize(activeSlots: slots)
        for slotID in newSlotIDs {
            do {
                try await Task.sleep(for: CompactMusicIconVisibility.visibleDuration)
            } catch {
                return
            }
            musicIconVisibility.hide(slotID: slotID)
        }
    }
}

/// The moving equaliser drawn in the music slot while a track is playing.
///
/// Settles into the static glyph after `animationDuration`, so the island does
/// not keep an animation running for the entire length of an album — the idle
/// budget in `docs/02-performance-contract.md` is the whole reason the pill is
/// cheap to leave on screen. The motion is announcement, not status.
struct MusicEqualiserSlotView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    @State private var hasSettled = false

    /// How long the bars move before settling to the glyph.
    static let animationDuration: Duration = .seconds(3)

    private static let barScales: [CGFloat] = [0.45, 1.0, 0.7]
    private static let barPhaseOffsets: [Double] = [0, 0.18, 0.36]

    let metrics: CompactPillMetrics
    let symbolName: String
    let sourceIdentity: MusicSourceIdentity

    var body: some View {
        content
            .foregroundStyle(musicAccentColor(sourceIdentity))
            .task {
                guard reduceMotion == false else { return }
                isAnimating = true
                try? await Task.sleep(for: Self.animationDuration)
                isAnimating = false
                hasSettled = true
            }
    }

    @ViewBuilder
    private var content: some View {
        if reduceMotion || hasSettled {
            Image(systemName: symbolName)
                .font(.system(size: metrics.symbolSize, weight: .medium))
                .transition(.opacity)
        } else {
            bars
        }
    }

    private var bars: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(Self.barScales.enumerated()), id: \.offset) { index, restingScale in
                Capsule()
                    .frame(width: barWidth, height: metrics.symbolSize * restingScale)
                    .scaleEffect(y: isAnimating ? 1 : 0.35, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.42)
                            .repeatForever(autoreverses: true)
                            .delay(Self.barPhaseOffsets[index]),
                        value: isAnimating
                    )
            }
        }
        .frame(height: metrics.symbolSize)
    }

    private var barWidth: CGFloat { metrics.symbolSize / 5 }
    private var barSpacing: CGFloat { metrics.symbolSize / 6 }
}
