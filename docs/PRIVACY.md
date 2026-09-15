# KerNotch Privacy Policy

**Effective date:** 2026-08-30

KerNotch is a macOS app that turns the notch on your MacBook into a live-activity surface. This policy describes what data KerNotch does and does not handle.

---

## What KerNotch does not collect

KerNotch collects nothing. There is no analytics SDK, no crash reporter that phones home, no telemetry, and no account system. KerNotch never transmits any information about you or your device to any server.

Specifically, KerNotch does not collect, store, or transmit:

- Your identity or any personally identifiable information
- Device identifiers, hardware serials, or IP addresses
- Usage statistics, session lengths, or feature interaction data
- The content of your music playback, timers, or AI agent sessions
- Crash reports or diagnostic data sent off-device
- Any information about other apps running on your Mac

---

## Network activity

The only network socket KerNotch ever opens is a loopback HTTP listener bound to `127.0.0.1`. This listener receives status events from AI coding agents (Claude Code, Codex CLI, OpenCode) running on the same machine. It is unreachable from outside your Mac. No data sent to this listener leaves your device.

KerNotch does not make any outbound network connections of its own. Update checks are handled entirely by the Mac App Store or Homebrew, not by KerNotch.

---

## Permissions KerNotch requests

The App Store build requests Apple Events permission lazily, only when you turn on the music feature. The Direct build uses MediaRemote and does not request Apple Events permission. Nothing is requested at first launch.

| Permission | Why it's needed | When it's requested |
|---|---|---|
| Apple Events (App Store build only) | To query and control Spotify and Apple Music for the music activity card | The first time you play a track from a supported app after enabling the music provider |

KerNotch does not request and has no code path that would need: Camera, Microphone, Screen Recording, Accessibility, Full Disk Access, Contacts, or Location.

The screen-recording and microphone-recording indicators in KerNotch observe that a recording is in progress through a public system notification, the same mechanism used for charging state. They never enable recording, never capture what is being recorded, and never require Screen Recording or Microphone permission.

---

## What stays on your device

Everything KerNotch knows stays on your Mac:

- **Settings** are stored in `UserDefaults` in the app's sandbox container.
- **No persistent data** is written outside the sandbox container.

---

## Third-party services

KerNotch has no third-party SDKs, no advertising networks, and no analytics services. It does not integrate with any external service on your behalf.

---

## Children

KerNotch does not knowingly collect any information from anyone, including children.

---

## Changes to this policy

If this policy changes in a future release, the updated version will be included in the release and the effective date above will be updated. Because KerNotch collects nothing, any change would only ever narrow or clarify what is written here, not expand data collection.

---

## Contact

KerNotch is an open-source project. Questions about this policy can be raised as a GitHub issue in the project repository.
