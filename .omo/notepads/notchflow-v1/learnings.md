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

## [2026-08-30] Task: todo-68
Ad-hoc Xcode signing injects `com.apple.security.get-task-allow` unless `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`; disabling that injection makes `codesign -d --entitlements - --xml` a reliable exact-set check for local packaging QA. Scheme build post-actions can run a channel-only guard with the built target's environment, so the App Store symbol check stays out of Direct builds.

## [2026-08-30] Task: todo-56
OpenCode discovers user plugins by file-tree convention, so installation is a drop at `~/.config/opencode/plugins/notchflow.ts`, not a settings merge. Keep generation centralized in `HookSnippetGenerator`, back up only a pre-existing destination file, restore it byte-for-byte on uninstall, and prune parent directories only when empty so unrelated plugins and user configuration survive.

## [2026-08-30] Task: todo-53
Agent detection is a one-shot query over the documented configuration paths: `~/.claude/settings.json`, `~/.codex/config.toml`, and `~/.config/opencode/plugin`. The probe uses throwing filesystem metadata lookup rather than `fileExists`, preserving the distinction between a missing path (`notInstalled`) and sandbox-denied inspection (`unknown`, so the UI can offer manual setup). A closure seam keeps all three outcomes hermetic in tests, while deriving the result from `IPCAgentID.allCases` guarantees a complete V1 mapping.

## [2026-08-30] Task: todo-55
Codex installation targets the root `notify` assignment in `~/.codex/config.toml`. Targeted text replacement preserves comments, ordering, and unrelated table values; new root settings must be inserted before the first table header because TOML keys after a header belong to that table. The installer validates existing and merged text through an injectable syntax seam, retains the original bytes in a one-time atomic backup, and removes only its generated assignment when uninstalling a fresh config that gained unrelated settings later.

## [2026-08-30] Task: todo-57
The manual-setup fallback holds no generator of its own: `ManualSetupInstructions` (Core) takes the snippet as an init parameter, and each installer's `manualSetupInstructions()` fills it from the same `proposedSettings()`/`proposedConfiguration()`/`proposedPlugin()` call `install()` writes from. That makes "the snippet is identical to what the installer would have written" a structural property rather than a test-enforced coincidence; the tests still assert it by installing into an in-memory file system and comparing against the bytes on disk. The copy path takes a `SnippetPasteboardWriting` seam (mirroring `ReduceTransparencyQuerying`) so a test can assert byte-for-byte copying without touching the real clipboard.

## [2026-08-30] Task: todo-59
Settings defaults are registered once from `SettingsKeys.registeredDefaults`; optional nil defaults remain absent because `UserDefaults.register(defaults:)` cannot represent nil. `SettingsKey<Value>` owns each name, default, and codec, while `SettingsStore` owns the storage and typed observation boundary. AI preferences and provider identifiers are derived from their existing enums, so the app composition root can load persisted state and react to provider changes without either receiver or provider calling `UserDefaults` directly.

## [2026-08-30] Task: todo-73
The pre-membership release path builds `NotchFlow (Direct)` with `CODE_SIGNING_ALLOWED=NO`, verifies the expected MediaRemote linkage, and packages the resulting `.app` with `ditto --keepParent`. Signing and notarization belong immediately before packaging so todo 70 can replace the unsigned seam without changing artifact names, checksum generation, or GitHub Release publication. `scripts/check-forbidden-symbols.sh` defaults to its existing App Store absence assertion and accepts `--present` only for Direct release validation.
