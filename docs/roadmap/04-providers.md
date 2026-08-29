# Phase 4: Activity Providers

**Todos:** 41-49
**Status:** NOT STARTED
**Depends on:** Phase 2 (Core, under TDD) — the `ActivityProvider` protocol and activity model providers register against. Phase 3 (Window and UI) — the compact/expanded view containers that render each provider's activity.
**Blocks:** Phase 6 (Settings, Localization, Polish) needs the per-provider enablement wired here before it can expose provider toggles in settings. Phase 7 (Performance, Packaging, Distribution) needs both music backends in place before it can verify the App Store build excludes the MediaRemote symbol.

## What this phase delivers

Every source of a live activity except AI agent status (Phase 5): music (via two interchangeable backends split by build configuration), a timer/stopwatch owned entirely by NotchFlow, screen recording and audio recording indicators built on public detection signals only, and the charging state machine. The phase closes with all providers wired into the registry behind per-provider settings, so each one starts only when enabled and stops immediately when disabled.

## Todos

### 41. Define the `MusicProvider` protocol and the shared music activity

The protocol, the now-playing model, the transport-command interface, and the SwiftUI compact/expanded views — all independent of which backend supplies the data.

- **Acceptance:** Views render correctly from a fake provider; no backend-specific type leaks into the view layer.
- **QA (CI):** Snapshot or structural tests against a fake provider. Evidence: `.omo/evidence/task-41-notchflow-v1.log`.
- **Commit:** `feat(music): add music provider protocol and views`

### 42. Implement `AppleScriptMusicProvider` (App Store build)

ScriptingBridge against Spotify and Music.app for metadata and transport, driven by the distributed notifications those apps post rather than by polling. Handles the app-not-running and permission-denied cases by producing no activity rather than erroring.

- **Acceptance:** Track changes in Spotify and Music appear in the island; play/pause/next/previous from the island control the app; denying Automation permission degrades silently.
- **QA (HW):** With each app in turn, change track, use each transport control, then revoke Automation permission and confirm graceful degradation. Evidence: `.omo/evidence/task-42-notchflow-v1/`.
- **Commit:** `feat(music): add AppleScript music backend`

### 43. Implement `MediaRemoteMusicProvider` (Direct build only)

System-wide now-playing observation, compiled only into the `Direct` configuration, resolved dynamically, never linked into `AppStore`.

- **Acceptance:** The App Store build contains no MediaRemote symbol (todo 21's guard passes); the Direct build shows now-playing for a media app that the AppleScript backend cannot see.
- **QA (HW + CI):** CI runs the symbol guard against the App Store build. On hardware, play audio in a browser and confirm the Direct build shows it while the App Store build does not. Evidence: `.omo/evidence/task-43-notchflow-v1/`.
- **Commit:** `feat(music): add MediaRemote backend for direct builds`

### 44. Wire the build-time music backend selection

Compilation condition selects the backend; a single composition-root line differs between configurations.

- **Acceptance:** Both configurations build and run with the correct backend active; the active backend is visible in the about pane for support purposes.
- **QA (CI):** Build both configurations and assert the reported backend name differs. Evidence: `.omo/evidence/task-44-notchflow-v1.log`.
- **Commit:** `feat(music): select music backend per build configuration`

### 45. Implement the timer and stopwatch provider

NotchFlow's own countdown and stopwatch, started from the expanded island or settings. The only provider owning a repeating tick: a `DispatchSourceTimer` with generous leeway, created when a time activity becomes visible and cancelled when it is not.

- **Acceptance:** The displayed time is accurate within the documented tolerance; no timer source exists while no time activity is visible.
- **QA (HW):** Run a countdown, confirm accuracy against a reference clock, end it, and confirm via sampling that no timer source remains. Evidence: `.omo/evidence/task-45-notchflow-v1.log`.
- **Commit:** `feat(timer): add countdown and stopwatch activities`

### 46. Implement the screen recording indicator provider

Observes the publicly available screen-capture signal documented in `docs/12` and produces a recording activity with elapsed time.

- **Acceptance:** Starting a screen recording produces the activity; stopping ends it. Cases the public API cannot detect are documented rather than faked.
- **QA (HW):** Start and stop a screen recording; observe the activity appear and disappear. Evidence: `.omo/evidence/task-46-notchflow-v1/`.
- **Commit:** `feat(recording): add screen recording indicator`

### 47. Implement the audio recording indicator provider

Observes microphone-in-use via the mechanism documented in `docs/12`, without NotchFlow itself requesting microphone permission.

- **Acceptance:** The activity appears while another app records; NotchFlow never prompts for microphone access.
- **QA (HW):** Start a recording in another app; confirm the activity and confirm no microphone prompt from NotchFlow. Evidence: `.omo/evidence/task-47-notchflow-v1/`.
- **Commit:** `feat(recording): add audio recording indicator`

### 48. Implement the charging provider

`IOPSNotificationCreateRunLoopSource`-driven state machine: plugged in → charging → fully charged → auto-dismiss. Never displays a persistent battery percentage.

- **Acceptance:** Connecting power shows charging; reaching full shows fully charged then dismisses; no persistent percentage is ever rendered.
- **QA (HW):** Connect and disconnect power; observe both transitions. Assert by code review and by screenshot that no percentage is persistently displayed. Evidence: `.omo/evidence/task-48-notchflow-v1/`.
- **Commit:** `feat(power): add charging activity`

### 49. Wire all providers into the registry with per-provider enablement

Each provider is started only when its setting is enabled and stopped immediately when disabled.

- **Acceptance:** Disabling a provider in settings stops its observation within the documented delay and removes its activities.
- **QA (HW):** Toggle each provider off and on; confirm observation stops and starts. Evidence: `.omo/evidence/task-49-notchflow-v1.log`.
- **Commit:** `feat(providers): wire providers to settings-driven enablement`

## Verification notes

Todo 41 and the CI half of todo 43 are the only headless-runnable work in this phase — everything else needs the physical notched MacBook to observe a real backend, a real recording, or a real power event. Per the plan's Final Verification Wave, the `HW` todos are collected into a scripted checklist with screenshot/recording evidence rather than run one-off. See the plan's [Verification strategy](../../.omo/plans/notchflow-v1.md#verification-strategy) for the anti-fake-pass rules that apply to every acceptance criterion above.
