# Decisions — notchflow-v1

Architectural choices and rationales discovered during work on this plan.

_Auto-scaffolded by /start-work. Append new entries below - never overwrite._

---

## [2026-08-30] Task: todo-68
The Direct build remains unsandboxed. `docs/09-security-privacy-permissions.md:15,18` and `docs/10-build-and-distribution.md:9-13` make the sandbox conditional for Direct, while that channel must use MediaRemote and read optional agent session logs outside an app container. Hardened runtime is therefore the Direct distribution boundary; no `com.apple.security.app-sandbox` key is emitted. Both channel configurations set `ENABLE_HARDENED_RUNTIME = YES`, use their documented entitlement file, and omit team, profile, and release-certificate settings until the membership-gated release work in todos 70-72. `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` keeps local ad-hoc verification limited to the documented entitlement sets.

## [2026-08-30] Task: F9 finding 1
Remove `com.apple.security.files.user-selected.read-write` from the App Store entitlement set. A repository-wide search found no `NSOpenPanel`, security-scoped bookmark, or `startAccessingSecurityScopedResource` code path, so the documented hook-installer consent flow does not exist in the App Store build. Keeping the entitlement would grant unused file access and misrepresent the shipped behavior.

## [2026-08-30] Task: F9 finding 2
Remove `com.apple.security.automation.apple-events` from the Direct entitlement set. `DIRECT_BUILD` selects `MediaRemoteMusicProvider`, so Direct never instantiates `AppleScriptMusicProvider`; moreover, Direct is unsandboxed and would not need the sandbox automation entitlement even if it sent Apple Events. Apple Events permission and its entitlement therefore remain App Store-only.

## [2026-08-30] Task: F9 finding 3
Treat the purpose sentence documented in `docs/09-security-privacy-permissions.md` as canonical. The base Info.plist and English `InfoPlist.strings` use that sentence verbatim; the Turkish localization uses the Turkish sentence documented alongside it. Both localized resources belong to the app target through one `PBXVariantGroup`.
