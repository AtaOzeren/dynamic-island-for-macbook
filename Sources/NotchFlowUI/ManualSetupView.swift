import AppKit
import CoreGraphics
import NotchFlowCore
import SwiftUI

/// The seam between the copy button and the system pasteboard: a test can
/// assert that the button copies the snippet *exactly* without writing to the
/// user's real clipboard.
public protocol SnippetPasteboardWriting: Sendable {
    func write(_ snippet: String)
}

/// Writes to the general pasteboard, clearing it first so the snippet is the
/// only thing a paste can produce.
public struct SystemSnippetPasteboard: SnippetPasteboardWriting {
    public init() {}

    public func write(_ snippet: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet, forType: .string)
    }
}

/// The manual-setup sheet's fixed visual budget, the counterpart to
/// `AIAgentViewMetrics` — one edit changes the sheet's density.
public struct ManualSetupMetrics: Equatable, Sendable {
    public static let `default` = ManualSetupMetrics()

    public let contentInset: CGFloat
    public let sectionSpacing: CGFloat
    public let stepSpacing: CGFloat
    public let titleSize: CGFloat
    public let bodySize: CGFloat
    public let snippetSize: CGFloat
    public let snippetCornerRadius: CGFloat
    public let snippetMaximumHeight: CGFloat
    public let width: CGFloat

    public init(
        contentInset: CGFloat = 20,
        sectionSpacing: CGFloat = 16,
        stepSpacing: CGFloat = 8,
        titleSize: CGFloat = 15,
        bodySize: CGFloat = 12,
        snippetSize: CGFloat = 11,
        snippetCornerRadius: CGFloat = 8,
        snippetMaximumHeight: CGFloat = 260,
        width: CGFloat = 440
    ) {
        self.contentInset = contentInset
        self.sectionSpacing = sectionSpacing
        self.stepSpacing = stepSpacing
        self.titleSize = titleSize
        self.bodySize = bodySize
        self.snippetSize = snippetSize
        self.snippetCornerRadius = snippetCornerRadius
        self.snippetMaximumHeight = snippetMaximumHeight
        self.width = width
    }
}

/// The fallback shown when automatic installation is unavailable or declined:
/// the numbered steps, the snippet, and a button that copies it.
///
/// The view never generates a snippet. It renders the `ManualSetupInstructions`
/// its installer handed it, so what the user copies is the same string the
/// installer would have written — the acceptance criterion this screen exists
/// to satisfy.
public struct ManualSetupView: View {
    private let instructions: ManualSetupInstructions
    private let metrics: ManualSetupMetrics
    private let pasteboard: any SnippetPasteboardWriting

    @State private var didCopy = false

    public init(
        instructions: ManualSetupInstructions,
        metrics: ManualSetupMetrics = .default,
        pasteboard: any SnippetPasteboardWriting = SystemSnippetPasteboard()
    ) {
        self.instructions = instructions
        self.metrics = metrics
        self.pasteboard = pasteboard
    }

    /// Copies the snippet. Exposed so a test can drive the same path the button
    /// takes without rendering into a window server.
    public func copySnippet() {
        pasteboard.write(instructions.snippet)
    }

    /// What the copy button says, which doubles as the confirmation that the
    /// copy happened — the sheet has no other place to report it.
    public var copyButtonTitle: String {
        didCopy ? localized("Copied") : localized("Copy snippet")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            heading
            steps
            snippet
            copyButton
        }
        .padding(metrics.contentInset)
        .frame(width: metrics.width, alignment: .leading)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: metrics.stepSpacing / 2) {
            Text(instructions.title)
                .font(.system(size: metrics.titleSize, weight: .semibold))
            Text(instructions.summary)
                .font(.system(size: metrics.bodySize))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: metrics.stepSpacing) {
            ForEach(Array(instructions.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: metrics.stepSpacing) {
                    Text(localized("manualSetup.stepNumber", default: "\(index + 1)."))
                        .font(.system(size: metrics.bodySize, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(step)
                        .font(.system(size: metrics.bodySize))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The snippet is selectable as well as copyable: a user who wants only the
    /// one line their file is missing should not have to take all of it.
    private var snippet: some View {
        ScrollView {
            Text(instructions.snippet)
                .font(.system(size: metrics.snippetSize, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(metrics.stepSpacing)
        }
        .frame(maxHeight: metrics.snippetMaximumHeight)
        .background {
            RoundedRectangle(cornerRadius: metrics.snippetCornerRadius, style: .continuous)
                .fill(.quaternary)
        }
        .accessibilityLabel(localized("Setup snippet for \(instructions.agent.displayName)"))
    }

    private var copyButton: some View {
        Button {
            copySnippet()
            didCopy = true
        } label: {
            Label(copyButtonTitle, systemImage: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: metrics.bodySize))
        }
        .accessibilityLabel(copyButtonTitle)
    }
}
