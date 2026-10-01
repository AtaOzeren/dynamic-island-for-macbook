import CoreGraphics
import KerNotchCore
import SwiftUI

public struct CompactMusicSlotPresentation: Equatable, Sendable {
    public let isPlaying: Bool
    public let sourceIdentity: MusicSourceIdentity

    public init(activity: MusicActivity) {
        isPlaying = activity.nowPlaying.playbackState == .playing
        sourceIdentity = MusicSourceIdentity(
            applicationName: activity.nowPlaying.sourceApplicationName
        )
    }
}

/// One drawn element of the compact pill: one compact group's icon.
public struct CompactSlot: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbolName: String
    public let accessibilityLabel: String

    /// Draws moving equaliser bars in place of the glyph. Carried as a flag
    /// rather than as a second symbol name because the bars are not a symbol:
    /// they animate, and only while something is actually playing.
    public let isPlayingMusic: Bool
    public let musicSourceIdentity: MusicSourceIdentity?
    public let recordingIndicator: CompactRecordingIndicator?
    public let discordCall: DiscordCallPresentation?
    public let charging: ChargingPresentation?
    let aiAgentPresentation: CompactAIAgentSlotPresentation?
    public var aiAgentID: IPCAgentID? { aiAgentPresentation?.agentID }

    fileprivate init(activity: any Activity) {
        id = activity.identity.rawValue
        symbolName = compactSymbolName(activity.kind)
        accessibilityLabel = compactAccessibilityLabel(activity.kind)
        isPlayingMusic = false
        musicSourceIdentity = nil
        recordingIndicator = nil
        discordCall = nil
        charging = nil
        aiAgentPresentation = nil
    }

    /// For activities whose per-instance detail outgrows what the kind alone can
    /// say — music announces "Windowlicker — Aphex Twin" rather than "Music".
    /// Omitting `symbolName` keeps the kind's glyph.
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
        self.accessibilityLabel = accessibilityLabel
        isPlayingMusic = musicPresentation?.isPlaying ?? false
        musicSourceIdentity = musicPresentation?.sourceIdentity
        recordingIndicator = nil
        discordCall = nil
        charging = nil
        self.aiAgentPresentation = aiAgentPresentation
    }

    init(
        recording activity: RecordingActivity,
        indicator: CompactRecordingIndicator
    ) {
        id = indicator.slotIdentity(for: activity).rawValue
        symbolName = indicator.symbolName
        accessibilityLabel = indicator.accessibilityLabel
        isPlayingMusic = false
        musicSourceIdentity = nil
        recordingIndicator = indicator
        discordCall = nil
        charging = nil
        aiAgentPresentation = nil
    }

    init(
        discordCall activity: DiscordCallActivity,
        presentation: DiscordCallPresentation
    ) {
        id = activity.identity.rawValue
        symbolName = presentation.microphoneSymbolName
        accessibilityLabel = presentation.accessibilityLabel
        isPlayingMusic = false
        musicSourceIdentity = nil
        recordingIndicator = nil
        discordCall = presentation
        charging = nil
        aiAgentPresentation = nil
    }

    init(
        charging activity: ChargingActivity,
        presentation: ChargingPresentation
    ) {
        id = activity.identity.rawValue
        symbolName = compactSymbolName(activity.kind)
        accessibilityLabel = presentation.accessibilityLabel
        isPlayingMusic = false
        musicSourceIdentity = nil
        recordingIndicator = nil
        discordCall = nil
        charging = presentation
        aiAgentPresentation = nil
    }
}

/// How the pill's slots divide around the notch. The notch itself is opaque
/// hardware, so the pill can only draw to either side of it; which slots go
/// where, and which are left out, is `CompactFlankAllocation`'s rule.
public struct CompactSlotLayout: Equatable, Sendable {
    public let leading: [CompactSlot]
    public let trailing: [CompactSlot]
    /// Where the pet is on the leading flank, or `nil` when no pet lives on
    /// the pill.
    public let petStage: PetStage?

