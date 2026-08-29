# notchflow-v1 - Work Plan

## TL;DR (For humans)

**What you'll get:** A complete `docs/` specification folder (15 documents) followed by a working, native macOS app called NotchFlow that turns your MacBook notch into a live-activity island — showing music, timers, screen/audio recording, charging, and the live status of your AI coding agents (Claude Code, Codex, OpenCode) — while sitting at essentially zero CPU when nothing is happening. It ships in two forms from one codebase: a sandboxed Mac App Store build and a notarized build for Homebrew.

**Why this approach:** Two decisions carry the whole design. First, the App Store forbids the private framework that every competing notch app uses for music, so the music source is split into two interchangeable providers chosen at build time — the App Store build talks to Spotify and Apple Music through official scripting, the Homebrew build sees every media app. Second, AI agents report their status by pushing events to NotchFlow through small hook scripts that NotchFlow installs for you, so NotchFlow never reads your screen and never guesses.

**What it will NOT do:** It will not show incoming calls, AirDrop progress, or other apps' download progress — macOS has no public way to observe those, so they are postponed with a written note. It will not run any AI model of its own. It will not read your screen or use Accessibility to inspect other apps.

**Effort:** XL
**Risk:** Medium — the engineering is well-understood and every API has been feasibility-checked, but two items carry real uncertainty: App Store review of an always-on-top overlay window, and the exact idle-power numbers on real hardware.
**Decisions to sanity-check:** dual distribution instead of picking one channel; MIT license; deferring calls/AirDrop/transfer progress out of V1; TDD on the pure core only, not on AppKit glue.

Your next move: approve and run `/start-work`, or ask for a high-accuracy review first. Full execution detail follows below.

---

> TL;DR (machine): XL effort, Medium risk. Deliverables: docs/ (15 specs), SPM-modularized Swift 6 macOS accessory app, NSPanel notch overlay, ActivityManager + 6 V1 providers, AI IPC bridge + 3 hook installers, settings + i18n, dual-build release pipeline, performance + hardware test harness.

## Scope

### Must have

**Documentation (delivered first, drives everything after):**
- `docs/` folder with 15 separate documents, one concern each, as enumerated in todos 1-16.

**Application:**
- Native macOS app, Swift 6, SwiftUI for content + AppKit for windowing. Minimum target macOS 14.0.
- Accessory app (`LSUIElement`), no Dock icon, optional status item, launch-at-login via `SMAppService`.
- SPM-modularized: `NotchFlowCore` (no AppKit), `NotchFlowProviders`, `NotchFlowUI`, app shell.
- Event-driven detection of the built-in notched display; correct behaviour on monitor hotplug, sleep/wake, lid open/close, resolution change.
- Borderless non-activating `NSPanel` pinned under the notch on the built-in display only, above the menu bar, visible over full-screen apps, click-through while idle.
- Three visual states: hidden (idle), compact, expanded. Animated transitions.
- `ActivityManager` + `Activity` protocol (`start`/`update`/`end`, `compactView`/`expandedView`, `priority`), multi-activity slotting and ordering.
- V1 providers: music (dual implementation), timer/stopwatch, screen recording, audio recording, charging, AI agent status.
- AI bridge: custom URL scheme + loopback listener; hook installers for Claude Code, Codex CLI, OpenCode; agent state machine (idle → thinking → working → using tool → waiting for user → completed → error).
- Settings window: display selection, per-integration toggles, per-event toggles, launch-at-login, appearance.
- Localization via String Catalog; English + Turkish at minimum, structure ready for more.
- Performance: measured idle CPU and wakeups, with a reproducible measurement script.
- Two build configurations (`AppStore`, `Direct`) with separate entitlements; release pipeline for both.
- MIT license, README, contribution guide, privacy policy.

### Must NOT have (guardrails, anti-slop, scope boundaries)

- **No `MediaRemote` symbols in the App Store build.** Not linked, not `dlopen`ed, not referenced in strings. This is an automatic rejection under App Store Review Guideline 2.5.1.
- **No screen scraping.** No OCR, no screenshot analysis, no `CGWindowListCreateImage` polling, no Accessibility (`AXUIElement`) inspection of other apps to infer state.
- **No polling loops.** No `while true`, no repeating `Timer` that runs while idle, no periodic re-query of system state. Every input is a subscription to an OS event or an inbound IPC message.
- **No animation while hidden.** No `CADisplayLink`, no implicit CoreAnimation work when the panel is ordered out.
- **No network activity** except the loopback listener. No analytics, no telemetry, no crash reporting service, no update check in V1 (Homebrew handles updates).
- **No third-party dependencies** in the shipped app. Dev-time tooling (SwiftLint, swift-format, xcbeautify) is allowed. If a dependency seems necessary, stop and raise it rather than adding it.
- **No incoming call, AirDrop progress, or third-party download progress features.** Deferred; see `docs/13-deferred-backlog.md`.
- **No V1.5 or V2 features** (Live Activities, navigation, shipping, live scores, smart home, ChatGPT/Gemini/Cursor/Copilot integrations, public API, developer SDK, user-defined activities).
- **No AI model, no inference, no API keys.** NotchFlow is a status and control surface only.
- **No "Dynamic Island" or "MacBook"** in the product name, bundle identifier, or App Store metadata.
- **No feature work that assumes the Apple Developer Program membership exists.** Signing/notarization/submission todos are written but must not block development.
- Do not invent features not listed here. Do not add settings not listed in `docs/08`. Do not add providers beyond the six named.

## Verification strategy

> Zero human intervention - all verification is agent-executed, except the explicitly marked hardware matrix.

- **Test decision: TDD for `NotchFlowCore`** — write the failing test first for every pure unit (geometry math, activity model, priority engine, state machines, IPC payload parsing, hook-script generation). **Tests-after** for AppKit/SwiftUI integration code. Framework: **Swift Testing** (`@Test`, `#expect`) for all new tests; XCTest only where a Swift Testing equivalent does not exist.
- **Core is AppKit-free by construction**, so it runs on a headless CI runner. Geometry math takes injected values, never a live `NSScreen`.
- **Evidence:** `.omo/evidence/task-<N>-notchflow-v1.<ext>` — build logs, test output, `powermetrics` captures, screenshots.
- **Two verification tiers**, and every todo declares which it is in:
  - `CI` — verifiable headlessly by `xcodebuild test` / a script on a GitHub Actions macOS runner.
  - `HW` — requires the physical notched MacBook plus one external monitor. These are collected into the Final verification wave and executed as a scripted checklist with screenshot evidence.
- **Anti-fake-pass rules:** a todo is not complete on a worker's say-so. Every todo's QA names an exact command and an exact assertion on its output. A test that passes because it asserts nothing is a failure. Grep-only verification is never sufficient for behavioural claims.

## Execution strategy

### Parallel execution waves

- **Wave 0 — Documentation (todos 1-16).** Fully parallel; 16 independent files. No code dependency. Must complete before Wave 2 begins, because the docs are the spec the code is checked against.
- **Wave 1 — Project foundation (todos 17-23).** Sequential-ish; 17 gates the rest.
- **Wave 2 — Core under TDD (todos 24-32).** Highly parallel; pure Swift, no AppKit, no ordering constraints between the units.
- **Wave 3 — Window and UI (todos 33-40).** Depends on Wave 2 core types.
- **Wave 4 — Providers (todos 41-49).** Parallel per provider once the `ActivityProvider` protocol (todo 28) exists.
- **Wave 5 — AI integration (todos 50-58).** Depends on the IPC core (todo 31) and the provider protocol.
- **Wave 6 — Settings, localization, polish (todos 59-65).** Depends on everything having settings to expose.
- **Wave 7 — Performance, packaging, distribution (todos 66-74).** Last; depends on a feature-complete app.

### Dependency matrix

| Wave | Depends on | Blocks | Parallelism |
|---|---|---|---|
| 0 Documentation | nothing | 2 | 16-wide |
| 1 Foundation | nothing (can run alongside 0) | 2,3,4,5,6,7 | 2-wide after todo 17 |
| 2 Core (TDD) | 1 | 3,4,5 | 8-wide |
| 3 UI | 2 | 4 (views), 6 | 4-wide |
| 4 Providers | 2, 3 | 6, 7 | 6-wide |
| 5 AI | 2, 3 | 6, 7 | 5-wide |
| 6 Settings/i18n | 3,4,5 | 7 | 3-wide |
| 7 Perf/dist | 6 | — | 3-wide |

## Todos

### Wave 0 — Documentation

