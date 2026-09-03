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

/// The pill's drawn size for `layout`, allocating each flank the width of the
/// busier one so an uneven split — every arrangement with an agent in it — still
/// draws both sides inside the capsule.
public func compactPillSize(
    for layout: CompactSlotLayout,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    compactPillSize(
        leadingSlotCount: layout.leading.count,
        trailingSlotCount: layout.trailing.count,
        notchSize: notchSize,
        metrics: metrics
    )
}

/// The pill's drawn size for `presentation`, routed through the same layout the
/// view draws so hit testing and rendering cannot disagree about the width.
public func compactPillSize(
    for presentation: CompactActivityPresentation,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    compactPillSize(
        for: compactSlotLayout(for: presentation),
        notchSize: notchSize,
        metrics: metrics
    )
}

/// The pill's full geometry — size and notch position — for `layout`.
public func compactPillGeometry(
    for layout: CompactSlotLayout,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CompactPillGeometry {
    compactPillGeometry(
        leadingSlotCount: layout.leading.count,
        trailingSlotCount: layout.trailing.count,
        notchSize: notchSize,
        metrics: metrics
    )
}

/// The pill's full geometry for `presentation`.
public func compactPillGeometry(
    for presentation: CompactActivityPresentation,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CompactPillGeometry {
    compactPillGeometry(
        for: compactSlotLayout(for: presentation),
        notchSize: notchSize,
        metrics: metrics
    )
}

/// The symmetric width for `layout`, for the elements that must stay centred on
/// the notch however the slots divide.
public func balancedCompactPillSize(
    for layout: CompactSlotLayout,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    balancedCompactPillSize(
        leadingSlotCount: layout.leading.count,
        trailingSlotCount: layout.trailing.count,
        notchSize: notchSize,
        metrics: metrics
    )
}

/// The symmetric width for `presentation`, for the elements that must stay
/// centred on the notch however the slots divide.
public func balancedCompactPillSize(
    for presentation: CompactActivityPresentation,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    let layout = compactSlotLayout(for: presentation)
    return balancedCompactPillSize(
        leadingSlotCount: layout.leading.count,
        trailingSlotCount: layout.trailing.count,
        notchSize: notchSize,
        metrics: metrics
    )
}

/// One activity's slot, routed to the kind that knows how to describe itself.
///
/// Music and charging both announce per-instance detail the shared kind label
/// cannot carry — the actual track, and a full battery once charging completes.
///
/// `groupSize` is how many active activities the slot stands for. Only the AI
/// agent slot has anything to say about it: every other kind draws one icon per
/// activity, so its group is always itself.
private func compactSlot(for activity: any Activity, groupSize: Int) -> CompactSlot {
    switch activity {
    case let music as MusicActivity: musicCompactSlot(for: music)
    case let recording as RecordingActivity: recordingCompactSlot(for: recording)
    case let charging as ChargingActivity: chargingCompactSlot(for: charging)
    case let aiAgent as AIAgentActivity:
        aiAgentCompactSlot(for: aiAgent, sessionCount: groupSize)
    default: CompactSlot(activity: activity)
    }
}

/// The ordered slots for `presentation`, which has already applied the priority
/// ordering and the capacity limit in `ActivityManager`.
public func compactSlots(for presentation: CompactActivityPresentation) -> [CompactSlot] {
    var slots = presentation.activities.map { activity in
        compactSlot(
            for: activity,
            groupSize: presentation.groupSizes[activity.compactGroupIdentity] ?? 1
        )
    }
    guard presentation.overflowCount > 0 else { return slots }
    let insertionIndex = slots.firstIndex { $0.aiAgentID != nil } ?? slots.endIndex
    slots.insert(CompactSlot(overflowCount: presentation.overflowCount), at: insertionIndex)
    return slots
}

/// Splits the slots around the notch, filling the leading side first so the
/// overflow indicator — always last — lands on the trailing side.
public func compactSlotLayout(for presentation: CompactActivityPresentation) -> CompactSlotLayout {
    compactSlotLayout(for: compactSlots(for: presentation))
}

private func compactSlotLayout(for slots: [CompactSlot]) -> CompactSlotLayout {
    let agentSlots = slots.filter { $0.aiAgentID != nil }
    if agentSlots.isEmpty == false {
        return CompactSlotLayout(
            leading: slots.filter { $0.aiAgentID == nil },
            trailing: agentSlots
        )
    }

    let leadingCount = (slots.count + 1) / 2
    return CompactSlotLayout(
        leading: Array(slots.prefix(leadingCount)),
        trailing: Array(slots.dropFirst(leadingCount))
    )
}

/// Tracks which music slots have already started their visibility timer.
///
/// The *hidden* set deliberately does not live here. It decides how wide the
/// pill is drawn, and the pill's black surface and its hover target are sized
/// by an ancestor of the view that owns this — while the set was private view
/// state, hiding the icon shrank the icons and left the bar and the hover
/// target at their old width. Only this bookkeeping, which nothing outside the
/// view needs, stayed behind.
struct CompactMusicIconVisibility: Equatable, Sendable {
    static let visibleDuration: Duration = .seconds(5)

    private var announcedSlotIDs: Set<String> = []

    init() {}

    /// Prunes slots that are gone and returns the ones whose timer must start.
    mutating func synchronize(
        activeSlots: [CompactSlot],
        hiddenSlotIDs: inout Set<String>
    ) -> [String] {
        let activeMusicSlotIDs = compactMusicSlotIDs(in: activeSlots)
        announcedSlotIDs.formIntersection(activeMusicSlotIDs)
        hiddenSlotIDs.formIntersection(activeMusicSlotIDs)

        let newSlotIDs = activeMusicSlotIDs.subtracting(announcedSlotIDs)
        announcedSlotIDs.formUnion(newSlotIDs)
        return newSlotIDs.sorted()
    }

    func hasAnnounced(_ slotID: String) -> Bool {
        announcedSlotIDs.contains(slotID)
    }
}

/// The music slots in `slots`, by identifier.
func compactMusicSlotIDs(in slots: [CompactSlot]) -> Set<String> {
    Set(slots.lazy.filter { $0.musicSourceIdentity != nil }.map(\.id))
}

/// The presentation with finished announcements taken out of the pill, and the
/// slots they were holding given back.
///
/// Hiding the slot is not enough on two counts.
///
/// The manager picks which agent groups fit the pill by urgency, and a failure
/// outranks work in flight — so a blocked agent wins a slot, and hiding it
/// afterwards leaves that slot empty while a third agent that is genuinely
/// working is never drawn at all. And a group that keeps its slot because
/// *some* of it is live still has its muted failure speaking for it, which
/// holds an agent's icon red for hours while another instance of it runs
/// happily.
///
/// Both are the same mistake — deciding who speaks before knowing who has
/// anything left to say — so the agent side of the pill is re-picked here from
/// the members that do. The rule mirrors the manager's, and the budget is
/// whatever the manager already allowed, so nothing about the ordinary case
/// changes: with no announcement pending this returns the presentation
/// untouched.
public func compactPresentation(
    _ presentation: CompactActivityPresentation,
    reconciledWith activities: [any Activity],
    announcementStarts: [ActivityIdentity: Date],
    registrationTimes: [ActivityIdentity: Date],
    now: Date
) -> CompactActivityPresentation {
    guard announcementStarts.isEmpty == false else { return presentation }

    let standard = presentation.activities.filter { $0.compactRegion != .agentTrailing }
    let budget = presentation.activities.count - standard.count
    guard budget > 0 else { return presentation }

    var speakers: [ActivityIdentity: any Activity] = [:]
    var latest: [ActivityIdentity: Date] = [:]
    for activity in activities where activity.compactRegion == .agentTrailing {
        let group = activity.compactGroupIdentity
        // A group's age is its own, whether or not its oldest member still has
        // something to say — otherwise muting a session would reorder the pill.
        let registered = registrationTimes[activity.identity] ?? .distantPast
        latest[group] = max(latest[group] ?? .distantPast, registered)

        guard hasFinishedAnnouncing(activity, announcementStarts, now) == false else { continue }
        if let speaker = speakers[group],
            speaker.compactRepresentationPriority >= activity.compactRepresentationPriority
        {
            continue
        }
        speakers[group] = activity
    }

    let agents =
        speakers
        .sorted { left, right in
            let leftKey = (left.value.compactRepresentationPriority, latest[left.key] ?? .distantPast)
            let rightKey = (
                right.value.compactRepresentationPriority, latest[right.key] ?? .distantPast
            )
            return leftKey > rightKey
        }
        .prefix(budget)
        .sorted { (latest[$0.key] ?? .distantPast) < (latest[$1.key] ?? .distantPast) }
        .map(\.value)

    return CompactActivityPresentation(
        activities: standard + agents,
        overflowCount: presentation.overflowCount,
        groupSizes: presentation.groupSizes
    )
}

/// Whether the pill has already said what this activity had to say.
private func hasFinishedAnnouncing(
    _ activity: any Activity,
    _ announcementStarts: [ActivityIdentity: Date],
    _ now: Date
) -> Bool {
    guard let window = activity.compactAnnouncementWindow,
        let start = announcementStarts[activity.identity]
    else {
        return false
    }
    return now.timeIntervalSince(start) >= window
}

/// When the next announcement window runs out, or `nil` when none is pending.
///
/// The compact presentation is computed on demand, so nothing re-reads it until
/// something changes — and an agent that failed once and went quiet sends
/// nothing more. Without a deadline to wake on, its announcement would never
/// end and the pill would stay red until the activity itself timed out, half an
/// hour later.
public func nextAnnouncementDeadline(
    for activities: [any Activity],
    announcementStarts: [ActivityIdentity: Date],
    after now: Date
) -> Date? {
    activities
        .compactMap { activity -> Date? in
            guard let window = activity.compactAnnouncementWindow,
                let start = announcementStarts[activity.identity]
            else {
                return nil
            }
            let deadline = start.addingTimeInterval(window)
            return deadline > now ? deadline : nil
        }
        .min()
}

/// When each activity started claiming the pill under an announcement window.
///
/// Carried forward for as long as the window persists, so an agent repeating the
/// same failure every forty seconds does not restart its own announcement and
/// sit in the pill forever. Cleared the moment the activity has something else
/// to say, which is what lets a recovered agent announce itself again.
public func advancedAnnouncementStarts(
    previous: [ActivityIdentity: Date],
    activities: [any Activity],
    now: Date
) -> [ActivityIdentity: Date] {
    var advanced: [ActivityIdentity: Date] = [:]
    for activity in activities where activity.compactAnnouncementWindow != nil {
        advanced[activity.identity] = previous[activity.identity] ?? now
    }
    return advanced
}

/// The slots still drawn, once the music icons that have timed out are removed.
///
/// Public because everything that sizes the compact pill has to agree on it:
/// the view that draws the icons, the surface drawn behind them, and the hover
/// target. Sizing any of those from the unfiltered set is what left a long
/// black bar behind a hidden icon.
public func visibleCompactSlots(
    _ slots: [CompactSlot],
    hiding hiddenSlotIDs: Set<String>
) -> [CompactSlot] {
    guard hiddenSlotIDs.isEmpty == false else { return slots }
    return slots.filter { !hiddenSlotIDs.contains($0.id) }
}

/// The pill's layout for `presentation`, with timed-out music icons removed.
public func compactSlotLayout(
    for presentation: CompactActivityPresentation,
    hiding hiddenSlotIDs: Set<String>
) -> CompactSlotLayout {
    compactSlotLayout(
        for: visibleCompactSlots(compactSlots(for: presentation), hiding: hiddenSlotIDs)
    )
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
    @Binding private var hiddenMusicSlotIDs: Set<String>

    public init(
        presentation: CompactActivityPresentation,
        notchSize: CGSize,
        hiddenMusicSlotIDs: Binding<Set<String>> = .constant([]),
        metrics: CompactPillMetrics = .default,
        motion: IslandMotion = .default
    ) {
        self.presentation = presentation
        self.notchSize = notchSize
        _hiddenMusicSlotIDs = hiddenMusicSlotIDs
        self.metrics = metrics
        self.motion = motion
    }

    public var body: some View {
        let slots = compactSlots(for: presentation)
        let visibleSlots = visibleCompactSlots(slots, hiding: hiddenMusicSlotIDs)
        let layout = compactSlotLayout(for: visibleSlots)
        let size = compactPillSize(for: layout, notchSize: notchSize, metrics: metrics)

        let surface = islandCompactSurface(scheme: colorScheme.islandColorScheme)

        // Zero spacing on the row, because each flank already carries its own
        // gap to the notch — and only when it has slots. An `HStack` spacing
        // would add that gap on an empty flank too, which is the stub this
        // layout exists to avoid.
        HStack(spacing: 0) {
            slotRow(layout.leading)
            Color.clear.frame(width: notchWidthWithGaps(for: layout))
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

    /// The opaque notch plus the gap owed to each occupied flank.
    ///
    /// Folded into the notch spacer rather than left to the enclosing stack's
    /// spacing so an empty flank contributes nothing at all — no slot width and
    /// no gap.
    private func notchWidthWithGaps(for layout: CompactSlotLayout) -> CGFloat {
        notchSize.width
            + (layout.leading.isEmpty ? 0 : metrics.slotSpacing)
            + (layout.trailing.isEmpty ? 0 : metrics.slotSpacing)
    }

    /// One flank, at exactly the width of the slots it holds.
    ///
    /// Sized to its content rather than given `maxWidth: .infinity`: with the
    /// latter the two flanks split the free space evenly, so an empty flank
    /// still claimed half of it and the occupied one was drawn too narrow.
    private func slotRow(_ slots: [CompactSlot]) -> some View {
        HStack(spacing: metrics.slotSpacing) {
            ForEach(slots) { slot in
                slotView(slot)
                    .transition(slotTransition)
            }
        }
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
        let newSlotIDs = musicIconVisibility.synchronize(
            activeSlots: slots,
            hiddenSlotIDs: &hiddenMusicSlotIDs
        )
        for slotID in newSlotIDs {
            do {
                try await Task.sleep(for: CompactMusicIconVisibility.visibleDuration)
            } catch {
                return
            }
            guard musicIconVisibility.hasAnnounced(slotID) else { continue }
            hiddenMusicSlotIDs.insert(slotID)
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
                // Cancellation — the slot leaving the hierarchy before the
                // announcement finishes — is the only error thrown, and
                // settling straight to the static glyph is the correct
                // response to it, so it is dropped rather than propagated.
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
