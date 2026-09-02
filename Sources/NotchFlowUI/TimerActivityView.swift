import CoreGraphics
import Foundation
import NotchFlowCore
import SwiftUI

/// One timer control: the command it sends, the glyph it draws, and the label
/// VoiceOver reads.
///
/// A value rather than a `Button`, on the same rationale as
/// `MusicTransportControl` — the set of controls a given timer state offers is
/// then assertable without rendering anything.
public struct TimerControl: Identifiable, Equatable, Sendable {
    public let command: TimerControlCommand
    public let symbolName: String
    public let accessibilityLabel: String

    public var id: String { accessibilityLabel }
}

/// What a timer control asks for. Deliberately a separate vocabulary from
/// `TimerProvider`'s command enum: the view layer describes the gesture, and
/// the composition root decides which provider call it maps to, exactly as the
/// music views describe transport without owning a backend.
public enum TimerControlCommand: Equatable, Sendable, CaseIterable {
    case pause
    case resume
    case stop
}

/// Everything the timer views draw, derived from `TimerActivity` alone.
public struct TimerPresentation: Equatable, Sendable {
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600

    /// The clock face, e.g. "04:59" or "1:02:03".
    public let time: String
    /// What the timer is, in words — "Countdown", "Stopwatch", or "Time's up".
    public let title: String
    public let isRunning: Bool
    public let isExpiring: Bool

    public init(activity: TimerActivity) {
        let displayed = activity.remaining ?? activity.elapsed

        time = Self.clockFace(displayed)
        isRunning = activity.isRunning
        isExpiring = activity.isExpiring
        title = Self.title(for: activity)
    }

    /// Stop is always offered; pause and resume are mutually exclusive, and
    /// neither is offered once the countdown has expired — there is nothing
    /// left to pause.
    public var controls: [TimerControl] {
        guard isExpiring == false else {
            return [Self.stopControl(label: localized("Dismiss timer"), symbolName: "checkmark")]
        }

        return [
            isRunning
                ? TimerControl(command: .pause, symbolName: "pause.fill", accessibilityLabel: localized("Pause timer"))
                : TimerControl(
                    command: .resume, symbolName: "play.fill", accessibilityLabel: localized("Resume timer")),
            Self.stopControl(label: localized("Stop timer"), symbolName: "stop.fill"),
        ]
    }

    /// What VoiceOver reads for the whole activity: the remaining or elapsed
    /// time spoken in words, prefixed by state only when it is not the expected
    /// one.
    public var accessibilityLabel: String {
        guard isExpiring == false else { return localized("Timer finished") }

        let spoken = localized("activity.accessibility.headlineAndDetail", default: "\(title), \(time)")
        return isRunning ? spoken : localized("Paused: \(spoken)")
    }

    private static func stopControl(label: String, symbolName: String) -> TimerControl {
        TimerControl(command: .stop, symbolName: symbolName, accessibilityLabel: label)
    }

    private static func title(for activity: TimerActivity) -> String {
        guard activity.isExpiring == false else { return localized("Time's up") }

        switch activity.mode {
        case .countdown: return localized("Countdown")
        case .stopwatch: return localized("Stopwatch")
        }
    }

    /// Whole seconds only: the tick's leeway means sub-second precision would
    /// be a lie, and a display that redraws faster than it can be trusted is
    /// wakeups spent on noise.
    ///
    /// The hour field appears only once there are hours, so the common case
    /// stays the narrow "mm:ss" the compact pill is sized for.
    private static func clockFace(_ duration: Duration) -> String {
        let total = max(0, Int(duration.components.seconds))
        let hours = total / secondsPerHour
        let minutes = (total % secondsPerHour) / secondsPerMinute
        let seconds = total % secondsPerMinute

        guard hours > 0 else {
            return String(format: "%02d:%02d", minutes, seconds)
        }

        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}

/// The timer activity's compact slot: the shared timer glyph, but announcing
/// the actual time rather than the generic "Timer" the kind-based label makes.
public func timerCompactSlot(for activity: TimerActivity) -> CompactSlot {
    CompactSlot(
        activity: activity,
        accessibilityLabel: TimerPresentation(activity: activity).accessibilityLabel
    )
}

/// The expanded timer view's visual budget, the timer counterpart to
/// `MusicViewMetrics` — one edit changes the timer row's density.
public struct TimerViewMetrics: Equatable, Sendable {
    public static let `default` = TimerViewMetrics()