- [x] 1. Create `docs/README.md` as the documentation index
  - **Content:** Product tagline; a statement that this folder is the pre-implementation design specification and that nothing here is code; a table of contents linking all 15 documents with a one-line description each (matching the titles in todos 2-16); a "five decisions everything depends on" section covering (a) dual distribution one-codebase-two-builds, (b) the split music provider and why the App Store build cannot contain MediaRemote, (c) idle means genuinely idle, (d) we never look at the screen, (e) AI status is the differentiator and NotchFlow never runs a model; a pointer to `.omo/plans/notchflow-v1.md` as the executable plan; MIT license note; naming note that Apple marks are not used.
  - **Acceptance:** File exists; every one of the 15 sibling documents is linked; all links resolve to files created in this wave.
  - **QA (CI):** `ls docs/*.md | wc -l` returns 15. A link-check script resolves every relative link in `docs/README.md` to an existing file; exit non-zero on any miss. Evidence: `.omo/evidence/task-1-notchflow-v1.txt`.
  - **Commit:** `docs(readme): add documentation index`

- [x] 2. Create `docs/00-product-overview.md`
  - **Content:** What NotchFlow is in two paragraphs. Who it is for (MacBook owners with a notch; developers using AI coding agents). The problem statement. Explicit non-goals. The full V1 feature list restated as user-visible capabilities: music now-playing and transport control, countdown timer and stopwatch, screen recording indicator, audio recording indicator, charging state, AI agent status, and multiple simultaneous activities. A "what V1 deliberately excludes" section listing incoming calls, AirDrop progress, third-party download progress, and all V1.5/V2 items, each with a one-line reason and a link to `13-deferred-backlog.md`. A success-criteria section in user terms. Source of truth note: derived from `draft.md` sections 1, 8, 16, 17, 22.
  - **Acceptance:** Every V1 feature listed in `draft.md:222-285` appears either in the included list or in the excluded list with a reason. No feature is silently dropped.
  - **QA (CI):** A checklist script greps the document for each of the ten V1 feature keywords (music, timer, stopwatch, screen recording, audio recording, charging, AI, multi-activity, call, AirDrop) and asserts each appears; manual read-back diff against `draft.md` recorded in evidence. Evidence: `.omo/evidence/task-2-notchflow-v1.txt`.
  - **Commit:** `docs(overview): add product overview and V1 scope`

- [x] 3. Create `docs/01-architecture.md`
  - **Content:** The module graph as a diagram and a table: `NotchFlowCore` (pure Swift, zero AppKit/SwiftUI import — holds `Activity`, `ActivityManager`, `ActivityPriority`, notch geometry math as pure functions, the AI state machine, IPC message types), `NotchFlowProviders` (imports Core + system frameworks; one provider per activity source), `NotchFlowUI` (imports Core; SwiftUI views + the NSPanel controller), `NotchFlow` app target (composition root only). State the **dependency rule** explicitly: dependencies point inward, `NotchFlowCore` imports nothing but Foundation, and a build-time check enforces it. The end-to-end event flow: OS event or IPC message → provider → `ActivityManager` → priority resolution → panel state change → render → activity ends → panel ordered out → idle. A sequence diagram for one concrete case (a track change while a timer is running). Threading model: providers may receive callbacks on arbitrary queues; all `ActivityManager` mutation is `@MainActor`; the documented hop pattern. Why this shape: testability in headless CI, and the ability to swap the music provider per build configuration.
  - **Acceptance:** The dependency rule is stated as an enforceable invariant with the enforcement mechanism named.
  - **QA (CI):** Document contains the four module names and the string "imports nothing but Foundation" or equivalent; the invariant it describes is the one todo 20 enforces. Evidence: `.omo/evidence/task-3-notchflow-v1.txt`.
  - **Commit:** `docs(architecture): add module graph and event flow`

- [x] 4. Create `docs/02-performance-contract.md`
  - **Content:** The numeric budget as a table: idle CPU < 0.1% averaged over 60s; idle wakeups < 1/s; resident memory < 60 MB idle; no measurable GPU work while hidden; energy impact "Low" in Activity Monitor while idle. The forbidden-patterns list with a one-line reason each: `while true`, repeating `Timer` active while idle, periodic system re-query, screen scanning, animation while hidden, unnecessary network, retained render loop. The required patterns: subscribe to OS notifications, `DispatchSourceTimer` with generous leeway and only while a time-based activity is visible, `orderOut(nil)` to stop compositing, passive `NSEvent` global monitors rather than polling, `ProcessInfo.beginActivity` used narrowly and released promptly, cooperation with App Nap. The measurement protocol: exact `powermetrics` invocation for per-process CPU and wakeups, exact `ps`/`top` invocation, which Instruments template for each question, how long to sample, and what constitutes a pass. A statement that these numbers are asserted by an automated script (todo 66) and that a regression is a build failure.
  - **Acceptance:** Every budget line has a number and a measurement command. No aspirational language without a threshold.
  - **QA (CI):** Script asserts the document contains at least five numeric thresholds and at least two copy-pasteable shell commands. Evidence: `.omo/evidence/task-4-notchflow-v1.txt`.
  - **Commit:** `docs(performance): add measurable idle-cost contract`

- [x] 5. Create `docs/03-display-and-notch.md`
  - **Content:** How to identify the built-in notched display: `NSScreen.safeAreaInsets.top > 0` combined with a built-in check; note that `safeAreaInsets` is macOS 12+ and that external displays report zero. The exact notch rectangle formula, stated as a pure function over four inputs (`frame`, `safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`) so it is unit-testable without a live screen: origin x = `auxiliaryTopLeftArea.maxX`, origin y = `frame.maxY - safeAreaInsets.top`, width = `auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX`, height = `safeAreaInsets.top`. The fallback behaviour when the display has no notch: NotchFlow still runs and anchors to the top-centre of the menu bar, documented as a supported degraded mode. The event sources for reacting without polling: `NSApplication.didChangeScreenParametersNotification` for hotplug and resolution change, `NSWorkspace.willSleepNotification` / `didWakeNotification` for sleep, and how lid open/close surfaces. The display-selection policy: default is automatic and means the built-in display; the user may override to a named display; on disconnect of the selected display, fall back to built-in; never migrate the island to an external display implicitly. A state table: (screens present) × (user setting) → (target screen). Known edge cases: clamshell mode with the lid closed and no built-in screen active; screen mirroring; a display appearing before its `localizedName` is populated.
  - **Acceptance:** The geometry formula is expressed as a pure function signature. The state table is complete over its inputs.
  - **QA (CI):** Document contains the four-input function signature and a table with at least six rows. Evidence: `.omo/evidence/task-5-notchflow-v1.txt`.
  - **Commit:** `docs(display): specify notch geometry and display selection`

- [x] 6. Create `docs/04-overlay-window.md`
  - **Content:** The `NSPanel` specification as a property table: `styleMask` `[.borderless, .nonactivatingPanel]`, `isFloatingPanel = true`, `level` set above the menu bar, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow` policy, `hidesOnDeactivate = false`, `isMovable = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `canBecomeKey` and `canBecomeMain` policy, `ignoresMouseEvents` toggled by state. For each property, one line on what breaks if it is wrong. The three visual states with their geometry: hidden (window ordered out, zero cost), compact (a pill hugging the notch edges), expanded (a larger rounded panel below the notch). The sizing strategy: keep the window at its maximum expanded bounds and animate the SwiftUI content inside it, rather than resizing the window per frame — with the reason (window resize is expensive and janky). Interaction: hover to peek, click to expand, click outside or Escape to collapse, and the rule that `ignoresMouseEvents` is true whenever collapsed so menu-bar clicks are never stolen. Animation specification: spring parameters, durations, and the constraint that no animation runs while the window is hidden. Behaviour over full-screen apps, over other Spaces, and during Mission Control. Appearance: light/dark mode, reduced-motion and reduced-transparency accessibility settings honoured.
  - **Acceptance:** Every listed property has a stated value and a failure mode.
  - **QA (CI):** Document contains at least ten `NSPanel`/`NSWindow` property names each with a value. Evidence: `.omo/evidence/task-6-notchflow-v1.txt`.
  - **Commit:** `docs(overlay): specify the notch panel window`

- [x] 7. Create `docs/05-activity-model.md`
  - **Content:** The `Activity` protocol in full: identity, kind, `priority`, lifecycle (`start`, `update`, `end`), view builders (`compactView`, `expandedView`), an optional auto-dismiss duration, and an optional primary action (what a click does). The `ActivityPriority` enum: `critical`, `high`, `normal`, `low`, with the V1 assignment table (AI needs-input → high; AI completed → high, auto-dismissing; recording → high; timer expiring → high; charging → normal, auto-dismissing; file/transfer → normal; music → low). The `ActivityManager` contract: registration, deduplication by identity, the ordering rule, how many activities may occupy the compact view simultaneously and what happens beyond that (overflow indicator), what the expanded view shows (all active, ordered), and the transition rules between hidden/compact/expanded. The auto-dismiss policy and its timing. The rule that the panel is ordered out when and only when the activity set becomes empty, and that this is what guarantees the idle budget. A worked example matching `draft.md:189-220`: music + timer + transfer simultaneously, compact and expanded renderings. An extension guide: exactly what a contributor implements to add a new activity type, so that adding features later does not require touching the manager.
  - **Acceptance:** The priority table covers every V1 activity. The overflow rule is unambiguous.
  - **QA (CI):** Document contains the protocol member list and a priority table with a row per V1 activity kind. Evidence: `.omo/evidence/task-7-notchflow-v1.txt`.
  - **Commit:** `docs(activities): specify the activity protocol and manager`

