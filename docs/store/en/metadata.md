# App Store Metadata — English (en-US)

This file contains all App Store Connect text fields for the English (United States) locale. Copy each section's content verbatim into the corresponding App Store Connect field.

---

## App Name

```
NotchFlow
```

## Subtitle (30 chars max)

```
Live activities in your notch
```

## Category

- **Primary:** Utilities
- **Secondary:** Productivity

## Age Rating

4+ (no objectionable content)

---

## Description (4000 chars max)

```
NotchFlow turns the notch on your MacBook into a live-activity surface — a glanceable status and control strip that shows what's happening right now and collapses away the moment there's nothing to show.

WHAT IT SHOWS

• Music — now-playing card with track title, artist, album art, and playback controls for Spotify and Apple Music, right in the notch.
• Timers and stopwatches — start a countdown or stopwatch from the notch; watch it tick without opening another app.
• Recording indicators — a clear visual when your screen or microphone is being recorded, so you always know.
• Charging status — a brief card when your charger connects or disconnects.
• AI agent status — live state of Claude Code, Codex CLI, and OpenCode: thinking, working, waiting for you, or done. Glance at the notch instead of switching to a terminal.

HOW IT WORKS

NotchFlow is event-driven. It wakes up when something happens, shows the relevant card, and goes back to sleep the moment that activity ends. When idle, it uses close to zero CPU.

AI agent status works through small hook scripts NotchFlow installs for you — with your explicit approval, one agent at a time. The hooks push a status event to NotchFlow over a local connection that never leaves your Mac. NotchFlow never reads your screen, never inspects terminal output, and never guesses.

PRIVACY

NotchFlow collects nothing. No analytics, no telemetry, no crash reports sent off-device, no account required. The only network connection it ever makes is a local loopback listener for AI agent hooks — unreachable from outside your machine. Everything stays on your Mac.

PERMISSIONS

NotchFlow asks for permissions only when you turn on the feature that needs them — never at first launch.

• Apple Events: used to query and control Spotify and Apple Music for the music card.
• File access: used by the hook installer to write the agent hook scripts you approve.

That's it. No camera, no microphone, no screen recording, no accessibility, no full disk access.

REQUIREMENTS

• MacBook with a notch (MacBook Pro 2021 or later, MacBook Air 2022 or later)
• macOS 14 Sonoma or later
```

---

## Keywords (100 chars max, comma-separated)

```
notch,dynamic island,music,timer,AI agent,Claude,Codex,recording,charging,live activity
```

> **Note:** Do not use "Dynamic Island" or "MacBook" as standalone keyword phrases that could imply Apple affiliation. The keyword above uses "dynamic island" as a descriptive term for the UI pattern, which is acceptable per App Store guidelines when used in keywords (not the app name). If review flags it, remove it and replace with "notch widget" or "notch app".

---

## What's New (first release)

```
Initial release.
```

---

## Support URL

```
https://github.com/ataozeren/dynamic-island-for-macbook
```

## Marketing URL (optional)

Leave blank until a landing page exists.

## Privacy Policy URL

```
https://github.com/ataozeren/dynamic-island-for-macbook/blob/main/docs/PRIVACY.md
```

---

## App Review Notes

Paste the following into the "Notes" field in App Store Connect under App Review Information.

```
Hello App Review,

Thank you for reviewing NotchFlow.

WHAT THE APP DOES
NotchFlow is a macOS utility that displays live-activity cards (music, timers, recording indicators, charging status, and AI coding agent status) in the notch area of MacBook models that have a notch. It is event-driven: it shows a card when an activity starts and hides it when the activity ends.

THE OVERLAY WINDOW
NotchFlow uses an NSWindow positioned at the top of the screen, set to NSWindow.Level.screenSaver, with a transparent background and a non-rectangular click-through region. This is the standard technique for drawing in the notch area on macOS. The window does not cover any interactive UI outside the notch region. It does not intercept clicks intended for other apps. It does not use any private API.

NO PRIVATE API
NotchFlow does not use any private framework or private API in the App Store build. The music provider in the App Store build uses AppleScript (Apple Events) to communicate with Spotify and Apple Music — a fully public, documented mechanism. The MediaRemote framework used in the direct/Homebrew build is excluded from the App Store build at compile time via a build flag.

PERMISSIONS
• Apple Events (NSAppleEventsUsageDescription): used to query now-playing state and send playback commands to Spotify and Apple Music.
• com.apple.security.network.server: used for the loopback HTTP listener that receives status events from AI coding agents running locally. The listener is bound to 127.0.0.1 only.
• User-selected file access: used by the hook installer to write small hook scripts to agent config files (e.g., ~/.claude/settings.json) that the user explicitly selects via NSOpenPanel.

TESTING THE APP
To see the music card: open Spotify or Apple Music and play a track. Grant Apple Events permission when prompted.
To see the timer card: open NotchFlow settings and start a timer.
To see the recording card: start a screen recording with QuickTime or the system screenshot tool.
To see the charging card: connect or disconnect a power adapter.
To see the AI agent card: the hook installer in settings can be demonstrated without a live agent by sending a test IPC event via curl to the loopback listener address shown in settings.

No account or login is required to test any feature.

If you have any questions, please reach out via the support URL.
```

---

## Privacy Nutrition Label

Fill in App Store Connect > App Privacy as follows. Every data type not listed here should be set to "Not Collected."

### Data Not Collected

NotchFlow does not collect any data. Select **"No, we do not collect data from this app"** on the App Privacy page.

If App Store Connect requires you to enumerate types anyway, set every category to **Not Collected**:

| Data Type | Collected? | Notes |
|---|---|---|
| Contact Info | Not Collected | |
| Health & Fitness | Not Collected | |
| Financial Info | Not Collected | |
| Location | Not Collected | |
| Sensitive Info | Not Collected | |
| Contacts | Not Collected | |
| User Content | Not Collected | |
| Browsing History | Not Collected | |
| Search History | Not Collected | |
| Identifiers | Not Collected | |
| Purchases | Not Collected | |
| Usage Data | Not Collected | |
| Diagnostics | Not Collected | |
| Other Data | Not Collected | |

---

## Screenshots

Required sizes for Mac App Store:

- **1280 × 800** (required)
- **2560 × 1600** (required for Retina)

Suggested screenshot sequence:

1. Notch showing the music card with playback controls
2. Notch showing the timer card counting down
3. Notch showing the AI agent "thinking" state
4. Notch showing the recording indicator
5. Settings window overview

> Screenshots are not yet produced. See `docs/65-app-icon-and-assets.md` (task 65) for the asset pipeline.
