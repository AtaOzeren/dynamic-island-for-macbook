# Activity Providers

This document specifies every `KerNotchProviders` type shipping in V1: its event source, the exact API it uses, the permission or entitlement it needs, the `Activity` it produces, that activity's priority and update cadence, how it tears itself down, and how it can be verified in CI versus only on real hardware. It is a design specification — nothing in this folder is code.

Each provider is a single type implementing the `Activity` protocol (`05-activity-model.md`) that watches exactly one system or IPC source and translates its events into `Activity` registrations, updates, and ends on the `ActivityManager`. No provider talks to another provider, and no provider talks to `KerNotchUI` — see the module graph and dependency rule in `01-architecture.md`.

## Music

Music is the longest section here because it is the one provider that does not exist as a single implementation: macOS 15.4 restricted `MediaRemote` now-playing metadata to Apple-signed processes, so KerNotch carries two interchangeable providers behind one protocol and picks one at launch for the running macOS release. Both are compiled into the one build described in `10-build-and-distribution.md`.

### The `MusicProvider` protocol

`KerNotchProviders` defines a `MusicProvider` protocol independent of the `Activity` protocol itself — it is the seam between "however we learn about now-playing" and "how we turn that into a `MusicActivity`". Exactly one concrete conformance is instantiated per launch:

| Conformance | macOS release | Mechanism | Lives in |
|---|---|---|---|
| `AppleScriptMusicProvider` | 15.4 and later | ScriptingBridge to Spotify.app and Music.app | `KerNotchProviders` |
| `MediaRemoteMusicProvider` | Before 15.4 | The system-wide `MediaRemote` private framework | `KerNotch` app target |

### `AppleScriptMusicProvider` (macOS 15.4 and later)

