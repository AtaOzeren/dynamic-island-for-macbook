import CoreGraphics
import NotchFlowCore
import SwiftUI

/// One drawn element of the compact pill: either an activity's icon or the
/// single overflow indicator that stands in for everything past the capacity in
/// `docs/05-activity-model.md`.
public struct CompactSlot: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbolName: String
    public let label: String?
    public let overflowCount: Int?
    public let accessibilityLabel: String

    fileprivate init(activity: any Activity) {
        id = activity.identity.rawValue
        symbolName = compactSymbolName(activity.kind)
        label = nil
        overflowCount = nil
        accessibilityLabel = compactAccessibilityLabel(activity.kind)
    }

    fileprivate init(overflowCount: Int) {
        id = Self.overflowIdentifier
        symbolName = "ellipsis"
        label = "+\(overflowCount)"
        self.overflowCount = overflowCount
        accessibilityLabel = "\(overflowCount) more activities"
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

/// The pill's fixed visual budget. Every size the compact view draws comes from
/// here, so a change to the island's density is one edit, not a sweep.
public struct CompactPillMetrics: Equatable, Sendable {
    public static let `default` = CompactPillMetrics()

    public let slotWidth: CGFloat
    public let slotSpacing: CGFloat
    public let edgeInset: CGFloat
    public let symbolSize: CGFloat
    public let cornerRadius: CGFloat

    public init(
        slotWidth: CGFloat = 22,
        slotSpacing: CGFloat = 6,
        edgeInset: CGFloat = 10,
        symbolSize: CGFloat = 13,
        cornerRadius: CGFloat = 12
    ) {
        self.slotWidth = slotWidth
        self.slotSpacing = slotSpacing
        self.edgeInset = edgeInset
        self.symbolSize = symbolSize
        self.cornerRadius = cornerRadius
    }
}

/// The ordered slots for `presentation`, which has already applied the priority
/// ordering and the capacity limit in `ActivityManager`.
public func compactSlots(for presentation: CompactActivityPresentation) -> [CompactSlot] {
    let slots = presentation.activities.map(CompactSlot.init(activity:))
    guard presentation.overflowCount > 0 else { return slots }
    return slots + [CompactSlot(overflowCount: presentation.overflowCount)]
}

/// Splits the slots around the notch, filling the leading side first so the
/// overflow indicator — always last — lands on the trailing side.
public func compactSlotLayout(for presentation: CompactActivityPresentation) -> CompactSlotLayout {
    let slots = compactSlots(for: presentation)
    let leadingCount = (slots.count + 1) / 2
    return CompactSlotLayout(
        leading: Array(slots.prefix(leadingCount)),
        trailing: Array(slots.dropFirst(leadingCount))
    )
}

/// The pill's drawn size: exactly as tall as the notch it hugs, and wide enough
/// for the notch plus the slots flanking it, per the compact row of the state
/// table in `docs/04-overlay-window.md`.
public func compactPillSize(
    slotCount: Int,
    notchSize: CGSize,
    metrics: CompactPillMetrics = .default
) -> CGSize {
    let slots = max(slotCount, 0)
    guard slots > 0 else { return notchSize }

    let slotsWidth = CGFloat(slots) * metrics.slotWidth
    let spacing = CGFloat(slots) * metrics.slotSpacing
    return CGSize(
        width: notchSize.width + slotsWidth + spacing + metrics.edgeInset * 2,
        height: notchSize.height
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
    case .music: "Music"
    case .timer: "Timer"
    case .recording: "Recording"
    case .charging: "Charging"
    case .aiAgent: "AI agent"
    case .fileTransfer: "Transfer"
    }
}

/// The compact pill: activity icons hugging both edges of the notch, with the
/// notch's own width held open between them.
public struct CompactActivityView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let presentation: CompactActivityPresentation
    private let notchSize: CGSize
    private let metrics: CompactPillMetrics

    public init(
        presentation: CompactActivityPresentation,
        notchSize: CGSize,
        metrics: CompactPillMetrics = .default
    ) {
        self.presentation = presentation
        self.notchSize = notchSize
        self.metrics = metrics
    }

    public var body: some View {
        let layout = compactSlotLayout(for: presentation)
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
            surface.fill(in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        }
        .environment(\.colorScheme, surface.foreground == .onDark ? .dark : .light)
    }

    private func slotRow(_ slots: [CompactSlot]) -> some View {
        HStack(spacing: metrics.slotSpacing) {
            ForEach(slots) { slot in
                slotView(slot)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func slotView(_ slot: CompactSlot) -> some View {
        Group {
            if let label = slot.label {
                Text(label)
                    .font(.system(size: metrics.symbolSize, weight: .semibold, design: .rounded))
            } else {
                Image(systemName: slot.symbolName)
                    .font(.system(size: metrics.symbolSize, weight: .medium))
            }
        }
        .frame(width: metrics.slotWidth)
        .accessibilityLabel(slot.accessibilityLabel)
    }
}
