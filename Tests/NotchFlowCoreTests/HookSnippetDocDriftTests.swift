import Foundation
import Testing

@testable import NotchFlowCore

@Suite("HookSnippetDocDrift")
struct HookSnippetDocDriftTests {
    private static let markerPrefix = "<!-- notchflow-snippet: "

    private static let integrationDocURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/07-ai-integration.md")

    @Test("doc examples are byte-identical to HookSnippetGenerator output")
    func docExamplesMatchGeneratorOutput() throws {
        let doc = try String(contentsOf: Self.integrationDocURL, encoding: .utf8)
        let generator = HookSnippetGenerator()

        let claudeCode = try Self.fencedSnippet(afterMarker: "claude-code", in: doc)
        #expect(
            claudeCode + "\n" == generator.claudeCodeSettingsFragment(),
            "docs/07-ai-integration.md claude-code block drifted from HookSnippetGenerator"
        )

        let codex = try Self.fencedSnippet(afterMarker: "codex", in: doc)
        #expect(
            codex + "\n" == generator.codexNotifyFragment(),
            "docs/07-ai-integration.md codex block drifted from HookSnippetGenerator"
        )

        let openCode = try Self.fencedSnippet(afterMarker: "opencode", in: doc)
        #expect(
            openCode + "\n" == generator.openCodePluginFile(),
            "docs/07-ai-integration.md opencode block drifted from HookSnippetGenerator"
        )
    }

    @Test("every generator snippet is documented")
    func everyGeneratorSnippetIsDocumented() throws {
        let doc = try String(contentsOf: Self.integrationDocURL, encoding: .utf8)
        for marker in ["claude-code", "codex", "opencode"] {
            #expect(
                doc.contains("\(Self.markerPrefix)\(marker) -->"),
                "docs/07-ai-integration.md lost its \(marker) snippet marker"
            )
        }
    }

    private static func fencedSnippet(afterMarker marker: String, in doc: String) throws -> Substring {
        let markerLine = "\(markerPrefix)\(marker) -->"
        let afterMarker = try #require(
            doc.range(of: markerLine)?.upperBound,
            "docs/07-ai-integration.md lost its \(marker) snippet marker"
        )
        let openFence = try #require(
            doc.range(of: "\n```", range: afterMarker..<doc.endIndex),
            "no fenced code block after the \(marker) marker"
        )
        let contentStart = try #require(
            doc.range(of: "\n", range: openFence.upperBound..<doc.endIndex)?.upperBound,
            "the \(marker) fence line is unterminated"
        )
        let closeFence = try #require(
            doc.range(of: "\n```", range: contentStart..<doc.endIndex)?.lowerBound,
            "the \(marker) code block is never closed"
        )
        return doc[contentStart..<closeFence]
    }
}
