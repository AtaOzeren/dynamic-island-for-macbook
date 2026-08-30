import Foundation

/// The manual-setup fallback's content: the file to edit, and the exact text the
/// installer would have written into it.
///
/// `docs/07-ai-integration.md` promises that a user who declines — or cannot be
/// granted — write access still gets "the exact snippet in a copyable text
/// view". "Exact" is the whole contract, so this type has no way to produce a
/// snippet of its own: `snippet` is supplied by the installer that owns the
/// generator, and the steps around it are the only thing assembled here.
public struct ManualSetupInstructions: Equatable, Sendable {
    public let agent: IPCAgentID
    /// The absolute path of the file the user has to create or edit.
    public let destinationPath: String
    /// Byte-for-byte what the installer's write would have put on disk.
    public let snippet: String

    public init(agent: IPCAgentID, destinationPath: String, snippet: String) {
        self.agent = agent
        self.destinationPath = destinationPath
        self.snippet = snippet
    }

    public var title: String {
        localized("Set up \(agent.displayName) by hand")
    }

    /// Why the user is reading this at all: the app could not write the file, so
    /// the work is theirs. Kept separate from `steps` so the view can give it
    /// the quieter treatment a subtitle gets.
    public var summary: String {
        localized("""
            NotchFlow could not write this file for you. \
            Copy the text below into \(destinationPath) to finish setup.
            """)
    }

    /// The instructions, in the order they are performed. The snippet itself is
    /// not among them — it is drawn in its own copyable block — so a step never
    /// paraphrases the text the user has to reproduce exactly.
    public var steps: [String] {
        [
            localized("Open \(destinationPath) in your editor, creating it if it does not exist."),
            replacementStep,
            localized("Save the file, then restart \(agent.displayName) so it picks up the change.")
        ]
    }

    /// The one step that differs per agent, because the three files differ in
    /// what "add the snippet" means: two are whole-file replacements the
    /// installer had already merged, and one is a new file of its own.
    private var replacementStep: String {
        switch agent {
        case .claudeCode, .codex:
            localized("""
                Replace the file's entire contents with the text below — \
                NotchFlow has already merged your existing settings into it.
                """)
        case .opencode:
            localized("Paste the text below as the file's entire contents.")
        }
    }
}