- [x] 8. Create `docs/06-activity-providers.md`
  - **Content:** One section per V1 provider. For each: the event source, the exact API used, whether it needs a permission or entitlement, the activity it produces, its priority, its update cadence, its teardown, and its CI-vs-hardware verifiability. **Music** gets the longest section and must document the split: the `MusicProvider` protocol; the `AppleScriptMusicProvider` used in the App Store build (ScriptingBridge to Spotify and Music.app, plus the distributed notifications those apps post, with the honest limitation that YouTube Music, browser audio, and other players are not visible); the `MediaRemoteMusicProvider` used in the Direct build (system-wide now-playing, dynamically resolved, never linked); the compile-time selection mechanism; the explicit prohibition on any MediaRemote symbol reaching the App Store build and the reason (Guideline 2.5.1 automatic rejection); and how the UI communicates the reduced capability to App Store users. **Timer/stopwatch** — NotchFlow's own timers, the only provider that owns a repeating tick, with the leeway'd `DispatchSourceTimer` policy and the rule that it ticks only while visible. **Screen recording** and **audio recording** — the event sources, what is publicly observable, the permission implications, and the honest statement of which cases are detectable. **Charging** — `IOPSNotificationCreateRunLoopSource` from IOKit, the state machine (plugged in → charging → fully charged → dismiss), and the explicit rule from `draft.md:272` that a persistent battery percentage is never displayed. **AI status** — a pointer to `07-ai-integration.md`. A closing table: provider × build configuration × available/degraded/unavailable.
  - **Acceptance:** The music section states the MediaRemote prohibition explicitly and names the guideline. Every provider has a permission line, even if it is "none".
  - **QA (CI):** Document contains a section per provider and the string "2.5.1"; a script asserts the provider × build table has a row per provider. Evidence: `.omo/evidence/task-8-notchflow-v1.txt`.
  - **Commit:** `docs(providers): specify V1 activity providers and the music split`

- [x] 9. Create `docs/07-ai-integration.md`
  - **Content:** The design principle first: NotchFlow is a status and control surface; it runs no model, holds no API key, and never reads the screen. The agent state machine with its seven states (idle, thinking, working, using tool, waiting for user, completed, error), the legal transitions, and what each renders as in compact and expanded form. The **IPC protocol** as a versioned contract: the message envelope (schema version, agent id, session id, state, human-readable detail, optional tool name, optional progress, timestamp), the JSON schema, and the two transports — a custom URL scheme invoked with `open -g` (works in both builds, no entitlement) and a loopback HTTP listener bound to `127.0.0.1` on an ephemeral port written to a discoverable location (requires `com.apple.security.network.server` in the sandboxed build). State which transport is preferred and the fallback order. Security: the listener binds loopback only, validates the schema, rate-limits, and rejects oversized payloads; an unknown agent id is ignored unless the user has enabled it. **Per-agent integration** sections: **Claude Code** — hook configuration in `~/.claude/settings.json`, which hook events map to which NotchFlow states, the fact that hooks receive event JSON on stdin and that async hooks must be used so NotchFlow never slows the agent down; **Codex CLI** — the `notify` program setting in `~/.codex/config.toml`; **OpenCode** — the plugin file convention and the events a plugin observes. For each, the exact snippet NotchFlow generates. The **hook installer** UX: NotchFlow detects which agents are present, shows the user the exact change it proposes, writes only on explicit consent, backs up the original file, and offers one-click uninstall; it never edits a config file silently. The sandbox note: the App Store build cannot write to `~/.claude` or `~/.codex` without user-selected file access, so the installer uses an open panel and a security-scoped bookmark, while the Direct build may write directly — and if the user declines, NotchFlow shows the snippet for manual copy-paste. The privacy statement: NotchFlow stores no prompt content, no code, and no transcript; only the state and a short label cross the boundary. A note that Claude Desktop, ChatGPT desktop, Cursor, Copilot, and Gemini CLI expose no public status hook and are therefore not in V1.
  - **Acceptance:** The message schema is fully specified with every field typed. The consent-before-writing rule is stated unambiguously.
  - **QA (CI):** Document contains a JSON schema block, the seven state names, and the three agent sections. Evidence: `.omo/evidence/task-9-notchflow-v1.txt`.
  - **Commit:** `docs(ai): specify the AI status protocol and hook installers`

- [x] 10. Create `docs/08-settings-and-localization.md`
  - **Content:** The complete settings surface as a table — every setting, its type, its default, its persistence key, and where it appears — covering: display target (automatic / built-in / a named display), launch at login, appearance (auto/light/dark), reduced motion override, which activity providers are enabled, per-AI-agent enable plus per-event toggles (task started, task completed, task error, needs input, tool activity), hook installation status and install/uninstall actions, and the about/licence pane. Persistence: `UserDefaults` with a typed wrapper, key naming convention, migration policy for future schema changes, and the rule that defaults are safe (nothing enabled that would surprise a first-run user). The settings window itself: a standard SwiftUI settings scene, opened from the status item and from first-run onboarding, and the fact that opening it must not change the app's activation policy permanently. First-run onboarding flow: welcome, permission explanation, agent detection and hook offer, done. Localization: String Catalogs (`.xcstrings`) as the single mechanism, `String(localized:)` usage, the rule that no user-visible string is hardcoded in a view, how plurals and units are handled, how dates and durations are formatted per-locale, right-to-left readiness, and the ship set (English, Turkish) with a contributor guide for adding a language. App Store metadata localization and where those strings live.
  - **Acceptance:** Every setting has a default value. The "no hardcoded user-visible strings" rule is stated as an enforceable lint.
  - **QA (CI):** Document contains a settings table with a defaults column and the string `.xcstrings`. Evidence: `.omo/evidence/task-10-notchflow-v1.txt`.
  - **Commit:** `docs(settings): specify preferences and localization`

- [x] 11. Create `docs/09-security-privacy-permissions.md`
  - **Content:** The privacy stance up front: NotchFlow collects nothing, sends nothing off-device, and has no analytics; the only network socket is a loopback listener. The **entitlements table**, one column per build configuration, one row per entitlement, with the justification and the user-visible consequence: App Sandbox (App Store build: on; Direct build: on where possible), `com.apple.security.automation.apple-events` with `NSAppleEventsUsageDescription` for the AppleScript music provider, `com.apple.security.network.server` for the loopback listener, user-selected file access for the hook installer, and an explicit "not requested" list — no camera, no microphone recording, no screen recording, no Accessibility, no full disk access, no contacts, no location. The **permission request flow**: nothing is requested at launch; each permission is requested lazily at the moment the user enables the feature that needs it, with a plain-language explanation shown before the system prompt, and every feature degrades gracefully when denied rather than nagging. The purpose strings, verbatim, in English and Turkish. The **threat model**: the loopback listener as the only inbound surface, what a malicious local process could send, and the mitigations (schema validation, size limit, rate limit, per-agent user enablement, no code execution from payloads, no shell interpolation of received strings). The hook-installer trust model: NotchFlow modifies another tool's configuration only with explicit consent, shows the exact diff, backs up, and can fully uninstall. The data-at-rest statement: only user preferences, no history, no logs of agent content. A privacy-policy source-of-truth section whose text is reused for App Store Connect.
  - **Acceptance:** Every entitlement in either build appears in the table with a justification. The "not requested" list is present.
  - **QA (CI):** Document contains a two-column build table, the not-requested list, and verbatim purpose strings. Evidence: `.omo/evidence/task-11-notchflow-v1.txt`.
  - **Commit:** `docs(security): specify entitlements, permissions and threat model`

- [x] 12. Create `docs/10-build-and-distribution.md`
  - **Content:** The two build configurations side by side: `AppStore` (sandboxed, no private frameworks, AppleScript music provider, IPC-only AI integration, submitted to App Store Connect) and `Direct` (Developer ID signed and notarized, MediaRemote music provider, may read agent session logs, distributed as a `.dmg` on GitHub Releases and via a Homebrew Cask). How the split is implemented: build configurations, Swift compilation conditions, per-configuration entitlements files, and separate schemes — plus a build-time guard that fails the App Store build if a forbidden symbol appears in the binary. Version and build-number policy, and how the two channels stay in step. The **App Store pipeline**: bundle identifier, category, required metadata, screenshots, the privacy nutrition label answers, the review notes text explaining why an always-on-top overlay is necessary and that no private API is used, and a candid section on review risk with the mitigation. The **Direct pipeline**: Developer ID signing, hardened runtime, `notarytool` submission, stapling, `.dmg` layout, GitHub Releases, and the Homebrew Cask submission requirements including the cask stanza. The **blocked-on-membership** note: the Apple Developer Program is not yet purchased, so every signing, notarization, and submission step is written but gated; local development uses ad-hoc signing and is not blocked. A troubleshooting section for the common signing and notarization failures.
  - **Acceptance:** The forbidden-symbol build guard is specified concretely enough to implement. Every step that requires paid membership is marked.
  - **QA (CI):** Document contains both configuration names, the string "notarytool", a cask stanza, and at least three steps marked as membership-gated. Evidence: `.omo/evidence/task-12-notchflow-v1.txt`.
  - **Commit:** `docs(distribution): specify dual build and release pipelines`

