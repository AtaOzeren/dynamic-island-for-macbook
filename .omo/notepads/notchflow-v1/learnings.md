# Learnings — notchflow-v1

Conventions, patterns, and successful approaches discovered during work on this plan.

_Auto-scaffolded by /start-work. Append new entries below - never overwrite._

---

## [2026-08-30] Task: todo-44
The music backend is selected by `makeMusicProvider()` in `NotchFlow/MusicBackend.swift` — one `#if DIRECT_BUILD` in the app target, per the todo-43 constraint that Xcode compilation conditions never reach SPM targets. `Debug`/`Release` define neither condition and fall through to `AppleScriptMusicProvider`: the private-framework path is opt-in only. `NotchFlow --print-music-backend` prints `backendName` and exits, which is how `scripts/check-music-backend.sh` asserts the two configurations differ in CI without a window server.

## [2026-08-30] Task: todo-50
Custom URL delivery belongs in the app target via SwiftUI `.onOpenURL`; the reusable parser stays in NotchFlowCore and delegates all envelope validation to `IPCMessageValidator`. An explicit Info.plist is needed to register `notchflow` while preserving LSUIElement and Apple Events metadata in every Xcode configuration.

## [2026-08-30] Task: todo-51
The HTTP fallback uses `NWParameters.requiredLocalEndpoint` with `127.0.0.1:0`, then publishes `NWListener.port` only after the listener reaches `.ready`. Enablement is an injected set of agent IDs: an empty set cancels the listener, closes active connections, and removes the discovery file without consulting UserDefaults. Request bodies flow through the shared `IPCMessageValidator`, while the core policy owns route, enabled-agent, size, and per-session interval gates. Xcode target configurations must explicitly set `CODE_SIGN_ENTITLEMENTS`; only the sandboxed AppStore plist carries `com.apple.security.network.server`.

## [2026-08-30] Task: todo-54
Claude Code installation belongs in `~/.claude/settings.json`: merge the exact `HookSnippetGenerator` object into only the matching hook event, retain a byte-for-byte backup of a pre-existing file, and restore that backup on uninstall. Fresh installs need no backup and uninstall by removing the generated-only file. The installer exposes the complete proposal separately so UI consent remains the caller's responsibility, validates strict JSON before every settings overwrite, uses atomic writes, and injects all filesystem operations for hermetic tests.

## [2026-08-30] Task: todo-53
Agent detection is a one-shot query over the documented configuration paths: `~/.claude/settings.json`, `~/.codex/config.toml`, and `~/.config/opencode/plugin`. The probe uses throwing filesystem metadata lookup rather than `fileExists`, preserving the distinction between a missing path (`notInstalled`) and sandbox-denied inspection (`unknown`, so the UI can offer manual setup). A closure seam keeps all three outcomes hermetic in tests, while deriving the result from `IPCAgentID.allCases` guarantees a complete V1 mapping.

## [2026-08-30] Task: todo-55
Codex installation targets the root `notify` assignment in `~/.codex/config.toml`. Targeted text replacement preserves comments, ordering, and unrelated table values; new root settings must be inserted before the first table header because TOML keys after a header belong to that table. The installer validates existing and merged text through an injectable syntax seam, retains the original bytes in a one-time atomic backup, and removes only its generated assignment when uninstalling a fresh config that gained unrelated settings later.
