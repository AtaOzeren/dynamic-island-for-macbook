import KerNotchCore
import SwiftUI

public func recordingActivityTitleKey(for source: RecordingSource) -> String {
    switch source {
    case .screen: "Screen recording in progress"
    case .audio: "Microphone in use"
    }
}

/// Source-specific recording copy and glyphs shared by compact and expanded
/// surfaces. No recorder app is named because the provider does not know one.
public struct RecordingPresentation: Equatable, Sendable {
    public let source: RecordingSource

    public init(activity: RecordingActivity) {
        self.init(source: activity.source)
    }

    public init(source: RecordingSource) {
        self.source = source
    }

    public var symbolName: String {
        switch source {
        case .screen: "display"
        case .audio: "mic.fill"
        }
    }

    public var title: String {
        localized(String.LocalizationValue(recordingActivityTitleKey(for: source)))
    }

    public var accessibilityLabel: String { title }
}

/// What the compact pill draws for the captures in progress.
public enum CompactRecordingIndicator: Equatable, Sendable {
    case screen
    case microphone
    /// Both at once, drawn as one icon: the screen mark carrying a microphone
    /// badge, the way the Discord call carries Discord's.
    case screenAndMicrophone

    init(source: RecordingSource) {
        switch source {
        case .screen: self = .screen
        case .audio: self = .microphone
        }
    }

    var symbolName: String {
        RecordingPresentation(source: leadingSource).symbolName
    }

    var accessibilityLabel: String {
        switch self {
        case .screen, .microphone:
            RecordingPresentation(source: leadingSource).accessibilityLabel
        case .screenAndMicrophone:
            localized("Screen recording and microphone in use")
        }
    }

    /// The capture whose mark the icon is built on.
    private var leadingSource: RecordingSource {
        switch self {
        case .screen, .screenAndMicrophone: .screen
        case .microphone: .audio
        }
    }

    /// A single capture keeps its own identity; both together are the group's,
    /// so the icon is replaced as a whole when the second capture joins.
    func slotIdentity(for activity: RecordingActivity) -> ActivityIdentity {
        switch self {
        case .screen, .microphone: activity.identity
        case .screenAndMicrophone: activity.compactGroupIdentity
        }
    }
}

/// The recording slot. `sourceCount` is how many captures the compact group
/// stands for; the activity is only the one that represents it.
public func recordingCompactSlot(
    for activity: RecordingActivity,
    sourceCount: Int = 1
) -> CompactSlot {
    CompactSlot(
        recording: activity,
        indicator: sourceCount > 1
            ? .screenAndMicrophone
            : CompactRecordingIndicator(source: activity.source)
    )
}

struct CompactRecordingIcon: View {
    let indicator: CompactRecordingIndicator
    /// The height of the icon band every island icon is drawn in. The screen
    /// mark is wider than it is tall, so it is built from the width that makes
    /// it exactly this tall rather than from the band's own measure.
    let size: CGFloat

    var body: some View {
        switch indicator {
        case .screen:
            AnimatedScreenRecordingIcon(size: ScreenRecordingGlyph.size(fittingHeight: size))
        case .microphone:
            AnimatedMicrophoneRecordingIcon(size: size)
        case .screenAndMicrophone:
            AnimatedScreenRecordingIcon(size: ScreenRecordingGlyph.size(fittingHeight: size))
                .overlay(alignment: .bottomTrailing) {
                    MicrophoneRecordingBadge(diameter: size * Self.badgeScale)
                        .offset(x: size * 0.22, y: size * 0.24)
                }
        }
    }

    /// The same proportion the Discord badge rides its microphone at, so the two
    /// badged icons read as one family.
    private static let badgeScale: CGFloat = 0.62
}

/// A red disc with a white microphone, ringed in the pill's own black so it
/// separates from the monitor outline it overlaps.
struct MicrophoneRecordingBadge: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(.red)
            .overlay {
                Image(systemName: "mic.fill")
                    .font(.system(size: diameter * 0.58, weight: .bold))
                    .foregroundStyle(.white)
            }
            .overlay {
                Circle().strokeBorder(.black, lineWidth: max(diameter * 0.1, 1))
            }
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