    /// How many places the leading flank is drawn with.
    ///
    /// A pet on the pill has one place of its own, at the flank's outer end,
    /// and the icons take theirs beside it from the notch side: the pet alone
    /// widens the pill by one place, never more. With the flank full of icons
    /// the pet has left, and the flank is as wide as its icons.
    public var leadingPlaceCount: Int {
        guard let petStage, petStage != .away else { return leading.count }
        return leading.count + 1
    }
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
        leadingSlotCount: layout.leadingPlaceCount,
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
        leadingSlotCount: layout.leadingPlaceCount,
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
        leadingSlotCount: layout.leadingPlaceCount,
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
    balancedCompactPillSize(
        for: compactSlotLayout(for: presentation),
        notchSize: notchSize,
        metrics: metrics
    )
}

/// One activity's slot, routed to the kind that knows how to describe itself.
///
/// Music and charging both announce per-instance detail the shared kind label
/// cannot carry — the actual track, and how full the battery is.
///
/// `groupSize` is how many active activities the slot stands for. Only grouped
/// kinds have anything to say about it — the AI agent slot counts its sessions,
/// and the recording slot draws both captures at once — while every other kind
/// draws one icon per activity, so its group is always itself.
private func compactSlot(for activity: any Activity, groupSize: Int) -> CompactSlot {
    switch activity {
    case let music as MusicActivity: musicCompactSlot(for: music)
    case let recording as RecordingActivity:
        recordingCompactSlot(for: recording, sourceCount: groupSize)
    case let call as DiscordCallActivity: discordCallCompactSlot(for: call)
    case let charging as ChargingActivity: chargingCompactSlot(for: charging)
    case let aiAgent as AIAgentActivity:
        aiAgentCompactSlot(for: aiAgent, sessionCount: groupSize)
    default: CompactSlot(activity: activity)
    }
}

/// One slot per compact group, in the order `ActivityManager` ranked them.
/// Every group gets one; which of them are drawn is the layout's decision.
public func compactSlots(for presentation: CompactActivityPresentation) -> [CompactSlot] {
    presentation.activities.map { activity in
        compactSlot(
            for: activity,
            groupSize: presentation.groupSizes[activity.compactGroupIdentity] ?? 1
        )
    }
}

/// Splits the slots around the notch, leaving out the standard slots the pill
/// has no room for.
public func compactSlotLayout(for presentation: CompactActivityPresentation) -> CompactSlotLayout {
    compactSlotLayout(for: compactSlots(for: presentation), housing: nil)
}

/// Allocated from the slots actually drawn, so a slot already taken off the
/// pill — a track paused long enough — never holds a place another icon needs,
/// and never pushes one to the other side of the notch.
///
/// A pet changes nothing about where the icons go. It is given the leading
/// places they leave free.
private func compactSlotLayout(for slots: [CompactSlot], housing pet: IslandPet?) -> CompactSlotLayout {
    let agentSlots = slots.filter { $0.aiAgentID != nil }
    let standardSlots = slots.filter { $0.aiAgentID == nil }
    let allocation = CompactFlankAllocation(
        standardCount: standardSlots.count,
        agentCount: agentSlots.count
    )

    return CompactSlotLayout(
        leading: Array(standardSlots.prefix(allocation.leadingStandardCount)),
        trailing: Array(
            standardSlots
                .dropFirst(allocation.leadingStandardCount)
                .prefix(allocation.trailingStandardCount)
        ) + agentSlots,
        petStage: pet.map { _ in
            PetStage(
                freePlaceCount: CompactFlankAllocation.slotsPerSide - allocation.leadingStandardCount
            )
        }
    )
}

