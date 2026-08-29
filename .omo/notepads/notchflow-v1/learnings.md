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
