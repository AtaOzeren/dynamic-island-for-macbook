# KerNotch Privacy Policy

**Effective date:** 2026-09-16

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
- Any information about other apps running on your Mac, beyond whether Discord is using the microphone when you turn on the Discord integration — a fact that is read on your Mac and never leaves it

---

## Network activity

The only listening network socket KerNotch ever opens is a loopback HTTP listener bound to `127.0.0.1`. This listener receives status events from AI coding agents (Claude Code, Codex CLI, OpenCode) running on the same machine. It is unreachable from outside your Mac. No data sent to this listener leaves your device.

KerNotch makes only two kinds of outbound connection. On macOS 15.4 and later, it downloads the album artwork Spotify reports for its current track, from the web address the Spotify app supplies; KerNotch adds no information about you to that request. And if you connect the Discord integration, it talks to the Discord app on your Mac through Discord's local socket to read your voice channel and mute state, and contacts `discord.com` only to obtain or renew the authorization you approved. The connection goes through KerNotch's own Discord application, which Discord shows by name when it asks you to approve it; KerNotch sends nothing else to Discord. KerNotch does not check for updates; if you installed it with Homebrew, Homebrew handles upgrades.

---

## Permissions KerNotch requests

Nothing is requested at first launch. On macOS 15.4 and later, KerNotch requests Apple Events permission lazily, only when the music feature first needs it. On earlier macOS releases it reads now playing through a system framework and does not request Apple Events permission.

| Permission | Why it's needed | When it's requested |
|---|---|---|
| Apple Events (macOS 15.4 and later) | To query and control Spotify and Apple Music for the music activity card | The first time you play a track from a supported app after enabling the music provider |

KerNotch does not request and has no code path that would need: Camera, Microphone, Screen Recording, Accessibility, Full Disk Access, Contacts, or Location.

The screen-recording and microphone-recording indicators in KerNotch observe that a recording is in progress through a public system notification, the same mechanism used for charging state. They never enable recording, never capture what is being recorded, and never require Screen Recording or Microphone permission. The Discord integration reads which app is running the microphone through the same kind of public CoreAudio state, with the same guarantees.

---

## What stays on your device

Everything KerNotch knows stays on your Mac:

- **Settings** are stored in one file, `settings.json`, in KerNotch's Application Support folder at `~/Library/Application Support/KerNotch`. Only your user account can read it.
- **The Discord authorization token** (only once you connect Discord) is kept in a file in that same folder, readable only by your user account, and deleted when you disconnect.
- **No other persistent data** is written, apart from the app language macOS keeps in KerNotch's preferences and CPU diagnostic reports under `~/Library/Logs/KerNotch`.

---

## Third-party services

KerNotch has no third-party SDKs, no advertising networks, and no analytics services. It does not integrate with any external service on your behalf unless you connect Discord, as described under Network activity.

---

## Children

KerNotch does not knowingly collect any information from anyone, including children.

---

## Changes to this policy

If this policy changes in a future release, the updated version will be included in the release and the effective date above will be updated. Because KerNotch collects nothing, any change would only ever narrow or clarify what is written here, not expand data collection.

---

## Contact

KerNotch is an open-source project. Questions about this policy can be raised as a GitHub issue in the project repository.
