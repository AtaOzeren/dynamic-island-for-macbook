import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// The UI half of todo 57's acceptance criterion: what the copy button puts on
/// the pasteboard is the snippet it was given, unaltered — no trimming, no
/// re-wrapping, no added fences.
@Suite("ManualSetupView")
@MainActor
struct ManualSetupViewTests {
    private static let snippet = """
        {
          "hooks" : {
            "PreToolUse" : [ ]
          }
        }

        """

    private static func instructions(
        agent: IPCAgentID = .claudeCode,
        destinationPath: String = "/Users/tester/.claude/settings.json",
        snippet: String = ManualSetupViewTests.snippet
    ) -> ManualSetupInstructions {
        ManualSetupInstructions(
            agent: agent,
            destinationPath: destinationPath,
            snippet: snippet
        )
    }

    @Test("copies the snippet byte for byte")
    func copiesSnippetExactly() {
        let pasteboard = RecordingPasteboard()
        let view = ManualSetupView(
            instructions: Self.instructions(),
            pasteboard: pasteboard
        )

        view.copySnippet()

        #expect(pasteboard.written == [Self.snippet])
    }

    /// Trailing newlines are the easy thing for a view to eat, and both the JSON
    /// and TOML snippets end in one that the file needs.
    @Test("keeps the snippet's trailing newline")
    func preservesTrailingNewline() {
        let pasteboard = RecordingPasteboard()
        let view = ManualSetupView(
            instructions: Self.instructions(snippet: "notify = []\n"),
            pasteboard: pasteboard
        )

        view.copySnippet()

        #expect(pasteboard.written.first?.hasSuffix("\n") == true)
    }

    @Test("copies afresh on every press")
    func copiesOnEveryPress() {
        let pasteboard = RecordingPasteboard()
        let view = ManualSetupView(
            instructions: Self.instructions(),
            pasteboard: pasteboard
        )

        view.copySnippet()
        view.copySnippet()

        #expect(pasteboard.written == [Self.snippet, Self.snippet])
    }

    @Test("labels the copy button before it has been pressed")
    func copyButtonTitle() {
        let view = ManualSetupView(
            instructions: Self.instructions(),
            pasteboard: RecordingPasteboard()
        )

        #expect(view.copyButtonTitle == "Copy snippet")
    }

    @Test("names the agent in the title for each agent")
    func titlesNameTheirAgent() {
        let titles = IPCAgentID.allCases.map { Self.instructions(agent: $0).title }

        #expect(Set(titles).count == IPCAgentID.allCases.count)
        #expect(titles.contains("Set up Claude by hand"))
    }
}

private final class RecordingPasteboard: SnippetPasteboardWriting, @unchecked Sendable {
    private(set) var written: [String] = []

    func write(_ snippet: String) {
        written.append(snippet)
    }
}
