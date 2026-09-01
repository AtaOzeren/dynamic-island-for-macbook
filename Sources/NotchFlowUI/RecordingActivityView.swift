import NotchFlowCore
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
        source = activity.source
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

public func recordingCompactSlot(for activity: RecordingActivity) -> CompactSlot {
    CompactSlot(
        recording: activity,
        presentation: RecordingPresentation(activity: activity)
    )
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
        Image(systemName: "mic.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.red)
            .scaleEffect(symbolScale)
            .task {
                guard reduceMotion == false else { return }
                for _ in 0..<Self.pulseCount {
                    withAnimation(.easeOut(duration: 0.3)) {
                        symbolScale = 1.12
                    }
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
        .frame(width: size, height: size * 0.72)
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
                .font(.system(size: metrics.symbolSize, weight: .medium))
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
            ScreenRecordingGlyph(size: metrics.symbolSize * 0.88, dotScale: 1)
        case .audio:
            Image(systemName: presentation.symbolName)
                .font(.system(size: metrics.symbolSize * 0.88, weight: .medium))
                .foregroundStyle(.red)
        }
    }
}
