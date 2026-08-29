# Security, Privacy, and Permissions

This document specifies NotchFlow's privacy stance, the entitlements each build configuration declares and why, the permission request flow, the threat model for the loopback IPC listener, and the hook installer's trust model. It is a design specification — nothing in this folder is code.

## Privacy stance

NotchFlow collects nothing, sends nothing off-device, and has no analytics. There is no telemetry SDK, no crash reporter that phones home, and no update-check ping beyond what the App Store or Homebrew Cask does on its own. The only network socket NotchFlow ever opens is the loopback HTTP listener described in `07-ai-integration.md`, and that socket is unreachable from outside the local machine. NotchFlow never reads the screen, never records audio or video itself, and never inspects another app's windows or file contents beyond the narrow, named cases below.

## Entitlements

Each entitlement below is requested only where the corresponding feature needs it, and only in the build configuration that needs it.

| Entitlement | App Store build | Direct build | Justification | User-visible consequence |
|---|---|---|---|---|
| App Sandbox | On | On where possible; hardened runtime is the primary constraint (see `10-build-and-distribution.md`) | Required for App Store distribution; kept on for the Direct build as defense in depth wherever a private-framework dependency doesn't force it off | The app cannot touch files or processes outside its container without one of the entitlements below |
| `com.apple.security.automation.apple-events` (with `NSAppleEventsUsageDescription`) | On | On | Needed for the AppleScript music provider to query and control Spotify and Apple Music, the only music integration path available inside the sandbox | First control of a supported music app triggers one system Apple Events permission prompt per target app |
| `com.apple.security.network.server` | On | Not needed | The loopback HTTP listener for AI agent IPC needs this entitlement to bind a socket at all inside the sandbox | No visible prompt; the entitlement is declared at build time, not requested at runtime |
| User-selected file access (`com.apple.security.files.user-selected.read-write`) | On | Not needed (unsandboxed Direct build writes directly) | The hook installer needs write access to files like `~/.claude/settings.json` that live outside the sandbox container | An `NSOpenPanel` scoped to the target file appears the first time the user approves a hook installation; a security-scoped bookmark is stored so NotchFlow can write again later (for example, to uninstall) without asking twice |

### Not requested

NotchFlow does not request, and has no code path that would need, any of the following:

- Camera
- Microphone recording
- Screen recording
- Accessibility
- Full Disk Access
- Contacts
- Location

The screen and audio recording indicators (see `00-product-overview.md` and `06-activity-providers.md`) observe that a recording is in progress through the same category of public, no-permission system notification NotchFlow uses for charging state — they never enable recording, never capture what is being recorded, and never require Screen Recording or Microphone permission themselves.

## Permission request flow

Nothing is requested at launch. NotchFlow's first run shows the notch UI with zero activities and asks for nothing. Each permission in the table above is requested lazily, at the exact moment the user turns on the specific feature that needs it:

1. The user enables the feature (for example, adds a Claude Code hook, or plays a track from a supported music app for the first time).
2. NotchFlow shows a plain-language explanation of what is about to be requested and why, in its own UI, before the system prompt appears.
3. The system permission prompt (Apple Events, or the file picker for the hook installer) is shown.
4. If the user denies or cancels, the feature that needed the permission is disabled and NotchFlow says so in place, in that feature's settings row — it does not nag, re-prompt on a timer, or block unrelated features.

Every feature degrades gracefully when its permission is denied. A denied Apple Events prompt for one music app disables control of that app only; the rest of NotchFlow, including any other music app, timers, recording indicators, charging state, and AI status, keeps working normally.

### Purpose strings

The `NSAppleEventsUsageDescription` shown in the system prompt, verbatim:

- **English:** "NotchFlow uses Apple Events to show now-playing info and let you control playback for Spotify and Apple Music from the notch."
- **Turkish:** "NotchFlow, çentikten şu an çalan şarkı bilgisini göstermek ve Spotify ile Apple Music'i kontrol edebilmek için Apple Events kullanır."

## Threat model

The loopback HTTP listener (see `07-ai-integration.md`) is NotchFlow's only inbound network surface. It is bound to `127.0.0.1`, so the only thing that can reach it is another process running as the same local user, on the same machine.

**What a malicious local process could attempt:**

- Send a well-formed IPC envelope with a spoofed `agentId` to make an unrelated activity appear in the notch.
- Flood the listener with requests to keep an activity visible or to consume CPU.
- Send an oversized or malformed payload to try to crash the listener or corrupt state.
- Send a payload containing shell metacharacters or script content, hoping it gets executed or interpolated somewhere.

**Mitigations, one per threat above:**

- Every envelope is validated against the JSON schema in `07-ai-integration.md` before it reaches `ActivityManager`; a message whose `agentId` is not one NotchFlow recognizes, or one the user has not explicitly enabled in AI Integrations settings, is ignored and never surfaces as an activity.
- The listener rate-limits per `sessionId`.
- Oversized payloads are rejected outright, both by the schema's `maxLength` bound on `detail` and by a hard cap on total request body size at the HTTP layer.
- No field of any IPC payload is ever passed to a shell, `NSAppleScript`, `Process`, or any other command-execution API. Every field is treated as inert display text; `detail` and `toolName` are rendered as plain strings in SwiftUI `Text` views, never interpolated into a command line or evaluated.

## Hook installer trust model

The hook installer (see `07-ai-integration.md`) modifies configuration files belonging to other tools — for example `~/.claude/settings.json` or `~/.codex/config.toml`. It only does so under this contract:

- **Explicit consent for every write.** NotchFlow never edits a config file silently. Each installation and each uninstallation is a separate, user-initiated action with its own confirmation.
- **Exact diff shown first.** Before writing, NotchFlow shows the precise snippet it will add or remove, in the same format the target file uses, so the user can read exactly what changes before approving.
- **Backup before write.** NotchFlow copies the original file alongside itself (for example, `settings.json.notchflow-backup`) before making any change.
- **One-click uninstall.** Removing the integration restores the file to its pre-installation state using the backup, and removes only the snippet NotchFlow added — it never rewrites the rest of the user's configuration.
- **Manual fallback.** If the user declines to grant NotchFlow write access (relevant in the sandboxed build, see the sandbox note in `07-ai-integration.md`), NotchFlow still shows the exact snippet in a copyable text view so the user can add it by hand.

## Data at rest

NotchFlow persists only user preferences (see `08-settings-and-localization.md`): which providers are enabled, which AI agents are enabled, window and display choices, and language selection. It keeps no history of past activities and no log of AI agent content — once an `AIActivity` reaches `completed` or `error` and is dismissed, nothing about its detail text or tool names is retained anywhere on disk.

## Privacy policy source of truth

This document is the source of truth for NotchFlow's privacy policy text. The App Store Connect privacy policy and in-app "Privacy" settings page both reuse the **Privacy stance**, **Entitlements**, and **Data at rest** sections above verbatim rather than maintaining a separate description; if this document changes, the App Store Connect listing and in-app text are updated in the same commit.