- [x] 13. Create `docs/11-testing-strategy.md`
  - **Content:** The TDD boundary, stated precisely: TDD is mandatory for `NotchFlowCore` and for every pure function elsewhere; tests-after is acceptable for AppKit/SwiftUI glue; and the reason for the split. The framework choice (Swift Testing) and the migration/coexistence policy with XCTest. How to test event-driven code that depends on the system: every system dependency sits behind a protocol, and tests inject a fake that emits the events — with a concrete worked example for a screen-parameters change. How notch geometry is tested without a notch: the pure function takes four values, and the test table covers a 14" MacBook Pro, a 16" MacBook Pro, a notched Air, a non-notched Mac, and degenerate inputs. The **two-column verifiability matrix**, exhaustive for this app — `CI` column: core logic, activity ordering and priority, geometry math, state machines, IPC payload parsing and rejection cases, hook-script generation, localization completeness, build success for both configurations, forbidden-symbol guard, lint. `HW` column: actual notch alignment on real hardware, panel level over a full-screen app, panel behaviour across Spaces and Mission Control, monitor hotplug and unplug, sleep and wake, lid close and open, clamshell, resolution and scaling change, real music apps, permission dialogs and denial paths, real agent hook round-trip, and idle CPU and wakeup measurement. The hardware checklist is a numbered script with an expected observation and a screenshot per step. CI configuration: runner image and Xcode version policy, the `xcodebuild test` invocation, coverage reporting, `swiftlint` and `swift-format` gates, and `xcbeautify` for readable logs. The definition of done for a todo, and the explicit anti-pattern list: no test that asserts nothing, no grep-as-verification for behavioural claims, no completion claimed on a worker's self-report.
  - **Acceptance:** The two-column matrix accounts for every V1 feature. The hardware checklist is numbered and observable.
  - **QA (CI):** Document contains a two-column table with at least ten entries per column and a numbered hardware checklist. Evidence: `.omo/evidence/task-13-notchflow-v1.txt`.
  - **Commit:** `docs(testing): specify TDD boundary and CI/hardware matrix`

- [x] 14. Create `docs/12-api-feasibility-matrix.md`
  - **Content:** The research record, so that no future contributor re-litigates a settled question. A table with one row per capability NotchFlow needs, and columns: capability, the API or mechanism, minimum macOS version, public or private, entitlement required, works sandboxed, works in the Direct build, and a source link. Rows must cover at minimum: notch detection, notch rectangle, built-in display identification, screen-parameter change events, display reconfiguration callbacks, sleep and wake notifications, overlay window level and collection behaviour, click-through, power source change notification, now-playing metadata via MediaRemote, now-playing metadata via ScriptingBridge, media transport control, distributed notifications from Spotify and Music, screen recording detection, microphone in-use detection, AirDrop progress observation, third-party download progress observation, incoming call state, ActivityKit availability on macOS, launch at login, loopback listening, custom URL scheme handling, and reading another tool's config directory. Each row ends in a verdict: feasible with public API, feasible only unsandboxed, sandbox-blocked, or impossible. Below the table, a short paragraph per contested row explaining the evidence, especially: why MediaRemote cannot ship in the App Store build, why incoming calls are impossible on macOS, and why AirDrop and generic transfer progress are not observable. A dated "as researched" header and an instruction to re-verify before acting on any row older than a year.
  - **Acceptance:** Every capability referenced anywhere else in `docs/` appears as a row. Every row has a verdict and a source.
  - **QA (CI):** Script asserts the table has at least twenty rows and that every row's verdict cell matches one of the four allowed verdicts. Evidence: `.omo/evidence/task-14-notchflow-v1.txt`.
  - **Commit:** `docs(feasibility): record the macOS API feasibility matrix`

- [x] 15. Create `docs/13-deferred-backlog.md`
  - **Content:** The standing note the user asked for. A clear framing: these are postponed, not cancelled, and each will be revisited. One section per deferred item with a uniform shape — what the feature is, why it is not in V1 (the specific API gap), what would have to become true for it to become possible, and how much work it would then be. Cover: incoming call activity; AirDrop transfer progress; generic third-party download and file-transfer progress; a NotchFlow-owned drop shelf as a possible partial substitute for the transfer feature; and then the `draft.md` V1.5 set (Live Activities, navigation, food delivery, shipping, live scores, Touch ID states) and V2 set (smart home, ChatGPT/Gemini/Cursor/VS Code and other agent integrations, third-party app API, public API, developer SDK, user-defined activities). A revisit-trigger list: new macOS release notes, a new public framework, or a documented third-party integration. A short instruction that anything added here must also be removed from V1 scope in `00-product-overview.md` so the two never disagree.
  - **Acceptance:** Every item excluded in `00-product-overview.md` has a matching section here.
  - **QA (CI):** A consistency script cross-checks the exclusion list in `docs/00-product-overview.md` against the section headings here and fails on a mismatch. Evidence: `.omo/evidence/task-15-notchflow-v1.txt`.
  - **Commit:** `docs(backlog): record deferred features and revisit triggers`

- [x] 16. Create `docs/14-glossary-and-conventions.md`
  - **Content:** Terminology, so the codebase and the docs use one vocabulary: island, notch, compact state, expanded state, activity, provider, agent, session, slot, overflow. Naming rules for the product: NotchFlow everywhere; Apple's "Dynamic Island" and "MacBook" marks are not used in the product name, bundle identifier, or App Store metadata, and the reason; how to refer to the concept in prose without infringing. Code conventions: Swift API design guidelines, the `swiftlint`/`swift-format` configuration summary, file and type naming, the one-type-per-file rule, the maximum file length policy, access-control defaults (internal by default, public only across module boundaries), the comment policy (explain why, never what or when; no change-tracking comments, history belongs in git), and the Swift 6 concurrency conventions including the standard pattern for hopping a system callback to `@MainActor`. Git conventions: Conventional Commits with the type list and the scope convention, branch naming, and the pull-request checklist. Documentation conventions: where a new document goes, when to update the index, and the rule that a code change contradicting a document must update the document in the same commit.
  - **Acceptance:** The commit convention matches the one used by every todo in this plan. The comment policy is stated.
  - **QA (CI):** Document contains the Conventional Commits type list and the naming prohibition. Evidence: `.omo/evidence/task-16-notchflow-v1.txt`.
  - **Commit:** `docs(conventions): add glossary, naming and code conventions`

### Wave 1 — Project foundation

- [x] 17. Create the Xcode project and SPM package skeleton
  - Create an Xcode project for a macOS app named `NotchFlow`, deployment target macOS 14.0, Swift 6 language mode with strict concurrency. Create a local Swift package containing three library targets — `NotchFlowCore`, `NotchFlowProviders`, `NotchFlowUI` — plus three matching test targets. `NotchFlowCore` must declare no dependencies beyond Foundation. Wire the app target to depend on all three. Add `.gitignore` for Xcode/SPM artifacts.
  - **Acceptance:** `xcodebuild -scheme NotchFlow build` succeeds; `swift test` runs (zero tests is acceptable at this point); `NotchFlowCore` compiles without importing AppKit.
  - **QA (CI):** Run the build and the test command; capture both exit codes. Evidence: `.omo/evidence/task-17-notchflow-v1.log`.
  - **Commit:** `build: scaffold Xcode project and SPM modules`

- [x] 18. Add MIT `LICENSE`, root `README.md`, `CONTRIBUTING.md`
  - `LICENSE`: MIT, current year, the author's name. `README.md`: what NotchFlow is, a screenshot placeholder, install instructions for both channels marked "coming soon", a build-from-source section, a link to `docs/`, and the license and naming notes. `CONTRIBUTING.md`: how to build, the TDD expectation for core code, the commit convention, and the pull-request checklist.
  - **Acceptance:** `LICENSE` is the verbatim MIT text; `README.md` links to `docs/README.md`.
  - **QA (CI):** Link check on `README.md`; assert `LICENSE` contains the MIT permission clause. Evidence: `.omo/evidence/task-18-notchflow-v1.txt`.
  - **Commit:** `docs: add license, readme and contribution guide`