    public let glyphSize: CGFloat
    public let contentInset: CGFloat
    public let textSpacing: CGFloat
    public let columnSpacing: CGFloat
    public let timeSize: CGFloat
    public let titleSize: CGFloat
    public let controlSymbolSize: CGFloat
    public let controlButtonSize: CGFloat
    public let controlSpacing: CGFloat
    public let cornerRadius: CGFloat
    public let width: CGFloat

    public init(
        glyphSize: CGFloat = 44,
        contentInset: CGFloat = 12,
        textSpacing: CGFloat = 2,
        columnSpacing: CGFloat = 12,
        timeSize: CGFloat = 20,
        titleSize: CGFloat = IslandTypeScale.default.title,
        controlSymbolSize: CGFloat = 13,
        controlButtonSize: CGFloat = 28,
        controlSpacing: CGFloat = 4,
        cornerRadius: CGFloat = 18,
        width: CGFloat = 320
    ) {
        self.glyphSize = glyphSize
        self.contentInset = contentInset
        self.textSpacing = textSpacing
        self.columnSpacing = columnSpacing
        self.timeSize = timeSize
        self.titleSize = titleSize
        self.controlSymbolSize = controlSymbolSize
        self.controlButtonSize = controlButtonSize
        self.controlSpacing = controlSpacing
        self.cornerRadius = cornerRadius
        self.width = width
    }
}

/// The expanded timer view's drawn size, clamped to the window's allocated
/// maximum for the same reason `musicExpandedSize` clamps: the `NSPanel` frame
/// is allocated once and never resized, so anything past it is silently clipped.
public func timerExpandedSize(
    metrics: TimerViewMetrics = .default,
    panelMetrics: PanelMetrics = .default
) -> CGSize {
    let contentHeight = max(metrics.glyphSize, metrics.controlButtonSize)
    return CGSize(
        width: min(metrics.width, panelMetrics.maximumExpandedSize.width),
        height: min(
            contentHeight + metrics.contentInset * 2,
            panelMetrics.maximumExpandedSize.height
        )
    )
}

/// The expanded timer row: the timer glyph, the clock face and its label, and
/// the pause/resume/stop controls.
///
/// Takes the activity rather than the provider, which is what keeps the view
/// free of the tick's lifetime; sending the command is the composition root's
/// job.
public struct TimerExpandedView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public let presentation: TimerPresentation
    private let metrics: TimerViewMetrics
    private let panelMetrics: PanelMetrics
    private let onCommand: (TimerControlCommand) -> Void

    public init(
        activity: TimerActivity,
        metrics: TimerViewMetrics = .default,
        panelMetrics: PanelMetrics = .default,
        onCommand: @escaping (TimerControlCommand) -> Void = { _ in }
    ) {
        presentation = TimerPresentation(activity: activity)
        self.metrics = metrics
        self.panelMetrics = panelMetrics
        self.onCommand = onCommand
    }

    /// Dispatches a control's command. Exposed so a test can drive the same
    /// path a tap takes without rendering into a window server.
    public func perform(_ control: TimerControl) {
        onCommand(control.command)
    }

    public var body: some View {
        let size = timerExpandedSize(metrics: metrics, panelMetrics: panelMetrics)
        let surface = islandExpandedSurface(
            scheme: colorScheme.islandColorScheme,
            reduceTransparency: reduceTransparency
        )

        HStack(spacing: metrics.columnSpacing) {
            glyph
            timeText
            Spacer(minLength: 0)
            controls
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

    private var glyph: some View {
        RoundedRectangle(cornerRadius: metrics.textSpacing * 2, style: .continuous)
            .fill(.quaternary)
            .frame(width: metrics.glyphSize, height: metrics.glyphSize)
            .overlay {
                Image(systemName: compactSymbolName(.timer))
                    .font(.system(size: metrics.titleSize, weight: .medium))
            }
            .accessibilityHidden(true)
    }

    private var timeText: some View {
        VStack(alignment: .leading, spacing: metrics.textSpacing) {
            Text(presentation.time)
                // Monospaced digits keep the row from twitching as the seconds
                // change width — the one place proportional figures would make
                // a once-a-second redraw visibly restless.
                .font(.system(size: metrics.timeSize, weight: .semibold).monospacedDigit())
                .lineLimit(1)

            Text(presentation.title)
                .font(.system(size: metrics.titleSize, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: metrics.controlSpacing) {
            ForEach(presentation.controls) { control in
                Button {
                    perform(control)
                } label: {
                    Image(systemName: control.symbolName)
                        .font(.system(size: metrics.controlSymbolSize, weight: .medium))
                        .frame(width: metrics.controlButtonSize, height: metrics.controlButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(control.accessibilityLabel)
            }
        }
    }
}