- **Event source:** Distributed notifications that Spotify and Music.app post on track change and play-state change (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`), observed via `DistributedNotificationCenter`. The notification payload carries enough to know *something* changed but not always the full up-to-date state, so the provider treats it as a wake-up signal.
- **Exact API:** On receiving a distributed notification, the provider queries the app's current state through ScriptingBridge-generated interfaces (`SpotifyApplication`, `MusicApplication` from each app's `.sdef`) for track name, artist, and player state. Transport control (play/pause, next/previous) is sent back the same way, as an AppleScript/ScriptingBridge call against the active app. Artwork comes from Music.app's track artwork data, and from the HTTPS `artworkUrl` Spotify reports for the current track.
- **Permission or entitlement:** The `com.apple.security.automation.apple-events` entitlement in `KerNotch.entitlements` — without it the hardened runtime refuses to send Apple Events at all — plus the `NSAppleEventsUsageDescription` purpose string. macOS asks for Apple Events consent once per target app (`com.spotify.client`, `com.apple.Music`); `MusicAutomationGate` shows KerNotch's own explanation before that prompt, and the Activities pane shows one permission row per target app. No separate KerNotch-specific permission screen is needed.
- **Activity produced:** `MusicActivity` with track title, artist, and play/pause state; `kind = .music`.
- **Priority:** `low` (see the V1 priority table in `05-activity-model.md`) — music never forces the panel visible on its own account and stays visible only as long as something is playing.
- **Update cadence:** Purely event-driven, bounded by how often Spotify/Music post their distributed notifications (on track change and play/pause, not on a timer). No polling of player state at any interval.
- **Teardown:** The provider calls `end()` on the current `MusicActivity` when it observes a "stopped" player state, or when both target apps are no longer running.
- **CI-vs-hardware verifiability:** The ScriptingBridge call surface can be unit-tested in CI behind a protocol seam (a fake conforming to the same Objective-C interface), but the actual round-trip against a real Spotify/Music.app instance and the Apple Events consent prompt can only be exercised on real hardware with those apps installed.
- **Honest limitation:** Only Spotify and Apple Music are observable this way. YouTube Music, browser-tab audio (Chrome, Safari), and any other player that does not post the two specific distributed notifications above are invisible to this provider. This is a real, user-facing capability gap on macOS 15.4 and later, not a bug to be silently patched — see "coverage by macOS release" below.

### `MediaRemoteMusicProvider` (before macOS 15.4)

- **Event source:** The system's private `MediaRemote` framework, which aggregates now-playing state across every app that participates in Control Center / media-key routing — Spotify, Apple Music, YouTube Music (web or app), browser tabs, anything.
- **Exact API:** `MediaRemoteNowPlayingBridge` (`KerNotch/SystemNowPlayingBridge+MediaRemote.swift`) registers with `MRMediaRemoteRegisterForNowPlayingNotifications`, observes the now-playing change notifications `MediaRemote` then posts, and reads track metadata with `MRMediaRemoteGetNowPlayingInfo` and play state with `MRMediaRemoteGetNowPlayingApplicationPlaybackState`. Because `MediaRemote` is a private framework, every symbol is resolved at runtime via `dlopen`/`dlsym` against the framework path; the framework is never linked at compile time. Transport control uses `MRMediaRemoteSendCommand`.
- **Permission or entitlement:** None. `MediaRemote` now-playing observation requires no user-facing permission prompt and no entitlement, and this backend sends no Apple Events.
- **Activity produced:** The same `MusicActivity` shape as `AppleScriptMusicProvider` — track title, artist, play/pause state, `kind = .music`. `KerNotchUI` renders one music view regardless of which provider is behind it.
- **Priority:** `low`, identical to the ScriptingBridge conformance — the `Activity` protocol and the priority table make provider identity invisible above the provider layer.
- **Update cadence:** Purely event-driven — `MediaRemote` notifies only on an actual now-playing state change, no polling.
- **Teardown:** The provider calls `end()` on the current `MusicActivity` when `MediaRemote` reports an empty now-playing state (nothing playing anywhere on the system).
- **CI-vs-hardware verifiability:** The `dlopen`/`dlsym` resolution and the now-playing notification wiring can only be exercised on real hardware running a macOS release before 15.4; CI can unit-test the `MusicActivity` construction logic against a fake bridge snapshot, but not the dynamic symbol resolution itself.

### The runtime selection mechanism

`makeMusicProvider(gate:)` in `KerNotch/MusicBackend.swift` selects the conformance with an availability check:

```swift
if #available(macOS 15.4, *) {
    AppleScriptMusicProvider(gate: gate, artworkLoader: URLSessionArtworkDataLoader())
} else {
    MediaRemoteMusicProvider()
}
```

This is a runtime branch, not a compile-time one: both providers are in every build, and the running macOS release decides. `makeMusicAutomationAccess(gate:)` sits beside it and answers from the same check whether the Activities pane shows Apple Events permission rows, so a backend that sends no Apple Events never offers to request them. The selected backend's name (`ScriptingBridge` or `MediaRemote`) is shown in the About pane and printed by `KerNotch --print-music-backend` without opening a window.

### Keeping the MediaRemote backend in the build

`MediaRemote` has no public header, documentation page, or entitlement, and Apple can change or restrict it in any release — macOS 15.4 already did (row 10 of `12-api-feasibility-matrix.md`). Two rules follow:

1. **Kept out of the provider package.** `MediaRemoteMusicProvider` and its bridge live in the `KerNotch` app target, not in `KerNotchProviders`, beside the one branch that decides to use them.
2. **Guarded as present.** Because the framework is resolved with `dlopen`/`dlsym`, nothing at compile time notices if the backend drops out of the build. `scripts/check-media-remote-linked.sh <binary>` fails when the Release binary lacks the framework path the bridge passes to `dlopen` or the now-playing notification name it subscribes to, and `scripts/check-music-backend.sh` fails when `--print-music-backend` does not report the backend the runner's macOS version calls for. CI runs both (`10-build-and-distribution.md`).

### Coverage by macOS release

On macOS 15.4 and later, a user who plays audio from YouTube Music or a browser tab sees no music activity at all — KerNotch does not show a broken or stale card, it shows nothing, which is the correct and honest behavior for a source it genuinely cannot observe. Below 15.4, `MediaRemote` covers any app that reports now playing to the system. The Activities pane reflects the selected backend: on 15.4 and later it lists the Apple Events permission for Spotify and Apple Music, and below 15.4 it lists none.

## Timer / Stopwatch

- **Event source:** None — this is the one V1 provider with no external system to observe. KerNotch owns the entire lifecycle of a countdown or stopwatch: the user starts it from the panel, and the provider is both the origin and the consumer of its own ticks.
- **Exact API:** `DispatchSourceTimer` configured with generous leeway (per the performance contract in `02-performance-contract.md`), so the OS can coalesce this wakeup with others already scheduled rather than firing a precise one-shot every second. This is the only provider in V1 permitted to own a repeating tick at all — every other provider is purely reactive to an external event.
- **Permission or entitlement:** None.
- **Activity produced:** `TimerActivity` with mode (countdown or stopwatch), remaining or elapsed duration, and a running/paused flag; `kind = .timer`.
- **Priority:** `high` while the timer is expiring or has just expired and needs acknowledgment (the V1 priority table's "Timer expiring" row); a running, non-expiring timer that the user is actively watching is not itself a forcing condition beyond having registered an activity at all.
- **Update cadence:** The `DispatchSourceTimer` fires only while the timer's `TimerActivity` is part of the currently visible panel — a countdown running with the panel closed or the notch not visible does not tick KerNotch's own timer at the interval a visible one would; the underlying duration is still tracked (typically via a start timestamp and elapsed-time computation rather than tick-accumulation, so no ticks are ever "lost" while not visible), but the moment-to-moment display refresh only runs when there is a display to refresh. This is the concrete instance of the performance contract's "active only while a time-based activity is visible" rule.
- **Menu bar controls:** The menu bar item carries Start 5-, 10- and 25-Minute Timer entries and a Stop Timer entry (`KerNotch/TimerMenuControls.swift`). They follow the Activities pane's "Timers and stopwatches" switch (`providers.timer.enabled`): switching it off hides those entries and their separator and stops any running timer, because a switched-off provider is not observed and a countdown started from the menu would be drawn nowhere; switching it back on shows the entries again.
- **Teardown:** `end()` fires when the countdown reaches zero and the auto-dismiss window (if any) elapses, when the user manually stops the timer, when the user acknowledges an expired timer's notification, or when the timer switch is turned off.
- **CI-vs-hardware verifiability:** Fully verifiable in CI. Because KerNotch is both source and consumer, the state machine (start → tick → expire → acknowledge) is pure logic over a clock abstraction and needs no live hardware, no permission, and no external app — this is one of the `KerNotchCore`-adjacent pieces suited to the TDD approach in `11-testing-strategy.md`.

## Screen Recording

- **Event source:** The system's own screen recording, started from the screenshot toolbar. Two signals, neither of which needs a permission: `NSWorkspace` reports the capture UI coming and going, and ReplayKit's open recording movie says whether a recording is actually under way.
- **Exact API:** `NSWorkspace.didLaunchApplicationNotification` / `didTerminateApplicationNotification` and the `runningApplications` key path for the capture UI; `proc_listpids`/`proc_pidfdinfo` to see whether `replayd` holds a `.mov` open under the system recordings folder. KerNotch deliberately does **not** query `ScreenCaptureKit` session state: that is behind the Screen Recording permission, and `09-security-privacy-permissions.md` refuses to ask for the very capability the indicator reports on.
- **Permission or entitlement:** None.
- **Activity produced:** `RecordingActivity` with source = screen, an elapsed-time counter since recording started; `kind = .recording`, compact rank `capture`.
- **Priority:** `high`, per the V1 priority table — a recording indicator stays visible for the duration of the recording and does not auto-dismiss, since silently missing that the screen is being recorded is a worse failure mode than an extra always-on indicator.
- **What decides:** only the probe. The capture UI can quit while a recording is under way, so its absence says nothing; an observer that read it as "not recording" showed nothing for the rest of the session. The workspace signal only decides *when to read the probe*.
- **Update cadence:** The probe is read when observation starts — so a recording already under way when KerNotch launches is seen — and whenever the capture UI comes or goes. A low-frequency tick keeps reading it while a recording is live or the toolbar is open, and is cancelled otherwise: an idle island keeps no timer, per `02-performance-contract.md`.
- **Teardown:** `end()` fires when the probe reports the recording movie closed.
- **CI-vs-hardware verifiability:** A real recording can only be made on a Mac, and the probe reads live processes; the gating, the session latch and the start-up reading are unit-tested in CI against fakes.
- **Honest statement of detectability:** only a recording the screenshot toolbar was part of is shown — Cmd-Shift-5, and anything else that opens that toolbar. A recording started from the menu bar without it, and any third-party recorder, is not detected.

  This was measured rather than assumed. During a menu-bar recording the probe reported the recording correctly within half a second, and the indicator still never appeared: nothing woke the probe. The folder the system records into would have woken it, but `~/Library/Group Containers/group.com.apple.screencapture` answers `Operation not permitted` to an application without Full Disk Access — it can be neither read nor watched — and the movie inside it is unlinked as soon as it is created, so it never appears in a listing either. That leaves two ways to catch those recordings, and both were declined: reading the probe on a clock (measured at 0.02 ms per reading, but a timer that runs while nothing is happening, against `02-performance-contract.md`), or asking for the Screen Recording permission (`09-security-privacy-permissions.md` refuses it). No indicator is shown rather than a guessed one.

## Audio Recording

- **Event source:** The system-level microphone-in-use signal, the same category of indicator macOS shows as an orange dot in the menu bar when any app is actively capturing audio.
- **Exact API:** Observation of active audio input sessions via `AVAudioSession`-adjacent APIs on macOS (or the microphone-in-use aggregate signal exposed through the same privacy-indicator mechanism screen recording uses) — the provider does not open its own microphone stream to detect this; it observes the system's own "is the mic in use" state.
- **Permission or entitlement:** Microphone permission (`kTCCServiceMicrophone` / `NSMicrophoneUsageDescription`) is required to query this state, requested via the standard system prompt on first use; the provider never captures or processes audio content itself, only the in-use boolean.
- **Activity produced:** `RecordingActivity` with source = audio (the same `RecordingActivity` type as screen recording, distinguished by source), an elapsed-time counter since capture started; `kind = .recording`.
- **Priority:** `high`, identical to screen recording in the V1 priority table, for the same reason — a live microphone is exactly the kind of ambient state a user wants to be reliably reminded of.
- **Update cadence:** Event-driven off the microphone-in-use-changed signal; elapsed-time counter ticks only while visible.
- **Teardown:** `end()` fires when the system reports no app is using the microphone.
- **CI-vs-hardware verifiability:** Same constraint as screen recording — the permission-gated system query needs real hardware with Microphone permission granted; the activity and teardown logic is unit-testable in CI against a fake in-use signal.
- **Honest statement of detectability:** Like screen recording, KerNotch shows *that* the microphone is in use, not *which app* is using it, unless the chosen API path happens to expose the consuming process reliably.

## Discord Call

- **Event source:** Two, and either is enough. The per-process microphone state CoreAudio has published since macOS 14.2 (`kAudioHardwarePropertyProcessObjectList`, `kAudioProcessPropertyIsRunningInput`), matched against the `com.hnc.Discord` bundle-identifier prefix — the input is opened by Discord's `helper.Renderer` process, not the application. Changes are heard through `kAudioProcessPropertyDevices`: on macOS 26 the documented `kAudioProcessPropertyIsRunningInput` listener was measured never to fire, while the device list changed on every join and leave. And, once the user has pressed Connect, Discord's local RPC over its IPC socket (`$TMPDIR/discord-ipc-N`): `GET_SELECTED_VOICE_CHANNEL` plus the `VOICE_CHANNEL_SELECT` and `VOICE_SETTINGS_UPDATE` subscriptions.
- **Permission or entitlement:** None for the microphone half. The RPC half needs Discord's `rpc` and `rpc.voice.read` scopes, which Discord grants only to approved applications — and, before approval, to the application's owner and its listed testers. Every user connects through KerNotch's own application, whose Client ID is a build setting (`Config/Discord.xcconfig`, see `16-discord-application.md`), authorized with PKCE and no client secret. There is no user-facing field for another application. The socket is reachable because KerNotch is not sandboxed: it lives in the per-user `$TMPDIR` KerNotch shares with Discord.
- **Activity produced:** `DiscordCallActivity` with the channel and its server when the RPC connection names them, and what the call sounds like from the user's side: live, muted, or deafened. Deafened is its own state rather than a kind of mute — Discord switches the microphone off with it but leaves its `mute` flag alone, so an island reading `mute` alone drew a live microphone for someone who could neither speak nor hear. The pill draws a microphone, a slashed microphone, or slashed headphones accordingly.
- **Priority:** `high`, `pinned` band, like the microphone indicator it stands in for.
- **Update cadence:** Event-driven on both halves. Process listeners are attached only while the integration is on *and* an input device is running. `VOICE_CONNECTION_STATUS` and `SPEAKING_START`/`STOP` are never subscribed: the first re-sends ping statistics every few seconds for a whole call, the second fires on every syllable. Server names are fetched once per server. Reconnection after Discord quits is a five-step backoff (2–32 s) that then waits for `NSWorkspace.didLaunchApplicationNotification`.
- **Interaction with Audio Recording:** while the integration is on, `SystemAudioRecordingObserver` leaves Discord out; its session ends only when every microphone client is known and excluded, so another application sharing the microphone keeps the ordinary indicator on screen beside the call.
- **Teardown:** `end()` when Discord releases the microphone and the RPC connection reports no channel, or when the integration is switched off.
- **CI-vs-hardware verifiability:** CoreAudio attribution and the real socket need hardware and a running Discord; the monitor's listener gating, the exclusion rule, the frame codec, the RPC session (authorization, renewal, reconnection, leave) and the activity are unit-tested against fakes.
- **Honest statement of detectability:** screen sharing ("Go Live") is not shown. Discord's local RPC reports the selected channel and the voice settings, and nothing in either says a stream is running; seeing it any other way means detecting a third-party screen capture, which needs the Screen Recording permission `09-security-privacy-permissions.md` refuses to ask for. No indicator is shown rather than a guessed one.

## Charging

- **Event source:** IOKit power-source change notifications — the same mechanism the menu bar battery indicator itself is built on.
- **Exact API:** `IOPSNotificationCreateRunLoopSource`, created when the provider starts observing and invalidated when it stops; it delivers a callback whenever the system's power-source state changes (AC connected/disconnected, charging/charged transition, capacity ticks), which `SystemPowerSourceObserver` reads via `IOPSCopyPowerSourcesInfo`/`IOPSGetPowerSourceDescription` into a `PowerSourceReading`: the state and the internal battery's level (`kIOPSCurrentCapacityKey` over `kIOPSMaxCapacityKey`). A Mac without an internal battery produces no reading.
- **Permission or entitlement:** None — power-source state is available without any user-facing permission prompt or entitlement.
- **Activity produced:** `ChargingActivity` with a state (`onBattery`, `pluggedIn`, `charging`, `fullyCharged`) and a `BatteryLevel`; `kind = .charging`. Per the explicit rule from `draft.md:272` — **a persistent battery percentage is never displayed.** The level is drawn as the fill of a battery glyph, the way the menu bar draws it, and only for the seconds the notification lasts; no digits appear on screen, and only VoiceOver is told the number. The fill is green while connected, and an unplugged battery at or below 20% is drawn red. The bolt is drawn only while the battery is filling, so a Mac holding at its charge limit shows a connected battery without one.
- **Priority:** `normal`, per the V1 priority table, compact rank `transition`, and auto-dismissing after 4 seconds.
- **State machine:** only the cable announces.

```
first reading after observation starts  ── baseline, nothing announced
        │
        ▼
