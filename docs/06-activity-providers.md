# Activity Providers

This document specifies every `NotchFlowProviders` type shipping in V1: its event source, the exact API it uses, the permission or entitlement it needs, the `Activity` it produces, that activity's priority and update cadence, how it tears itself down, and how it can be verified in CI versus only on real hardware. It is a design specification — nothing in this folder is code.

Each provider is a single type implementing the `Activity` protocol (`05-activity-model.md`) that watches exactly one system or IPC source and translates its events into `Activity` registrations, updates, and ends on the `ActivityManager`. No provider talks to another provider, and no provider talks to `NotchFlowUI` — see the module graph and dependency rule in `01-architecture.md`.

## Music

Music is the longest section here because it is the one provider that does not exist as a single implementation: the App Store's sandbox rules make it impossible to ship the same music-observation code in both build configurations, so V1 ships two interchangeable providers behind one protocol, selected at compile time. See `10-build-and-distribution.md` for the full build-configuration mechanism this section relies on.

### The `MusicProvider` protocol

`NotchFlowProviders` defines a `MusicProvider` protocol independent of the `Activity` protocol itself — it is the seam between "however we learn about now-playing" and "how we turn that into a `MusicActivity`". Exactly one concrete conformance is compiled into any given build:

| Conformance | Build | Mechanism |
|---|---|---|
| `AppleScriptMusicProvider` | `AppStore` | ScriptingBridge to Spotify.app and Music.app |
| `MediaRemoteMusicProvider` | `Direct` | The system-wide `MediaRemote` private framework |

### `AppleScriptMusicProvider` (App Store build)