- [x] 19. Configure `swiftlint` and `swift-format`
  - Add configuration files matching the conventions in `docs/14`. Include a custom rule that flags user-visible string literals in view files, supporting the localization rule.
  - **Acceptance:** Both tools run clean on the current tree.
  - **QA (CI):** `swiftlint --strict` and the format check both exit zero. Evidence: `.omo/evidence/task-19-notchflow-v1.log`.
  - **Commit:** `build: add lint and format configuration`

- [x] 20. Add the architecture guard script
  - A script that fails if `NotchFlowCore` sources import AppKit, SwiftUI, or any provider module — enforcing the dependency rule from `docs/01`.
  - **Acceptance:** The script passes on the current tree and fails when a deliberate violating import is introduced in a scratch file.
  - **QA (CI):** Run both the passing case and the deliberately-failing case; assert exit codes zero and non-zero respectively. Evidence: `.omo/evidence/task-20-notchflow-v1.log`.
  - **Commit:** `build: enforce core module dependency rule`

- [x] 21. Add the forbidden-symbol guard script
  - A script that inspects a built binary and fails if any `MediaRemote` or `MRMediaRemote` symbol or string is present. Wired to run for the `AppStore` configuration only.
  - **Acceptance:** Passes for a stub `AppStore` build; fails for a stub binary containing the symbol.
  - **QA (CI):** Both cases executed with asserted exit codes. Evidence: `.omo/evidence/task-21-notchflow-v1.log`.
  - **Commit:** `build: guard the App Store build against private framework symbols`

- [x] 22. Add the GitHub Actions CI workflow
  - Jobs: build both configurations, run all tests, run lint, run the architecture guard, run the forbidden-symbol guard, and run the docs consistency checks from Wave 0. Pin the runner image and Xcode version. Use `xcbeautify` for readable logs. Upload test results and coverage as artifacts.
  - **Acceptance:** The workflow passes on the current tree.
  - **QA (CI):** The workflow run itself is the evidence; record the run URL and conclusion. Evidence: `.omo/evidence/task-22-notchflow-v1.txt`.
  - **Commit:** `ci: add build, test and guard workflow`

- [x] 23. Configure the app as an accessory app with launch-at-login
  - Set `LSUIElement`, set the activation policy to accessory, add a status item that opens settings and quits, and implement launch-at-login via `SMAppService.mainApp` with a settings toggle that reflects the real registration state.
  - **Acceptance:** The app launches with no Dock icon and no window; the status item appears; toggling launch-at-login changes and correctly reports the registration state.
  - **QA (HW):** Launch, observe no Dock icon, toggle the setting twice, and read back the service status each time. Evidence: screenshots plus status output at `.omo/evidence/task-23-notchflow-v1/`.
  - **Commit:** `feat(app): run as accessory app with launch-at-login`

### Wave 2 — Core, under TDD

- [x] 24. TDD the notch geometry pure functions
  - Write failing tests first for a function computing the notch rectangle from `frame`, `safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`, and a function deciding whether a screen description represents a notched built-in display. Cover a 14" MacBook Pro, a 16" MacBook Pro, a notched Air, a non-notched Mac, a zero-inset external display, and degenerate/empty auxiliary areas. Then implement in `NotchFlowCore`.
  - **Acceptance:** All cases pass; no AppKit import; the functions are total (no crash on degenerate input, returning nil instead).
  - **QA (CI):** `swift test --filter Geometry`; assert all pass and that the degenerate cases return nil rather than trapping. Evidence: `.omo/evidence/task-24-notchflow-v1.log`.
  - **Commit:** `feat(core): add notch geometry calculations`

- [x] 25. TDD the display-selection state machine
  - Failing tests first for the state table in `docs/03`: available screens × user preference → target screen, including automatic mode, an explicit built-in choice, an explicit external choice that is currently connected, the same choice while disconnected (fall back to built-in), and no built-in available (clamshell).
  - **Acceptance:** Every row of the documented table has a test; all pass.
  - **QA (CI):** `swift test --filter DisplaySelection`; assert the test count equals the documented row count. Evidence: `.omo/evidence/task-25-notchflow-v1.log`.
  - **Commit:** `feat(core): add display selection policy`

- [x] 26. TDD `ActivityPriority` and the ordering rule
  - Failing tests first: ordering across all four priority levels, tie-breaking by start time, and stability under repeated sorts.
  - **Acceptance:** Ordering is total and deterministic.
  - **QA (CI):** `swift test --filter Priority`. Evidence: `.omo/evidence/task-26-notchflow-v1.log`.
  - **Commit:** `feat(core): add activity priority ordering`

- [x] 27. TDD the `Activity` protocol and lifecycle types
  - Define `Activity`, its identity and kind types, the lifecycle events, and the auto-dismiss descriptor, driven by tests for a stub conforming type covering start, update, end, and auto-dismiss expiry.
  - **Acceptance:** A conforming stub can be driven through every lifecycle transition; illegal transitions are rejected.
  - **QA (CI):** `swift test --filter ActivityLifecycle`. Evidence: `.omo/evidence/task-27-notchflow-v1.log`.
  - **Commit:** `feat(core): add activity protocol and lifecycle`

- [x] 28. TDD `ActivityProvider` and the registry
  - Define the provider protocol (start observing, stop observing, emit activities) and a registry that starts and stops providers. Tests use fake providers and assert that stopping the registry stops every provider and leaves no retained observer.
  - **Acceptance:** No provider continues to emit after the registry stops; no reference cycles (verified by a deallocation test).
  - **QA (CI):** `swift test --filter ProviderRegistry`; include a test asserting a weak reference is nil after teardown. Evidence: `.omo/evidence/task-28-notchflow-v1.log`.
  - **Commit:** `feat(core): add provider protocol and registry`

- [x] 29. TDD `ActivityManager`
  - Failing tests first for: registration, deduplication by identity, update-in-place, removal on end, ordering by priority, the compact-slot limit and overflow indicator, auto-dismiss firing, and — critically — the transition to empty producing an explicit "become idle" signal exactly once.
  - **Acceptance:** The idle signal fires exactly once per emptying, never while activities remain; the worked example from `docs/05` (music + timer + transfer) produces the documented ordering.
  - **QA (CI):** `swift test --filter ActivityManager`; assert the idle-signal count in the emptying test is exactly one. Evidence: `.omo/evidence/task-29-notchflow-v1.log`.
  - **Commit:** `feat(core): add activity manager`

- [x] 30. TDD the AI agent state machine
  - Failing tests first for the seven states and their legal transitions, including rejection of illegal transitions, coalescing of rapid duplicate updates, and the terminal-state auto-dismiss timing.
  - **Acceptance:** The transition table in `docs/07` is fully covered; illegal transitions are rejected rather than silently accepted.
  - **QA (CI):** `swift test --filter AgentState`. Evidence: `.omo/evidence/task-30-notchflow-v1.log`.
  - **Commit:** `feat(core): add AI agent state machine`

- [x] 31. TDD the IPC message contract
  - Failing tests first for decoding a valid message, rejecting an unknown schema version, rejecting missing required fields, rejecting an oversized payload, rejecting a payload with a disallowed agent id, and safely handling hostile strings (very long, control characters, shell metacharacters, invalid UTF-8). Then implement the codable types and validator in `NotchFlowCore`.
  - **Acceptance:** Every hostile input is rejected without crashing; no received string is ever interpolated into a shell command anywhere in the codebase.
  - **QA (CI):** `swift test --filter IPCMessage`; plus a grep asserting no shell interpolation of message fields. Evidence: `.omo/evidence/task-31-notchflow-v1.log`.
  - **Commit:** `feat(core): add IPC message schema and validation`

- [x] 32. TDD hook-snippet generation
  - Failing tests first for generating the Claude Code settings fragment, the Codex `notify` fragment, and the OpenCode plugin file, including correct escaping of paths containing spaces and quotes, and idempotence (generating twice yields identical output).
  - **Acceptance:** Generated fragments parse as valid JSON/TOML/TypeScript respectively; paths with spaces are correctly escaped.
  - **QA (CI):** `swift test --filter HookGeneration`; additionally pipe each generated fragment through a parser and assert success. Evidence: `.omo/evidence/task-32-notchflow-v1.log`.
  - **Commit:** `feat(core): add agent hook snippet generation`

### Wave 3 — Window and UI

- [x] 33. Implement the screen observer
  - A `NotchFlowProviders` type wrapping `NSApplication.didChangeScreenParametersNotification`, display reconfiguration, and sleep/wake notifications behind the protocol the core tests already fake. Emits a screen-set description into the core's display-selection policy.
  - **Acceptance:** Subscribes on start, fully unsubscribes on stop, and emits on every relevant system event.
  - **QA (HW):** Plug and unplug an external monitor, change resolution, sleep and wake; assert one emission per event in a debug log. Evidence: `.omo/evidence/task-33-notchflow-v1.log`.
  - **Commit:** `feat(display): observe screen configuration events`

