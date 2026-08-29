# Glossary and Conventions

This document fixes the vocabulary the codebase and the rest of `docs/` share, the naming rules that keep NotchFlow out of trademark trouble, and the code, git, and documentation conventions every todo in this plan follows. It is a design specification — nothing in this folder is code.

## Glossary

| Term | Meaning |
|---|---|
| Island | The overlay window NotchFlow draws around and over the notch. The user-facing name for the whole feature. |
| Notch | The physical camera housing cut into the top of a built-in display, detected via `NSScreen.safeAreaInsets.top`. |
| Compact state | The island's default, minimal footprint: it hugs the notch rectangle and shows only what fits without expanding. |
| Expanded state | The island's enlarged footprint, shown on hover or interaction, revealing full activity detail and controls. |
| Activity | A single unit of live information a provider publishes: now-playing, a timer, a recording indicator, charging state, or an AI agent's status. Modeled by the `Activity` protocol in `NotchFlowCore`. |
| Provider | A `NotchFlowProviders` type that watches one system or IPC source and translates its events into `Activity` updates. One provider per activity source. |
| Agent | An AI coding agent (Claude Code, Codex, OpenCode) whose state NotchFlow surfaces via the IPC protocol. Not to be confused with the app itself. |
| Session | One running instance of an agent, identified by the session id in the IPC message envelope. |
| Slot | A fixed position in the compact or expanded layout that an activity occupies. |
| Overflow | The state where more activities are active than the current layout has slots for, requiring priority-based selection or a secondary indicator. |

## Naming rules

NotchFlow is the product name everywhere: in code, in commit messages, in the App Store listing, and in prose. Apple's "Dynamic Island" and "MacBook" are trademarks and must not appear in the product name, the bundle identifier, or any App Store metadata field.

In prose, refer to the concept generically, for example "the notch on modern MacBook models" when describing the hardware, or "a Dynamic-Island-style live activity surface" only in an explanatory, comparative sentence aimed at readers who already know the iPhone feature, never as part of NotchFlow's own name or marketing copy. When in doubt, prefer "the island" or "the notch," both defined above.

## Code conventions

NotchFlow follows the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) throughout. `swiftlint` and `swift-format` run at build time with the project's checked-in configuration as the single source of truth for style; a PR that fails either is not mergeable.

- **One type per file.** The file name matches the type name exactly (`ActivityManager.swift` defines `ActivityManager` and nothing else at top level).
- **File length.** A file that grows past roughly 400 lines is a signal to split it along a natural seam (extension, sub-type, or protocol conformance), not a hint to write smaller comments.
- **Access control.** `internal` is the default for every declaration. `public` is reserved for the boundary between `NotchFlowCore`, `NotchFlowProviders`, and `NotchFlowUI` as described in `01-architecture.md`; nothing inside the app target needs to be `public`.
- **Comments explain why, never what or when.** A comment restating the next line in English is deleted, not fixed. No change-tracking comments (`// added`, `// changed 2024-01-01`, `// TODO(name): remove after v2`) — that history belongs in git, not in source.
- **Swift 6 concurrency.** The codebase builds under strict concurrency checking. System callbacks that arrive off the main actor (delegate methods, completion handlers from `MediaRemote`, `ScreenCaptureKit`, IOKit notifications, and the IPC listener) follow one standard pattern to hop onto `@MainActor`:

  ```swift
  nonisolated func systemCallback(_ payload: Payload) {
      Task { @MainActor in
          self.handle(payload)
      }
  }
  ```

  UI-facing state lives on `@MainActor` types; provider internals that don't touch UI may stay off it, but the boundary crossing always goes through an explicit `Task { @MainActor in ... }` hop, never an implicit assumption about which thread a callback fires on.

## Git conventions

Every commit follows [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`, imperative mood, lowercase, no trailing period, subject under 72 characters.

| Type | Use for |
|---|---|
| `feat` | A new user-visible capability |
| `fix` | A bug fix |
| `docs` | Documentation-only changes, including everything in `docs/` |
| `refactor` | Internal restructuring with no behavior change |
| `test` | Adding or adjusting tests without touching production code |
| `perf` | A change made specifically to hit or protect a performance-contract number |
| `chore` | Tooling, config, dependency, or repo-maintenance changes |

Scope is the module or doc area affected: `core`, `providers`, `ui`, `ipc`, `architecture`, `performance`, `conventions`, and so on, matching the vocabulary already in use across this plan's commit messages (`docs(architecture): ...`, `docs(performance): ...`).

Branches are named `type/short-description` (for example `feat/media-provider`, `fix/notch-rect-external-display`), mirroring the commit type of the primary change the branch carries.

Every pull request is checked against:

- [ ] The change matches its stated scope; unrelated files are not swept in.
- [ ] `swiftlint` and `swift-format` pass with no suppressions added.
- [ ] Any relevant performance-contract row from `02-performance-contract.md` still holds.
- [ ] A doc under `docs/` is updated in the same PR if the change contradicts it.
- [ ] Tests cover the new behavior or the fixed bug.

## Documentation conventions

A new document goes in `docs/`, numbered after the last existing document, and is added to the index in `00-product-overview.md` (or the top-level `docs/README.md` if one exists) in the same commit that adds it. A code change that contradicts an existing document updates that document in the same commit as the code change — the two are never allowed to disagree, even temporarily.