- **Event source:** Distributed notifications that Spotify and Music.app post on track change and play-state change (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`), observed via `DistributedNotificationCenter`. The notification payload carries enough to know *something* changed but not always the full up-to-date state, so the provider treats it as a wake-up signal.
- **Exact API:** On receiving a distributed notification, the provider queries the app's current state through ScriptingBridge-generated interfaces (`SpotifyApplication`, `MusicApplication` from each app's `.sdef`) for track name, artist, and player state. Transport control (play/pause, next/previous) is sent back the same way, as an AppleScript/ScriptingBridge call against the active app.
- **Permission or entitlement:** `com.apple.security.scripting-targets` entitlement, scoped to `com.spotify.client` and `com.apple.Music`, declared in `NotchFlow-AppStore.entitlements`. The user sees a one-time Apple Events automation prompt per target app on first control attempt; no separate NotchFlow-specific permission screen is needed.
- **Activity produced:** `MusicActivity` with track title, artist, and play/pause state; `kind = .music`.
- **Priority:** `low` (see the V1 priority table in `05-activity-model.md`) — music never forces the panel visible on its own account and stays visible only as long as something is playing.
- **Update cadence:** Purely event-driven, bounded by how often Spotify/Music post their distributed notifications (on track change and play/pause, not on a timer). No polling of player state at any interval.
- **Teardown:** The provider calls `end()` on the current `MusicActivity` when it observes a "stopped" player state, or when both target apps are no longer running.
- **CI-vs-hardware verifiability:** The ScriptingBridge call surface can be unit-tested in CI behind a protocol seam (a fake conforming to the same Objective-C interface), but the actual round-trip against a real Spotify/Music.app instance and the Apple Events consent prompt can only be exercised on real hardware with those apps installed.
- **Honest limitation:** Only Spotify and Apple Music are observable this way. YouTube Music, browser-tab audio (Chrome, Safari), and any other player that does not post the two specific distributed notifications above are invisible to this provider. This is a real, user-facing capability gap versus the Direct build, not a bug to be silently patched — see "communicating reduced capability" below.

### `MediaRemoteMusicProvider` (Direct build)

- **Event source:** The system's private `MediaRemote` framework, which aggregates now-playing state across every app that participates in Control Center / media-key routing — Spotify, Apple Music, YouTube Music (web or app), browser tabs, anything.
- **Exact API:** `MediaRemote`'s now-playing notification callback (`MRMediaRemoteRegisterForNowPlayingNotifications`) delivered on a `MediaRemote`-owned queue, and its info dictionary getter (`MRMediaRemoteGetNowPlayingInfo`) for track metadata. Because `MediaRemote` is a private framework, every symbol is resolved dynamically at runtime via `dlopen`/`dlsym` against the framework path — **the symbol table is never linked at compile time**, so no `MediaRemote` or `MRMediaRemote` string appears in the binary's import table even in the Direct build. Transport control uses the corresponding `MediaRemote` command-sending function.
- **Permission or entitlement:** None. `MediaRemote` now-playing observation requires no user-facing permission prompt and no entitlement; the Direct build is unsandboxed, so there is no App Sandbox restriction to satisfy either.
- **Activity produced:** The same `MusicActivity` shape as `AppleScriptMusicProvider` — track title, artist, play/pause state, `kind = .music`. `NotchFlowUI` renders one music view regardless of which provider is behind it.
- **Priority:** `low`, identical to the App Store conformance — the `Activity` protocol and the priority table make provider identity invisible above `NotchFlowProviders`.
- **Update cadence:** Purely event-driven — `MediaRemote` calls back only on an actual now-playing state change, no polling.
- **Teardown:** The provider calls `end()` on the current `MusicActivity` when `MediaRemote` reports an empty now-playing state (nothing playing anywhere on the system).
- **CI-vs-hardware verifiability:** The `dlopen`/`dlsym` resolution and the now-playing callback wiring can only be exercised on real hardware running the Direct build; CI can unit-test the `MusicActivity` construction logic against a fake `MediaRemote` info dictionary, but not the dynamic symbol resolution itself.

### The compile-time selection mechanism

`NotchFlowProviders` selects the conformance with a Swift compilation condition, matching the two build configurations described in `10-build-and-distribution.md`:

```swift
#if APPSTORE_BUILD
let musicProvider: MusicProvider = AppleScriptMusicProvider()
#elseif DIRECT_BUILD
let musicProvider: MusicProvider = MediaRemoteMusicProvider()
#endif
```

This is a compile-time branch, not a runtime `if`. The `AppStore` scheme's build settings define `APPSTORE_BUILD` and omit any reference to `MediaRemoteMusicProvider.swift` from the target membership for that configuration where feasible; where a single target must contain both files, the `#if` guard above ensures `MediaRemoteMusicProvider`'s body — including every `dlsym` string literal — is stripped by the compiler before the App Store binary is produced.

### The MediaRemote prohibition

**No `MediaRemote` or `MRMediaRemote` symbol may reach the App Store build, under any code path, for any reason.** The reason is Apple App Review Guideline 2.5.1 (Software Requirements): apps must use public APIs, and use of private frameworks is grounds for automatic rejection. `MediaRemote` is undocumented and unlisted in any public SDK; a submission that links it — even if the linked code path is unreachable at runtime — risks rejection because static analysis of the binary, not runtime behavior, is what review tooling and `nm`/`otool` inspection catch.

This prohibition is enforced two ways:
1. **Compile-time exclusion**, per the mechanism above — the App Store target does not compile `MediaRemoteMusicProvider`'s implementation body under `APPSTORE_BUILD`.
2. **The forbidden-symbol build guard** (`10-build-and-distribution.md`, todo 21): a post-build script phase on the `AppStore` scheme runs `nm`/`strings` against the built product and fails the build non-zero on any match for `MediaRemote` or `MRMediaRemote`. This is the backstop that catches an accidental reintroduction (a stray import, a shared file that should have been guarded) before it can reach archiving, let alone submission.

### Communicating reduced capability to App Store users

Because `AppleScriptMusicProvider` only sees Spotify and Apple Music, a user on the App Store build who plays audio from YouTube Music or a browser tab sees no music activity at all — NotchFlow does not show a broken or stale card, it shows nothing, which is the correct and honest behavior for a source it genuinely cannot observe. The Settings screen (`08-settings-and-localization.md`) states this limitation plainly next to the music section — "Supports Spotify and Apple Music. For all other players, install the Homebrew/Direct build." — rather than leaving the user to guess why their music never appears. This is a capability difference disclosed up front, not a bug to be worked around silently.

## Timer / Stopwatch

- **Event source:** None — this is the one V1 provider with no external system to observe. NotchFlow owns the entire lifecycle of a countdown or stopwatch: the user starts it from the panel, and the provider is both the origin and the consumer of its own ticks.
- **Exact API:** `DispatchSourceTimer` configured with generous leeway (per the performance contract in `02-performance-contract.md`), so the OS can coalesce this wakeup with others already scheduled rather than firing a precise one-shot every second. This is the only provider in V1 permitted to own a repeating tick at all — every other provider is purely reactive to an external event.
- **Permission or entitlement:** None.
- **Activity produced:** `TimerActivity` with mode (countdown or stopwatch), remaining or elapsed duration, and a running/paused flag; `kind = .timer`.
- **Priority:** `high` while the timer is expiring or has just expired and needs acknowledgment (the V1 priority table's "Timer expiring" row); a running, non-expiring timer that the user is actively watching is not itself a forcing condition beyond having registered an activity at all.
- **Update cadence:** The `DispatchSourceTimer` fires only while the timer's `TimerActivity` is part of the currently visible panel — a countdown running with the panel closed or the notch not visible does not tick NotchFlow's own timer at the interval a visible one would; the underlying duration is still tracked (typically via a start timestamp and elapsed-time computation rather than tick-accumulation, so no ticks are ever "lost" while not visible), but the moment-to-moment display refresh only runs when there is a display to refresh. This is the concrete instance of the performance contract's "active only while a time-based activity is visible" rule.
- **Teardown:** `end()` fires when the countdown reaches zero and the auto-dismiss window (if any) elapses, when the user manually stops the timer, or when the user acknowledges an expired timer's notification.
- **CI-vs-hardware verifiability:** Fully verifiable in CI. Because NotchFlow is both source and consumer, the state machine (start → tick → expire → acknowledge) is pure logic over a clock abstraction and needs no live hardware, no permission, and no external app — this is one of the `NotchFlowCore`-adjacent pieces suited to the TDD approach in `11-testing-strategy.md`.

## Screen Recording

- **Event source:** `CGWindowListCreateImage`/`ScreenCaptureKit`-adjacent recording-session state, or, at minimum, the system-level indicator macOS itself surfaces when the screen is being recorded via `ScreenCaptureKit` (macOS 12.3+) or the older `CGDisplayStream`/`AVCaptureScreenInput` paths.
- **Exact API:** `SCShareableContent`/`SCStream` session-state observation where the recording session is one NotchFlow itself might not initiate (a third-party screen recorder or the system's own screenshot toolbar recording) — what is publicly observable is whether *the system* currently has an active screen-recording session via the Screen Recording privacy category, not which specific app started it. NotchFlow observes the same system-level "is anything recording the screen right now" signal that macOS itself exposes in its own menu bar indicator, rather than instrumenting every possible recording app individually.
- **Permission or entitlement:** Screen Recording permission (`kTCCServiceScreenCapture`), requested via the standard system prompt the first time the provider attempts to query recording state; declared in `NSCameraUsageDescription`-adjacent `Info.plist` usage-description keys as applicable to the exact API chosen.
- **Activity produced:** `RecordingActivity` with source = screen, an elapsed-time counter since recording started; `kind = .recording`.
- **Priority:** `high`, per the V1 priority table — a recording indicator stays visible for the duration of the recording and does not auto-dismiss, since silently missing that the screen is being recorded is a worse failure mode than an extra always-on indicator.
- **Update cadence:** Event-driven off the recording-session-started/-stopped notification; the elapsed-time counter within the activity increments while visible, following the same "ticks only while shown" discipline as the timer provider.
- **Teardown:** `end()` fires when the system reports the recording session has ended.
- **CI-vs-hardware verifiability:** The permission-gated system query can only be exercised on real hardware with Screen Recording permission actually granted (CI runners are typically headless and cannot grant or exercise TCC permissions); the `RecordingActivity` construction and priority/teardown logic around it is unit-testable in CI against a fake session-state source.
- **Honest statement of detectability:** NotchFlow shows *that* the screen is being recorded, not *by which app* — the public API surface tells you a recording session is active, not the identity of every possible recorder, so the indicator is deliberately generic ("Recording") rather than naming a specific app unless the API path chosen happens to expose that detail reliably.

## Audio Recording

- **Event source:** The system-level microphone-in-use signal, the same category of indicator macOS shows as an orange dot in the menu bar when any app is actively capturing audio.
- **Exact API:** Observation of active audio input sessions via `AVAudioSession`-adjacent APIs on macOS (or the microphone-in-use aggregate signal exposed through the same privacy-indicator mechanism screen recording uses) — the provider does not open its own microphone stream to detect this; it observes the system's own "is the mic in use" state.
- **Permission or entitlement:** Microphone permission (`kTCCServiceMicrophone` / `NSMicrophoneUsageDescription`) is required to query this state, requested via the standard system prompt on first use; the provider never captures or processes audio content itself, only the in-use boolean.
- **Activity produced:** `RecordingActivity` with source = audio (the same `RecordingActivity` type as screen recording, distinguished by source), an elapsed-time counter since capture started; `kind = .recording`.
- **Priority:** `high`, identical to screen recording in the V1 priority table, for the same reason — a live microphone is exactly the kind of ambient state a user wants to be reliably reminded of.
- **Update cadence:** Event-driven off the microphone-in-use-changed signal; elapsed-time counter ticks only while visible.
- **Teardown:** `end()` fires when the system reports no app is using the microphone.
- **CI-vs-hardware verifiability:** Same constraint as screen recording — the permission-gated system query needs real hardware with Microphone permission granted; the activity and teardown logic is unit-testable in CI against a fake in-use signal.
- **Honest statement of detectability:** Like screen recording, NotchFlow shows *that* the microphone is in use, not *which app* is using it, unless the chosen API path happens to expose the consuming process reliably.

## Charging

- **Event source:** IOKit power-source change notifications — the same mechanism the menu bar battery indicator itself is built on.
- **Exact API:** `IOPSNotificationCreateRunLoopSource`, registered once at launch and left running for the life of the process; it delivers a callback whenever the system's power-source state changes (AC connected/disconnected, charging/charged transition), which the provider then reads via `IOPSCopyPowerSourcesInfo`/`IOPSGetPowerSourceDescription` to determine the current state.
- **Permission or entitlement:** None — power-source state is available without any user-facing permission prompt or entitlement in either build configuration.
- **Activity produced:** `ChargingActivity` with state (`pluggedIn` → `charging` → `fullyCharged`); `kind = .charging`. Per the explicit rule from `draft.md:272` — **a persistent battery percentage is never displayed.** The activity communicates the charging *transition*, not an ongoing percentage readout; showing a live, continuously-updating battery percentage would turn a brief, dismissible notification into exactly the kind of persistent low-value display this app's whole design avoids.
- **Priority:** `normal`, per the V1 priority table, and auto-dismissing.
- **State machine:**

```
MacBook plugged in
        │
        ▼
   pluggedIn / charging     ── ChargingActivity registered
        │
        ▼
   fullyCharged              ── ChargingActivity updated
        │
        ▼ (auto-dismiss duration elapses)
   end()                     ── island closes
```

- **Update cadence:** Purely event-driven off the IOKit run-loop source callback; no polling of battery state at any interval.
- **Teardown:** `end()` fires automatically after the auto-dismiss duration elapses following the `fullyCharged` update, per the `ActivityManager`'s own auto-dismiss timer contract in `05-activity-model.md` — the provider does not need its own dismiss timer.
- **CI-vs-hardware verifiability:** The `IOPSNotificationCreateRunLoopSource` registration and real power-source transitions can only be observed on real hardware with a battery (or a way to simulate AC plug/unplug); the `ChargingActivity` state-machine transitions (`pluggedIn` → `charging` → `fullyCharged` → dismissed) are pure logic over an injected power-source-state sequence and are fully unit-testable in CI.

## AI Status

AI status is not documented in depth here — see `07-ai-integration.md` for the full agent state machine, the IPC protocol, and the per-agent (Claude Code, Codex CLI, OpenCode) hook integrations. In the terms of this document: the AI provider's "event source" is the IPC protocol itself (a custom URL scheme and a loopback HTTP listener) rather than a system framework, its `Activity` is `AIActivity` with `kind = .ai`, its priority is `high` for both "AI needs input" and "AI completed" per the V1 priority table, and it needs the `com.apple.security.network.server` entitlement only for the HTTP-listener transport in the sandboxed build — the URL-scheme transport needs no entitlement in either build.

## Provider × build configuration matrix

| Provider | `AppStore` build | `Direct` build |
|---|---|---|
| Music | Available — degraded (Spotify + Apple Music only, via `AppleScriptMusicProvider`) | Available — full (any app, via `MediaRemoteMusicProvider`) |
| Timer / Stopwatch | Available | Available |
| Screen recording | Available | Available |
| Audio recording | Available | Available |
| Charging | Available | Available |
| AI status | Available (IPC only) | Available (IPC, plus optional agent session log reading per `10-build-and-distribution.md`) |

Every provider except music is identical across both build configurations — no permission, API, or behavior differs. Music is the sole provider whose capability set genuinely changes with the build, which is why it is the only row above marked "degraded" rather than a flat "available"/"unavailable".