- [x] 34. Implement the `NotchPanel` window
  - The `NSPanel` subclass with every property from `docs/04`, positioned by the core geometry functions on the selected screen.
  - **Acceptance:** The panel appears exactly under the notch on the built-in display, never on an external display unless explicitly selected.
  - **QA (HW):** Screenshot on the notched MacBook with the panel visible; measure alignment against the notch edges. Evidence: `.omo/evidence/task-34-notchflow-v1/`.
  - **Commit:** `feat(ui): add the notch panel window`

- [x] 35. Implement the three-state presentation controller
  - Hidden, compact, expanded. Hidden means `orderOut(nil)`. The controller subscribes to the manager's activity set and the idle signal, and orders the window out on idle.
  - **Acceptance:** With no activity the window is not on screen (`isVisible == false`); the transition to hidden happens within the documented delay.
  - **QA (HW):** Start an activity, end it, assert `isVisible` becomes false; capture the window list before and after. Evidence: `.omo/evidence/task-35-notchflow-v1.log`.
  - **Commit:** `feat(ui): add hidden/compact/expanded presentation states`

- [x] 36. Implement click-through and hit-testing
  - `ignoresMouseEvents` true whenever collapsed or hidden; false only while expanded. Hover detection via a passive global monitor with a bounds check, not a polling loop.
  - **Acceptance:** Menu-bar clicks near the notch reach the menu bar while collapsed; the panel receives clicks while expanded.
  - **QA (HW):** Click a menu-bar item adjacent to the notch while an activity is compact; confirm the menu opens. Then expand and confirm the panel handles a click. Evidence: screen recording at `.omo/evidence/task-36-notchflow-v1/`.
  - **Commit:** `feat(ui): add click-through and hover handling`

- [x] 37. Implement the compact view container
  - Renders the ordered activity set as icons/pills hugging the notch, with the overflow indicator when the slot limit is exceeded.
  - **Acceptance:** Matches the layout described in `docs/05` for the three-activity worked example.
  - **QA (HW):** Drive three simultaneous fake activities; screenshot and compare to the documented layout. Evidence: `.omo/evidence/task-37-notchflow-v1/`.
  - **Commit:** `feat(ui): add compact activity view`

- [x] 38. Implement the expanded view container
  - Renders every active activity's expanded view in priority order, with the documented spacing and the primary-action affordance.
  - **Acceptance:** All active activities are visible and ordered correctly.
  - **QA (HW):** Same three-activity scenario, expanded; screenshot compared to `docs/05`. Evidence: `.omo/evidence/task-38-notchflow-v1/`.
  - **Commit:** `feat(ui): add expanded activity view`

- [x] 39. Implement transitions and animation
  - Spring animations for hidden↔compact↔expanded using the parameters in `docs/04`, honouring Reduce Motion, and running no animation while hidden.
  - **Acceptance:** With Reduce Motion enabled, transitions are instant; no animation timer exists while hidden.
  - **QA (HW):** Toggle Reduce Motion and record both behaviours; sample the process during the hidden state and assert no animation work. Evidence: `.omo/evidence/task-39-notchflow-v1/`.
  - **Commit:** `feat(ui): add island state transitions`

- [x] 40. Implement appearance handling
  - Light/dark mode, Reduce Transparency, and the appearance setting from `docs/08`.
  - **Acceptance:** The island is legible in both appearances and with Reduce Transparency enabled.
  - **QA (HW):** Screenshot in all four combinations. Evidence: `.omo/evidence/task-40-notchflow-v1/`.
  - **Commit:** `feat(ui): honour system appearance and accessibility settings`

### Wave 4 — Activity providers

- [x] 41. Define the `MusicProvider` protocol and the shared music activity
  - The protocol, the now-playing model, the transport-command interface, and the SwiftUI compact/expanded views — all independent of which backend supplies the data.
  - **Acceptance:** Views render correctly from a fake provider; no backend-specific type leaks into the view layer.
  - **QA (CI):** Snapshot or structural tests against a fake provider. Evidence: `.omo/evidence/task-41-notchflow-v1.log`.
  - **Commit:** `feat(music): add music provider protocol and views`

- [ ] 42. Implement `AppleScriptMusicProvider` (App Store build)
  - ScriptingBridge against Spotify and Music.app for metadata and transport, driven by the distributed notifications those apps post rather than by polling. Handles the app-not-running and permission-denied cases by producing no activity rather than erroring.
  - **Acceptance:** Track changes in Spotify and Music appear in the island; play/pause/next/previous from the island control the app; denying Automation permission degrades silently.
  - **QA (HW):** With each app in turn, change track, use each transport control, then revoke Automation permission and confirm graceful degradation. Evidence: `.omo/evidence/task-42-notchflow-v1/`.
  - **Commit:** `feat(music): add AppleScript music backend`