cable plugged in or unplugged           ── ChargingActivity registered (state + level)
        │
        ├── state changes within 4 s of the cable ── ChargingActivity updated in place
        │
        ▼ (auto-dismiss duration elapses)
end()                                   ── island closes

while connected: pluggedIn ⇄ charging ⇄ fullyCharged  ── nothing announced
```

- **Why only the cable:** a charge limit or optimised charging pauses and resumes the charge again and again while the Mac stays connected, and the battery reports full and not-full as it tops up. Announcing those changes reopened the island all through a charge. The change a moment after the cable goes in — the charge starting — still reaches the notification on screen, measured from the cable's edge so a flickering charge cannot keep it open.
- **Update cadence:** Purely event-driven off the IOKit run-loop source callback; no polling of battery state at any interval. The provider owns no timer: the announcement window is compared with the clock only when a reading arrives.
- **Teardown:** `end()` fires automatically when the auto-dismiss duration elapses, per the `ActivityManager`'s own auto-dismiss timer contract in `05-activity-model.md`. Launching KerNotch, or switching the provider back on, takes a fresh baseline and announces nothing.
- **CI-vs-hardware verifiability:** The `IOPSNotificationCreateRunLoopSource` registration and real power-source transitions can only be observed on real hardware with a battery; the description classification, the baseline, the cable-edge rule and the refinement window are pure logic over an injected reading sequence and clock, and are fully unit-testable in CI.

## AI Status

AI status is not documented in depth here — see `07-ai-integration.md` for the full agent state machine, the IPC protocol, and the per-agent (Claude Code, Codex CLI, OpenCode) hook integrations. In the terms of this document: the AI provider's "event source" is the IPC protocol itself (a custom URL scheme and a loopback HTTP listener) rather than a system framework, its `Activity` is `AIActivity` with `kind = .ai`, its priority is `high` for both "AI needs input" and "AI completed" per the V1 priority table, and neither transport needs an entitlement.

## Provider × macOS release matrix

| Provider | macOS 14.0 – 15.3 | macOS 15.4 and later |
|---|---|---|
| Music | Available — any app that reports now playing, via `MediaRemoteMusicProvider` | Available — Spotify and Apple Music only, via `AppleScriptMusicProvider` |
| Timer / Stopwatch | Available | Available |
| Screen recording | Available | Available |
| Audio recording | Available | Available |
| Discord call | Available — microphone attribution needs macOS 14.2; channel name and leave need KerNotch's Discord application to be approved, or the user to be one of its testers | Available — channel name and leave under the same approval condition |
| Charging | Available | Available |
| AI status | Available (IPC) | Available (IPC) |

Apart from Discord's microphone attribution needing macOS 14.2, every provider except music behaves identically on every supported macOS release — no permission, API, or behavior differs. Music is the sole provider whose capability set genuinely changes with the release, which is why its two cells above describe different coverage rather than a flat "available".
