import Foundation
import KerNotchCore

/// Everything on the island that changes with time rather than with an event,
/// kept together so the presenter needs a single wake-up for all of it.
///
/// Three things end on a clock: a blocked agent's announcement in the pill, a
/// paused track's note, and the attention glow. None of them produces an event
/// when its time runs out, so something has to wake the island at the right
/// moment — and three separate timers would be three chances to forget one.
///
/// Lives beside the presentation rather than in `ActivityManager`: this is
/// presentation state, and adding any stored property to that class makes the
/// whole test suite abort inside `swift_task_dealloc`, reproducibly.
public struct IslandPresentationClocks: Sendable {
    /// What the clocks say right now, for the views to draw.
    public struct Reading: Equatable, Sendable {
        public let announcementStarts: [ActivityIdentity: Date]
        public let hiddenMusicSlotIDs: Set<String>
        public let attentionGlow: IslandAttentionGlow?
    }

    public private(set) var reading = Reading(
        announcementStarts: [:],
        hiddenMusicSlotIDs: [],
        attentionGlow: nil
    )

    /// The next moment any reading changes on its own, or `nil` when nothing is
    /// counting down — which is what keeps an idle island free of wake-ups.
    public private(set) var nextDeadline: Date?

    /// The user's AI Integrations switch for the glow.
    ///
    /// Switching it off hides the glow but keeps tracking the moments behind
    /// it, so switching it back on shows only what is still running rather than
    /// replaying news that arrived while it was off.
    public var showsAttentionGlow = true

    private var musicIcons = CompactMusicIconVisibility()
    private var glowTracker = IslandAttentionGlowTracker()

    /// A glow the user asked to see from Settings, so they know what the switch
    /// controls. It belongs to no session, so nothing an agent does ends it
    /// early, and it shows even with the switch off — it is how someone decides
    /// whether to turn it on.
    private var previewGlow: IslandAttentionGlow?

    public init() {}

    /// Plays the preview's single crossing; a second press starts it over.
    public mutating func previewAttentionGlow(at now: Date) {
        previewGlow = .preview(startedAt: now)
    }

    public mutating func advance(
        activities: [any Activity],
        registrationTimes: [ActivityIdentity: Date],
        now: Date
    ) {
        let announcementStarts = advancedAnnouncementStarts(
            previous: reading.announcementStarts,
            activities: activities,
            now: now
        )
        musicIcons.advance(
            slots: activities.compactMap { $0 as? MusicActivity }.map(musicCompactSlot(for:)),
            now: now
        )
        glowTracker.advance(activities: activities, registrationTimes: registrationTimes, now: now)

        if let preview = previewGlow, now >= preview.endsAt {
            previewGlow = nil
        }
        // A real agent's news outranks a demonstration of it.
        let attentionGlow = (showsAttentionGlow ? glowTracker.glow : nil) ?? previewGlow
        reading = Reading(
            announcementStarts: announcementStarts,
            hiddenMusicSlotIDs: musicIcons.hiddenSlotIDs(at: now),
            attentionGlow: attentionGlow
        )
        nextDeadline = [
            nextAnnouncementDeadline(for: activities, announcementStarts: announcementStarts, after: now),
            musicIcons.nextDeadline(after: now),
            attentionGlow?.endsAt,
        ]
        .compactMap { $0 }
        .min()
    }
}
