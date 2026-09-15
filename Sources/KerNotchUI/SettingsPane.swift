import CoreGraphics
import SwiftUI

/// The settings window's fixed visual budget, shared by every pane so the tabs
/// do not drift apart in density — one edit changes all four.
///
/// This started as the AI Integrations pane's private metrics. It is shared
/// rather than copied because a settings window whose tabs disagree about
/// inset, type scale, or width visibly jumps as the user switches between them.
public struct SettingsPaneMetrics: Equatable, Sendable {
    public static let `default` = SettingsPaneMetrics()

    public let contentInset: CGFloat
    public let sectionSpacing: CGFloat
    public let rowSpacing: CGFloat
    public let titleSize: CGFloat
    public let bodySize: CGFloat
    public let footnoteSize: CGFloat
    public let width: CGFloat

    public init(
        contentInset: CGFloat = 20,
        sectionSpacing: CGFloat = 16,
        rowSpacing: CGFloat = 8,
        titleSize: CGFloat = 15,
        bodySize: CGFloat = 12,
        footnoteSize: CGFloat = 11,
        width: CGFloat = 440
    ) {
        self.contentInset = contentInset
        self.sectionSpacing = sectionSpacing
        self.rowSpacing = rowSpacing
        self.titleSize = titleSize
        self.bodySize = bodySize
        self.footnoteSize = footnoteSize
        self.width = width
    }
}

/// A titled, captioned group of controls — the one section shape every pane in
/// the settings window uses.
public struct SettingsSection<Rows: View>: View {
    private let title: String
    private let caption: String
    private let metrics: SettingsPaneMetrics
    private let rows: Rows

    public init(
        title: String,
        caption: String,
        metrics: SettingsPaneMetrics = .default,
        @ViewBuilder rows: () -> Rows
    ) {
        self.title = title
        self.caption = caption
        self.metrics = metrics
        self.rows = rows()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            Text(title)
                .font(.system(size: metrics.titleSize, weight: .semibold))
            Text(caption)
                .font(.system(size: metrics.footnoteSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            rows
                .font(.system(size: metrics.bodySize))
                .toggleStyle(.switch)
        }
    }
}

extension View {
    /// The frame every pane sits in, so a tab switch never resizes the window.
    func settingsPaneFrame(_ metrics: SettingsPaneMetrics) -> some View {
        padding(metrics.contentInset)
            .frame(width: metrics.width, alignment: .leading)
    }
}
