# Decisions — notchflow-v1

Architectural choices and rationales discovered during work on this plan.

_Auto-scaffolded by /start-work. Append new entries below - never overwrite._

---

## [2026-08-30] Task: todo-68
The Direct build remains unsandboxed. `docs/09-security-privacy-permissions.md:15,18` and `docs/10-build-and-distribution.md:9-13` make the sandbox conditional for Direct, while that channel must use MediaRemote and read optional agent session logs outside an app container. Hardened runtime is therefore the Direct distribution boundary; no `com.apple.security.app-sandbox` key is emitted. Both channel configurations set `ENABLE_HARDENED_RUNTIME = YES`, use their documented entitlement file, and omit team, profile, and release-certificate settings until the membership-gated release work in todos 70-72. `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` keeps local ad-hoc verification limited to the documented entitlement sets.