- [x] 43. Implement `MediaRemoteMusicProvider` (Direct build only)
  - System-wide now-playing observation, compiled only into the `Direct` configuration, resolved dynamically, never linked into `AppStore`.
  - **Acceptance:** The App Store build contains no MediaRemote symbol (todo 21's guard passes); the Direct build shows now-playing for a media app that the AppleScript backend cannot see.
  - **QA (HW + CI):** CI runs the symbol guard against the App Store build. On hardware, play audio in a browser and confirm the Direct build shows it while the App Store build does not. Evidence: `.omo/evidence/task-43-notchflow-v1/`.
  - **Commit:** `feat(music): add MediaRemote backend for direct builds`

- [x] 44. Wire the build-time music backend selection
  - Compilation condition selects the backend; a single composition-root line differs between configurations.
  - **Acceptance:** Both configurations build and run with the correct backend active; the active backend is visible in the about pane for support purposes.
  - **QA (CI):** Build both configurations and assert the reported backend name differs. Evidence: `.omo/evidence/task-44-notchflow-v1.log`.
  - **Commit:** `feat(music): select music backend per build configuration`

- [x] 45. Implement the timer and stopwatch provider
  - NotchFlow's own countdown and stopwatch, started from the expanded island or settings. The only provider owning a repeating tick: a `DispatchSourceTimer` with generous leeway, created when a time activity becomes visible and cancelled when it is not.
  - **Acceptance:** The displayed time is accurate within the documented tolerance; no timer source exists while no time activity is visible.
  - **QA (HW):** Run a countdown, confirm accuracy against a reference clock, end it, and confirm via sampling that no timer source remains. Evidence: `.omo/evidence/task-45-notchflow-v1.log`.
  - **Commit:** `feat(timer): add countdown and stopwatch activities`

- [x] 46. Implement the screen recording indicator provider
  - Observes the publicly available screen-capture signal documented in `docs/12` and produces a recording activity with elapsed time.
  - **Acceptance:** Starting a screen recording produces the activity; stopping ends it. Cases the public API cannot detect are documented rather than faked.
  - **QA (HW):** Start and stop a screen recording; observe the activity appear and disappear. Evidence: `.omo/evidence/task-46-notchflow-v1/`.
  - **Commit:** `feat(recording): add screen recording indicator`

- [x] 47. Implement the audio recording indicator provider
  - Observes microphone-in-use via the mechanism documented in `docs/12`, without NotchFlow itself requesting microphone permission.
  - **Acceptance:** The activity appears while another app records; NotchFlow never prompts for microphone access.
  - **QA (HW):** Start a recording in another app; confirm the activity and confirm no microphone prompt from NotchFlow. Evidence: `.omo/evidence/task-47-notchflow-v1/`.
  - **Commit:** `feat(recording): add audio recording indicator`

- [x] 48. Implement the charging provider
  - `IOPSNotificationCreateRunLoopSource`-driven state machine: plugged in → charging → fully charged → auto-dismiss. Never displays a persistent battery percentage.
  - **Acceptance:** Connecting power shows charging; reaching full shows fully charged then dismisses; no persistent percentage is ever rendered.
  - **QA (HW):** Connect and disconnect power; observe both transitions. Assert by code review and by screenshot that no percentage is persistently displayed. Evidence: `.omo/evidence/task-48-notchflow-v1/`.
  - **Commit:** `feat(power): add charging activity`

- [x] 49. Wire all providers into the registry with per-provider enablement
  - Each provider is started only when its setting is enabled and stopped immediately when disabled.
  - **Acceptance:** Disabling a provider in settings stops its observation within the documented delay and removes its activities.
  - **QA (HW):** Toggle each provider off and on; confirm observation stops and starts. Evidence: `.omo/evidence/task-49-notchflow-v1.log`.
  - **Commit:** `feat(providers): wire providers to settings-driven enablement`

### Wave 5 — AI integration

- [x] 50. Implement the URL-scheme receiver
  - Register the custom scheme, parse and validate incoming URLs through the core validator, and reject anything invalid without side effects.
  - **Acceptance:** A valid `open -g` invocation produces an agent activity; malformed and hostile inputs are rejected silently.
  - **QA (CI + HW):** Unit tests for parsing; on hardware, invoke the scheme for each of the seven states and one malformed case. Evidence: `.omo/evidence/task-50-notchflow-v1.log`.
  - **Commit:** `feat(ai): add URL scheme event receiver`

- [x] 51. Implement the loopback listener
  - Bind `127.0.0.1` on an ephemeral port, publish the port to the documented discovery location, enforce the size and rate limits, and validate every payload. Starts only when at least one AI integration is enabled; stops when the last is disabled.
  - **Acceptance:** Bound to loopback only (verified by an external-interface connection attempt failing); no socket exists while all integrations are disabled.
  - **QA (HW):** Confirm the listening socket's bind address; attempt a connection from a non-loopback address and assert refusal; disable all integrations and assert the socket is gone. Evidence: `.omo/evidence/task-51-notchflow-v1.log`.
  - **Commit:** `feat(ai): add loopback event listener`

- [x] 52. Implement the AI activity and its views
  - Compact and expanded renderings for all seven states, the agent label, the tool name, optional progress, and the primary action that activates the originating app.
  - **Acceptance:** Every state renders distinctly; the completed and error states auto-dismiss per `docs/05`.
  - **QA (CI):** Structural tests per state; on hardware, drive all seven states and screenshot each. Evidence: `.omo/evidence/task-52-notchflow-v1/`.
  - **Commit:** `feat(ai): add AI agent activity and views`

- [ ] 53. Implement agent detection
  - Detect which of Claude Code, Codex CLI, and OpenCode are present, in a way that works in both builds (and degrades to "unknown, offer manual setup" when the sandbox prevents inspection).
  - **Acceptance:** Present agents are detected in the Direct build; the App Store build offers manual setup rather than failing.
  - **QA (HW):** Run in both configurations with at least one agent installed; confirm the expected path in each. Evidence: `.omo/evidence/task-53-notchflow-v1.log`.
  - **Commit:** `feat(ai): detect installed agents`

- [ ] 54. Implement the Claude Code hook installer
  - Shows the exact proposed change, requires explicit consent, backs up the existing settings file, writes the async hook configuration, and supports full uninstall restoring the backup.
  - **Acceptance:** Installing then uninstalling leaves the settings file byte-identical to the original; the installed hook is async and cannot block the agent.
  - **QA (HW):** Install, diff, run a Claude Code session and observe states in the island, uninstall, and diff against the original. Evidence: `.omo/evidence/task-54-notchflow-v1/`.
  - **Commit:** `feat(ai): add Claude Code hook installer`

- [ ] 55. Implement the Codex CLI hook installer
  - Same consent, backup, and uninstall contract, targeting the `notify` setting.
  - **Acceptance:** Round-trip install/uninstall is byte-identical; a Codex session drives the island.
  - **QA (HW):** As todo 54, with Codex. Evidence: `.omo/evidence/task-55-notchflow-v1/`.
  - **Commit:** `feat(ai): add Codex CLI hook installer`

- [ ] 56. Implement the OpenCode plugin installer
  - Writes the plugin file with the same consent, backup, and uninstall contract.
  - **Acceptance:** Round-trip is clean; an OpenCode session drives the island.
  - **QA (HW):** As todo 54, with OpenCode. Evidence: `.omo/evidence/task-56-notchflow-v1/`.
  - **Commit:** `feat(ai): add OpenCode plugin installer`

- [ ] 57. Implement the manual-setup fallback UI
  - When automatic installation is unavailable or declined, display the exact snippet with a copy button and instructions.
  - **Acceptance:** The displayed snippet is identical to what the installer would have written.
  - **QA (CI):** Assert the UI snippet and the installer output are produced by the same generator and are string-equal. Evidence: `.omo/evidence/task-57-notchflow-v1.log`.
  - **Commit:** `feat(ai): add manual hook setup fallback`

- [ ] 58. Implement per-agent and per-event toggles
  - Enable/disable each agent and each event class per `docs/08`; disabled events are dropped at the receiver, not merely hidden.
  - **Acceptance:** A disabled event class produces no activity and no UI work.
  - **QA (HW):** Disable one event class, emit it, and assert no activity is created. Evidence: `.omo/evidence/task-58-notchflow-v1.log`.
  - **Commit:** `feat(ai): add per-agent and per-event controls`

### Wave 6 — Settings, localization, polish

- [ ] 59. Implement the settings store
  - Typed `UserDefaults` wrapper with the exact keys and defaults from `docs/08`, plus the migration hook.
  - **Acceptance:** Every documented setting round-trips; first launch produces exactly the documented defaults.
  - **QA (CI):** Tests over a clean defaults domain asserting each default. Evidence: `.omo/evidence/task-59-notchflow-v1.log`.
  - **Commit:** `feat(settings): add typed preferences store`

- [ ] 60. Implement the settings window
  - All panes from `docs/08`: general, display, activities, AI integrations, about.
  - **Acceptance:** Every documented setting is reachable and functional.
  - **QA (HW):** Walk every pane and exercise every control; screenshot each pane. Evidence: `.omo/evidence/task-60-notchflow-v1/`.
  - **Commit:** `feat(settings): add settings window`

- [ ] 61. Implement the first-run onboarding flow
  - Welcome, permission explanation, agent detection and hook offer, done — per `docs/08`.
  - **Acceptance:** Shown exactly once on first launch; skippable; never requests a permission the user has not opted into.
  - **QA (HW):** Reset the defaults domain and launch; confirm the flow and that no permission prompt appears unless a feature is enabled. Evidence: `.omo/evidence/task-61-notchflow-v1/`.
  - **Commit:** `feat(onboarding): add first-run setup flow`

- [ ] 62. Add the String Catalog and extract every user-visible string
  - Create the `.xcstrings` catalog; move every user-visible literal into it; add the lint rule enforcement from todo 19.
  - **Acceptance:** The lint rule reports zero hardcoded user-visible strings.
  - **QA (CI):** `swiftlint --strict` passes with the custom rule enabled. Evidence: `.omo/evidence/task-62-notchflow-v1.log`.
  - **Commit:** `feat(i18n): add string catalog and extract strings`

- [ ] 63. Add the Turkish localization
  - Translate every catalog entry; ensure date, duration, and number formatting is locale-driven rather than hardcoded.
  - **Acceptance:** No untranslated key remains; the UI is legible in Turkish without truncation.
  - **QA (CI + HW):** A script asserts zero missing translations; on hardware, run in Turkish and screenshot every surface. Evidence: `.omo/evidence/task-63-notchflow-v1/`.
  - **Commit:** `feat(i18n): add Turkish localization`

- [ ] 64. Implement the permission request flow
  - Lazy, explained, per-feature requests with graceful degradation on denial, per `docs/09`.
  - **Acceptance:** No permission is requested at launch; denying any permission disables only the dependent feature, with an explanatory state in settings.
  - **QA (HW):** Fresh install, launch, confirm no prompts; enable each feature in turn and confirm one explained prompt each; deny each and confirm graceful degradation. Evidence: `.omo/evidence/task-64-notchflow-v1/`.
  - **Commit:** `feat(permissions): add lazy permission flow with graceful degradation`

- [ ] 65. Add the app icon and visual assets
  - App icon at all required sizes, status item symbol, and any activity glyphs, in light and dark variants.
  - **Acceptance:** No missing icon size; the status item renders correctly in both appearances and in the menu bar's reduced contrast.
  - **QA (CI + HW):** Asset validation in the build; screenshots of the status item in both appearances. Evidence: `.omo/evidence/task-65-notchflow-v1/`.
  - **Commit:** `feat(assets): add app icon and symbols`

### Wave 7 — Performance, packaging, distribution

- [ ] 66. Implement the performance measurement script
  - A script that launches the app, waits for idle, samples for the documented duration, and asserts the `docs/02` thresholds for CPU, wakeups, and memory, failing non-zero on a breach.
  - **Acceptance:** The script runs unattended and produces a machine-readable result plus a human summary.
  - **QA (HW):** Run on the notched MacBook with no activities; capture the report. Evidence: `.omo/evidence/task-66-notchflow-v1/`.
  - **Commit:** `test(perf): add idle cost measurement script`

- [ ] 67. Meet the idle performance budget
  - Profile and fix until the script from todo 66 passes. Expected work: eliminating any retained observer, confirming the window is truly ordered out, removing incidental timers, and verifying App Nap cooperation.
  - **Acceptance:** Todo 66's script passes on real hardware with every provider enabled and no activity present.
  - **QA (HW):** The script's passing report, plus an Instruments capture confirming no periodic work. Evidence: `.omo/evidence/task-67-notchflow-v1/`.
  - **Commit:** `perf: meet the idle cost budget`

- [ ] 68. Author both entitlements files and both build configurations
  - Per `docs/09` and `docs/10`, with the guards from todos 20 and 21 wired into both.
  - **Acceptance:** Both configurations build; the App Store configuration passes the symbol guard; each entitlement present is justified in `docs/09`.
  - **QA (CI):** Build both; run both guards; diff the effective entitlements against the documented table. Evidence: `.omo/evidence/task-68-notchflow-v1.log`.
  - **Commit:** `build: add per-configuration entitlements`

- [ ] 69. Write the privacy policy and App Store metadata
  - Privacy policy file in the repository, plus the App Store description, keywords, review notes explaining the overlay window and the absence of private API, and the privacy nutrition label answers — all localized.
  - **Acceptance:** The privacy policy matches the actual data behaviour described in `docs/09`; review notes address the overlay question directly.
  - **QA (CI):** Consistency check between the privacy policy claims and the entitlements table. Evidence: `.omo/evidence/task-69-notchflow-v1.txt`.
  - **Commit:** `docs(store): add privacy policy and App Store metadata`

- [ ] 70. Implement the Direct build packaging pipeline — BLOCKED-ON-MEMBERSHIP for signing
  - Script producing a `.dmg`: build, sign with Developer ID, enable the hardened runtime, submit to `notarytool`, staple, and package. Until the membership exists, the script runs end-to-end with ad-hoc signing and clearly reports the signing steps as skipped.
  - **Acceptance:** The script produces a mountable `.dmg` today; every membership-dependent step is explicitly reported as skipped rather than silently omitted.
  - **QA (HW):** Run the script; mount the `.dmg`; confirm the skipped-step report. Evidence: `.omo/evidence/task-70-notchflow-v1/`.
  - **Commit:** `build: add direct distribution packaging pipeline`

- [ ] 71. Prepare the Homebrew Cask definition — BLOCKED-ON-MEMBERSHIP for submission
  - The cask file with the correct stanzas, plus the submission checklist. Submission itself waits on a notarized release.
  - **Acceptance:** The cask file is syntactically valid and passes local audit against a locally-produced artifact.
  - **QA (CI):** Run the cask audit; capture output. Evidence: `.omo/evidence/task-71-notchflow-v1.log`.
  - **Commit:** `build: add homebrew cask definition`

- [ ] 72. Prepare the App Store submission — BLOCKED-ON-MEMBERSHIP
  - Archive the App Store configuration, run the full validation locally, and assemble screenshots and metadata. Actual upload waits on the membership.
  - **Acceptance:** A validated archive exists locally with zero validation errors; the screenshot set is complete for every required size.
  - **QA (HW):** Produce the archive and run validation; capture the report. Evidence: `.omo/evidence/task-72-notchflow-v1/`.
  - **Commit:** `build: prepare App Store submission artifacts`

- [ ] 73. Add the release workflow
  - A tag-triggered GitHub Actions workflow producing the `.dmg`, attaching it to a release, and generating release notes. Signing steps are conditional on the secrets existing, so the workflow is usable before and after the membership.
  - **Acceptance:** A dry-run on a test tag produces an artifact; the workflow does not fail merely because signing secrets are absent.
  - **QA (CI):** Trigger on a test tag; record the run conclusion and artifact. Evidence: `.omo/evidence/task-73-notchflow-v1.txt`.
  - **Commit:** `ci: add release workflow`

- [ ] 74. Reconcile documentation with the implementation
  - Re-read all 15 documents against the shipped code and correct every divergence. Update `docs/12` with anything learned during implementation, and update `docs/13` if any deferred item's status changed.
  - **Acceptance:** No document contradicts the code. Every API row in `docs/12` reflects what was actually built.
  - **QA (CI):** The docs consistency scripts pass; a reviewer diff of each document against the corresponding implementation is recorded. Evidence: `.omo/evidence/task-74-notchflow-v1.txt`.
  - **Commit:** `docs: reconcile specification with implementation`

## Final verification wave

- [ ] F1. Full clean build of both configurations from a fresh checkout
  - Clone into a clean directory, build `AppStore` and `Direct`, and run all guards and lints. Assert zero warnings in the app targets.
  - Evidence: `.omo/evidence/final-F1-notchflow-v1.log`

- [ ] F2. Complete automated test suite with coverage
  - Run every test target; assert all pass and that `NotchFlowCore` line coverage meets the threshold set in `docs/11`.
  - Evidence: `.omo/evidence/final-F2-notchflow-v1.log`

- [ ] F3. Hardware matrix — single built-in display
  - The numbered checklist from `docs/11` on the notched MacBook alone: notch alignment, all three states, click-through, every provider, all seven AI states, light and dark, Reduce Motion, Reduce Transparency. One screenshot per step.
  - Evidence: `.omo/evidence/final-F3-notchflow-v1/`

- [ ] F4. Hardware matrix — multi-monitor and display transitions
  - With one external monitor: island stays on the built-in display by default; explicit external selection works; unplugging the selected display falls back correctly; resolution change repositions correctly; mirroring behaves sanely.
  - Evidence: `.omo/evidence/final-F4-notchflow-v1/`

- [ ] F5. Hardware matrix — power and lifecycle transitions
  - Sleep and wake, lid close and open, clamshell with an external display, user switch, and charging connect/disconnect. Assert the island recovers correctly and no duplicate or orphaned activity remains after each.
  - Evidence: `.omo/evidence/final-F5-notchflow-v1/`

- [ ] F6. Hardware matrix — full-screen and Spaces behaviour
  - Island visibility and behaviour over a full-screen app, across multiple Spaces, and during Mission Control.
  - Evidence: `.omo/evidence/final-F6-notchflow-v1/`

- [ ] F7. End-to-end AI round-trip for all three agents
  - Install each hook, run a real session per agent, observe every reachable state in the island, click through to the originating app, then uninstall and confirm each config file is byte-identical to its backup.
  - Evidence: `.omo/evidence/final-F7-notchflow-v1/`

- [ ] F8. Idle performance verification
  - Run the todo 66 script with every provider enabled and no activity, for the full documented duration, and assert every `docs/02` threshold.
  - Evidence: `.omo/evidence/final-F8-notchflow-v1/`

- [ ] F9. Privacy and entitlement audit
  - Inspect the effective entitlements of both built binaries; assert they match `docs/09` exactly with nothing extra. Confirm no network connection other than the loopback listener occurs during a full session, using a network monitor.
  - Evidence: `.omo/evidence/final-F9-notchflow-v1/`

- [ ] F10. Scope and guardrail audit
  - Confirm every Must-have is present and every Must-NOT-have is absent: no MediaRemote symbol in the App Store build, no polling loop, no screen scraping, no third-party runtime dependency, no deferred feature partially implemented, no undocumented setting.
  - Evidence: `.omo/evidence/final-F10-notchflow-v1.txt`

## Commit strategy

- Conventional Commits, exactly as specified in `docs/14` and in each todo's `Commit:` line.
- Types in use: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.
- Scope is the feature area (`music`, `ai`, `ui`, `display`, `settings`, `i18n`, `perf`, `permissions`) or the layer (`core`, `app`).
- One commit per todo. Do not batch todos into a single commit; do not split one todo across commits unless a genuine fix follows.
- Subject in the imperative, lowercase, no trailing period, at most 50 characters. Body only where the "why" is not obvious from the subject, wrapped at 72.
- No change-tracking comments in source. History lives in git.
- Wave 0 lands as a single documentation series before code begins.

## Success criteria

1. `docs/` contains 15 complete, mutually consistent documents, and the consistency scripts pass.
2. Both build configurations build clean from a fresh checkout with zero warnings in the app targets.
3. The full test suite passes, `NotchFlowCore` meets its coverage threshold, and the core contains no AppKit import.
4. The App Store build contains no private-framework symbol, verified by an automated guard in CI.
5. The island appears correctly aligned under the notch on the built-in display and never migrates to an external display without an explicit user choice.
6. With no activity present and every provider enabled, measured idle CPU, wakeups, and memory are within the `docs/02` budget on real hardware.
7. Music now-playing and transport control work in the App Store build for Spotify and Apple Music, and in the Direct build for any media source.
8. Timer, stopwatch, screen recording, audio recording, and charging activities each appear and dismiss correctly on real hardware.
9. Multiple simultaneous activities render in the documented priority order in both compact and expanded states.
10. All three AI agents drive all seven states end to end, and every hook installer round-trips byte-identically.
11. No permission is requested at launch; every permission is explained before being requested and every denial degrades gracefully.
12. Every user-visible string is localized, with English and Turkish complete.
13. A `.dmg` is produced by an automated pipeline, and the App Store archive validates locally — with the signing and submission steps ready to run the moment the Apple Developer Program membership exists.
14. Every deferred feature is absent from the app and documented in `docs/13-deferred-backlog.md` with a revisit trigger.