/// The presentation with finished announcements taken out of the pill.
///
/// Hiding the slot is not enough: a group that keeps its slot because *some* of
/// it is live still has its muted failure speaking for it, which holds an
/// agent's icon red for hours while another instance of it runs happily.
///
/// That is deciding who speaks before knowing who has anything left to say, so
/// the agent side of the pill is re-picked here from the members that do. With
/// no announcement pending this returns the presentation untouched.
public func compactPresentation(
    _ presentation: CompactActivityPresentation,
    reconciledWith activities: [any Activity],
    announcementStarts: [ActivityIdentity: Date],
    registrationTimes: [ActivityIdentity: Date],
    now: Date
) -> CompactActivityPresentation {
    guard announcementStarts.isEmpty == false else { return presentation }

    let standard = presentation.activities.filter { $0.compactRegion != .agentTrailing }

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
        .sorted { (latest[$0.key] ?? .distantPast) < (latest[$1.key] ?? .distantPast) }
        .map(\.value)

    return CompactActivityPresentation(
        activities: standard + agents,
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

/// The pill's layout for `presentation`, with timed-out music icons removed and
/// the pet, when there is one, given the leading places the icons leave free.
///
/// `pet` has no default on purpose. Everything that sizes the pill — the icons,
/// the surface behind them, the hover target — has to agree on whether a pet
/// is keeping the leading flank open, and a default would let one of them
/// quietly size the pill without it.
public func compactSlotLayout(
    for presentation: CompactActivityPresentation,
    hiding hiddenSlotIDs: Set<String>,
    housing pet: IslandPet?
) -> CompactSlotLayout {
    compactSlotLayout(
        for: visibleCompactSlots(compactSlots(for: presentation), hiding: hiddenSlotIDs),
        housing: pet
    )
}

public func compactSymbolName(_ kind: ActivityKind) -> String {
    switch kind {
    case .music: "music.note"
    case .timer: "timer"
    case .recording: "record.circle"
    case .charging: "bolt.fill"
    case .aiAgent: "sparkles"
    case .watchdogNotice: "exclamationmark.triangle.fill"
    case .discordCall: "mic.fill"
    }
}

public func compactAccessibilityLabel(_ kind: ActivityKind) -> String {
    switch kind {
    case .music: localized("Music")
    case .timer: localized("Timer")
    case .recording: localized("Recording")
    case .charging: localized("Charging")
    case .aiAgent: localized("AI agent")
    case .watchdogNotice: localized("High CPU recovery")
    case .discordCall: localized("Discord call")
    }
}

/// The compact pill: activity icons hugging both edges of the notch, with the
/// notch's own width held open between them.
public struct CompactActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.prefersReducedIslandMotion) private var reduceMotion
    @Environment(\.drawsOwnIslandSurface) private var drawsOwnSurface
    /// The clock the island itself is moving on. The pill's own width follows
    /// the island's shape, and its icons follow a hair behind it.
    @Environment(\.islandContentMotion) private var islandMotion

    private let presentation: CompactActivityPresentation
    private let notchSize: CGSize
    private let metrics: CompactPillMetrics

    /// Music icons the presenter has taken off the pill. Read, never written:
    /// the presenter's clocks own the countdown, because this view is rebuilt
    /// every time the island expands and collapses.
    private let hiddenMusicSlotIDs: Set<String>

    /// The pet on the leading flank, which keeps the flank open. The pet itself
    /// is drawn by the island, which carries it between the compact and the
    /// open island; the icons only make room for it.
    private let pet: IslandPet?

    public init(
        presentation: CompactActivityPresentation,
        notchSize: CGSize,
        hiddenMusicSlotIDs: Set<String> = [],
        pet: IslandPet? = nil,
        metrics: CompactPillMetrics = .default
    ) {
        self.presentation = presentation
        self.notchSize = notchSize
        self.hiddenMusicSlotIDs = hiddenMusicSlotIDs
        self.pet = pet
        self.metrics = metrics
    }

    public var body: some View {
        let slots = compactSlots(for: presentation)
        let visibleSlots = visibleCompactSlots(slots, hiding: hiddenMusicSlotIDs)
        let layout = compactSlotLayout(for: visibleSlots, housing: pet)
        let size = compactPillSize(for: layout, notchSize: notchSize, metrics: metrics)

        let surface = islandCompactSurface(scheme: colorScheme.islandColorScheme)

        // Zero spacing on the row, because each flank already carries its own
        // gap to the notch — and only when it has slots. An `HStack` spacing
        // would add that gap on an empty flank too, which is the stub this
        // layout exists to avoid.
        HStack(spacing: 0) {
            slotRow(layout.leading)
                .frame(width: petFlankWidth(for: layout), alignment: .trailing)
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
    }

    /// The opaque notch plus the gap owed to each occupied flank.
    ///
    /// Folded into the notch spacer rather than left to the enclosing stack's
    /// spacing so an empty flank contributes nothing at all — no slot width and
    /// no gap.
    private func notchWidthWithGaps(for layout: CompactSlotLayout) -> CGFloat {
        notchSize.width
            + (layout.leadingPlaceCount == 0 ? 0 : metrics.slotSpacing)
            + (layout.trailing.isEmpty ? 0 : metrics.slotSpacing)
    }

    /// The whole leading flank while a pet lives there, so the icons sit
    /// against the notch and the pet has the outer place; `nil` without one,
    /// leaving the flank exactly as wide as its icons.
    private func petFlankWidth(for layout: CompactSlotLayout) -> CGFloat? {
        guard layout.petStage != nil else { return nil }
        return compactSideWidth(slotCount: layout.leadingPlaceCount, metrics: metrics)
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
        .animation(islandMotion.content, value: slots)
    }

    /// Slots grow out of, and shrink back into, the notch's edge rather than
    /// appearing at full size, so an activity starting reads as the island
    /// extending rather than as a glyph blinking into place.
    private var slotTransition: AnyTransition {
        guard reduceMotion == false else { return .opacity }
        return .scale(scale: 0.6).combined(with: .opacity)
    }

    /// Every icon is drawn in the same band: the agent logo's own, so a
    /// microphone, a battery and a logo sit at one height and on one centre
    /// line. Each glyph used to carry a factor of its own, which is why a
    /// microphone came out taller than the warning triangle beside it and a
    /// screen mark shorter than both.
    private func slotView(_ slot: CompactSlot) -> some View {
        Group {
            if let aiAgentPresentation = slot.aiAgentPresentation {
                CompactAIAgentIcon(
                    presentation: aiAgentPresentation,
                    iconSize: metrics.symbolSize
                )
            } else {
                slotIcon(slot)
                    .frame(height: metrics.symbolSize)
                    .padding(.top, metrics.iconBandTopInset)
                    .frame(height: metrics.slotHeight, alignment: .top)
            }
        }
        .frame(width: metrics.slotWidth)
        .accessibilityLabel(slot.accessibilityLabel)
    }

    @ViewBuilder
    private func slotIcon(_ slot: CompactSlot) -> some View {
        Group {
            if let recordingIndicator = slot.recordingIndicator {
                CompactRecordingIcon(indicator: recordingIndicator, size: metrics.symbolSize)
            } else if let charging = slot.charging {
                BatteryLevelGlyph(
                    presentation: charging,
                    size: BatteryLevelGlyph.size(fittingWidth: metrics.wideIconWidth)
                )
            } else if let discordCall = slot.discordCall {
                DiscordCallIcon(
                    presentation: discordCall,
                    size: metrics.symbolSize,
                    animatesArrival: true
                )
            } else if let sourceIdentity = slot.musicSourceIdentity {
                if slot.isPlayingMusic {
                    MusicEqualiserSlotView(
                        metrics: metrics,
                        symbolName: slot.symbolName,
                        sourceIdentity: sourceIdentity
                    )
                } else {
                    IslandSymbolIcon(systemName: slot.symbolName, height: metrics.symbolSize)
                        .foregroundStyle(musicAccentColor(sourceIdentity))
                }
            } else {
                IslandSymbolIcon(systemName: slot.symbolName, height: metrics.symbolSize)
            }
        }
    }
}

extension CompactPillMetrics {
    /// How far below the pill's top the icon band begins. The agent slot hangs
    /// a session-count badge above its logo, and every other icon lines up with
    /// that logo rather than with the badge's corner.
    var iconBandTopInset: CGFloat { CompactAIAgentMetrics.default.countBadgeOverhang }

    /// The whole slot: the badge's corner, the icon band, and the room the
    /// agent's status light hangs in underneath.
    var slotHeight: CGFloat {
        iconBandTopInset + CompactAIAgentMetrics.default.statusBaseline(iconSize: symbolSize)
    }

    /// How wide an icon that cannot be square — the battery — is drawn. Narrower
    /// than the slot, so it keeps the air its neighbours have around them
    /// instead of reaching the icon beside it.
    var wideIconWidth: CGFloat { (slotWidth * 0.8).rounded() }
}