/// Compact recording mark: a restrained monitor outline and red capture dot.
/// Three short pulses announce capture start; it then becomes static so a long
/// recording does not retain a render loop.
struct AnimatedScreenRecordingIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dotScale: CGFloat = 1

    private static let pulseDuration = Duration.milliseconds(420)
    private static let pulseCount = 3

    let size: CGFloat

    var body: some View {
        ScreenRecordingGlyph(size: size, dotScale: dotScale)
            .task {
                guard reduceMotion == false else { return }
                for _ in 0..<Self.pulseCount {
                    withAnimation(.easeInOut(duration: 0.42)) {
                        dotScale = 0.55
                    }
                    // The only error Task.sleep throws here is cancellation —
                    // the slot leaving the hierarchy mid-pulse — and the
                    // isCancelled guards turn that into a clean exit, so the
                    // thrown error is deliberately dropped. Applies to both
                    // pulse sleeps in this loop.
                    try? await Task.sleep(for: Self.pulseDuration)
                    guard Task.isCancelled == false else { return }

                    withAnimation(.easeInOut(duration: 0.42)) {
                        dotScale = 1
                    }
                    try? await Task.sleep(for: Self.pulseDuration)
                    guard Task.isCancelled == false else { return }
                }
            }
            .accessibilityHidden(true)
    }
}

/// Compact microphone mark: a clear red microphone with three restrained
/// breaths, then a static glyph. Motion announces the privacy-sensitive edge
/// without competing with the screen-recording indicator beside it.
struct AnimatedMicrophoneRecordingIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var symbolScale: CGFloat = 1

    static let pulseCount = 3
    private static let pulseDuration = Duration.milliseconds(300)

    let size: CGFloat

    var body: some View {
        IslandSymbolIcon(systemName: "mic.fill", height: size)
            .foregroundStyle(.red)
            .scaleEffect(symbolScale)
            .task {
                guard reduceMotion == false else { return }
                for _ in 0..<Self.pulseCount {
                    withAnimation(.easeOut(duration: 0.3)) {
                        symbolScale = 1.12
                    }
                    // Cancellation — the slot leaving the hierarchy mid-breath —
                    // is the only error Task.sleep throws, and the isCancelled
                    // guards convert it to a clean exit, so it is dropped
                    // rather than propagated. Applies to both sleeps below.
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

struct ScreenRecordingGlyph: View {
    /// How tall the glyph draws as a fraction of `size`: a monitor is wider
    /// than it is tall, so its width is what `size` sets.
    static let heightRatio: CGFloat = 0.72

    static func size(fittingHeight height: CGFloat) -> CGFloat {
        height / heightRatio
    }

    let size: CGFloat
    let dotScale: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                .stroke(lineWidth: max(size * 0.1, 1))

            Circle()
                .fill(.red)
                .frame(width: size * 0.32, height: size * 0.32)
                .scaleEffect(dotScale)
        }
        .frame(width: size, height: size * Self.heightRatio)
    }
}

/// Expanded recording row: one icon and one explicit sentence. No elapsed
/// counter or app attribution competes with the status the user asked to see.
public struct RecordingActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let presentation: RecordingPresentation
    private let metrics: ExpandedPanelMetrics

    public init(
        activity: RecordingActivity,
        metrics: ExpandedPanelMetrics = .default
    ) {
        presentation = RecordingPresentation(activity: activity)
        self.metrics = metrics
    }

    public var body: some View {
        let surface = islandExpandedSurface(
            scheme: colorScheme.islandColorScheme,
            reduceTransparency: reduceTransparency
        )

        HStack(spacing: 0) {
            icon
                .frame(width: metrics.symbolColumnWidth)

            Text(presentation.title)
                .font(.system(size: metrics.titleSize, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch presentation.source {
        case .screen:
            // A monitor is wider than it is tall, so its width is what the
            // symbol size sets — the icon box keeps the same air around it that
            // a symbol has, instead of the glyph reaching the text.
            ScreenRecordingGlyph(size: metrics.symbolSize, dotScale: 1)
        case .audio:
            IslandSymbolIcon(systemName: presentation.symbolName, height: metrics.symbolSize)
                .foregroundStyle(.red)
        }
    }
}
