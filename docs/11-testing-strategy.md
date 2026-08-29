# Testing Strategy

This document specifies the TDD boundary, the testing framework and its coexistence policy, how event-driven and hardware-dependent code gets tested without real hardware, the two-column CI/hardware verifiability matrix for the whole app, the numbered manual hardware checklist, the CI configuration, and the definition of done for a todo. It is a design specification, nothing in this folder is code.

## The TDD boundary

TDD is mandatory, not aspirational, for two categories of code:

- **`NotchFlowCore`**, in its entirety. Per `01-architecture.md`, this module imports nothing but Foundation, so every type in it, the `Activity` protocol, `ActivityManager`, `ActivityPriority` resolution, the AI agent state machine, IPC message types, and the notch geometry math, is pure logic with no window server, no display, and no permission dependency. There is no excuse for writing this code before its test.
- **Every pure function elsewhere**, regardless of which module it lives in. If a function's output depends only on its inputs (the notch rectangle formula in `03-display-and-notch.md` is the canonical example), it gets a test written first, wherever it's declared.

Tests-after is acceptable, not just tolerated, for AppKit and SwiftUI glue: `NSPanel` positioning code, view hierarchies, and the thin translation layer inside a provider that turns a system callback into an `ActivityManager` call. This code is often awkward or impossible to unit test in isolation (see the CI-vs-hardware notes throughout `06-activity-providers.md`), and forcing a test-first discipline onto it produces tests that assert the mock was called rather than that behavior is correct. The reason for the split is simple: TDD pays off in proportion to how deterministic and isolatable the code under test is. `NotchFlowCore` and pure functions are maximally deterministic and isolatable; AppKit/SwiftUI glue is neither, so the same discipline applied there buys process, not confidence.

## Framework choice: Swift Testing

NotchFlow's tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`) as the primary framework for all new test code, in both `NotchFlowCore` and everywhere else. Swift Testing's `@Test(arguments:)` parameterization is a direct fit for the table-driven tests this document describes below (the geometry table, the priority table, the IPC rejection cases), replacing what would otherwise be repetitive `XCTestCase` subclasses with one parameterized function per behavior.

**Coexistence with XCTest:** UI-level tests that need `XCUIApplication` (launch, screenshot, accessibility-tree interaction) stay on XCTest, because Swift Testing does not yet replace XCTest's UI automation surface. Both frameworks run in the same `xcodebuild test` invocation and report through the same `xcresult` bundle, so there is no separate CI step and no dual coverage pipeline to maintain. There is no plan to migrate existing XCTest UI tests to Swift Testing; the policy is additive, not a rewrite: new logic tests are Swift Testing, UI automation stays XCTest, and neither framework is deprecated for its respective lane.

## Testing event-driven code without the real event source

Every system dependency in `NotchFlowProviders` sits behind a protocol NotchFlow defines, never behind a direct call to the system API. A test then supplies a fake conforming to that protocol, one that emits the same events the real system would, on the test's own schedule instead of the OS's. This is the same seam described per-provider in `06-activity-providers.md` (a fake `MediaRemote` info dictionary, a fake ScriptingBridge interface); this section states the pattern once, generally.

**Worked example: a screen-parameters change.** The real dependency is `NSApplication.didChangeScreenParametersNotification`, which fires when a display is connected, disconnected, or its resolution or scaling changes. Wrapping it:

```
protocol ScreenChangeObserving {
    var screenChanges: AsyncStream<Void> { get }
}
```

The production conformance wraps `NotificationCenter` and yields on every `didChangeScreenParametersNotification`. The test conformance is a `FakeScreenChangeObserver` whose `screenChanges` stream is backed by a `AsyncStream.Continuation` the test holds directly:

1. Construct the component under test (the notch-locating logic) with the fake observer injected.
2. Call `continuation.yield(())` to simulate a monitor being unplugged.
3. Await the component's next published notch rectangle.
4. `#expect` it matches the value computed by the pure `notchRect` function (see below) for the new, post-change `NSScreen` state the test also fakes.

No real display change, no real `NSScreen`, and no real notification center delivery are needed to prove the component reacts correctly to the event; the fake proves the wiring, and the pure function proves the math.

## Testing notch geometry without a notch

`notchRect(frame:safeAreaInsets:auxiliaryTopLeftArea:auxiliaryTopRightArea:)`, specified in `03-display-and-notch.md`, takes exactly four values and returns a `CGRect?`. None of those four values requires a physical notch, a display, or even a running app: they're passed as literal structs. The test table therefore runs identically on any Mac, notched or not, and in CI with no display attached at all.

| Case | `frame` | `safeAreaInsets.top` | Auxiliary areas | Expected result |
|---|---|---|---|---|
| 14" MacBook Pro | `(0, 0, 1512, 982)` | `37` | Both non-nil, matching the 14" notch width | The computed rect, matching Apple's published notch dimensions for this model |
| 16" MacBook Pro | `(0, 0, 1728, 1117)` | `37` | Both non-nil, matching the 16" notch width | The computed rect, wider than the 14" case, same height |
| Notched MacBook Air (M2/M3) | `(0, 0, 1470, 956)` | `37` | Both non-nil | The computed rect for the Air's notch geometry |
| Non-notched Mac (external display, older MacBook) | Any valid frame | `0` | Both `nil` | `nil`, no fallback math attempted |
| Degenerate: one auxiliary area `nil`, the other populated | Any valid frame | `37` | One `nil`, one non-nil | `nil` (the function requires both to be non-nil to compute a rect, per `03-display-and-notch.md`) |
| Degenerate: `auxiliaryTopRightArea.minX < auxiliaryTopLeftArea.maxX` | Any valid frame | `37` | Both non-nil, but with an inverted or overlapping relationship | `nil` or a zero-width rect, never a negative-width `CGRect` |

Every row is a data point in one `@Test(arguments:)` function; there is no reason to write six separate test functions for one pure function.

## The verifiability matrix

Every testable surface in NotchFlow falls into exactly one of two columns: it runs in CI on every commit, headless and unattended, or it can only be exercised by a person on a real Mac with real hardware, real permissions, and real peripherals attached. Conflating the two, claiming CI coverage for something that actually needs a human and a notch, is the single most common way a "tested" feature ships broken.

| CI | Hardware (HW) |
|---|---|
| Core logic (`ActivityManager` register/update/end lifecycle) | Actual notch alignment on real hardware (the rendered island sits flush against the real notch, not just the computed rect) |
| Activity ordering and priority resolution | Panel level over a full-screen app (the island stays visible, or correctly hides, per the full-screen policy) |
| Notch geometry math (the table above) | Panel behavior across Spaces and Mission Control |
| The AI agent state machine (legal and illegal transitions) | Monitor hotplug and unplug |
| IPC payload parsing and rejection cases (malformed envelope, unknown `agentId`, stale `timestamp`) | Sleep and wake |
| Hook-script generation (the installer's output for Claude Code, Codex CLI, OpenCode) | Lid close and open |
| Localization completeness (every String Catalog key has no untranslated or stale entries) | Clamshell mode |
| Build success for both configurations (`AppStore` and `Direct` schemes both compile and link) | Resolution and scaling change |
| The forbidden-symbol build guard (`nm`/`strings` scan for `MediaRemote` on the `AppStore` scheme) | Real music apps (Spotify, Apple Music, and, on the Direct build, a third-party player via `MediaRemote`) |
| `swiftlint` and `swift-format` gates | Permission dialogs and denial paths (Screen Recording, Microphone, Apple Events, each accepted and each denied) |
| `ActivityManager` auto-dismiss timers, driven by a fake clock, never a real `sleep` | Real agent hook round-trip (an actual Claude Code, Codex, or OpenCode session driving the IPC protocol end to end) |
| Priority-forced panel visibility (a `high`-priority activity registering while the panel is hidden) | Idle CPU and wakeup measurement (the `02-performance-contract.md` budget, which needs `powermetrics` on real hardware) |

This table is exhaustive for V1: every feature in `00-product-overview.md`'s V1 list has at least one row in each column, either directly (music, timers, recording, charging, AI status each have a CI-testable core and an HW-only integration point) or through a shared mechanism (geometry math and the performance contract apply across all of them).

## The hardware checklist

The HW column above says what needs a human; this checklist says how to run that human pass. Each step is numbered, states the exact action, states the expected observation, and requires a screenshot as evidence. A checklist item that isn't observable, or that isn't backed by a screenshot in the QA evidence file, isn't done.

1. **Single-screen MacBook.** Launch NotchFlow with only the built-in display attached. Expected: the island renders flush against the notch, compact state by default. Screenshot: the notch area at rest.
2. **MacBook + one external monitor.** Attach one external display. Expected: the island stays anchored to the built-in display's notch, not the external monitor. Screenshot: both displays visible, island only on the built-in one.
3. **MacBook + two external monitors.** Attach a second external display. Expected: same anchoring behavior as step 2, with no crash or duplicate island. Screenshot: three-display layout with a single island.
4. **Monitor hotplug.** With NotchFlow running and an external monitor already attached, plug in a second one. Expected: the island does not flicker, relocate, or disappear during the hotplug. Screenshot: before and after the plug event.
5. **Monitor unplug.** Disconnect an external monitor while NotchFlow is running. Expected: no crash, the island remains correctly anchored to the built-in display. Screenshot: the state immediately after unplug.
6. **Sleep to wake.** Put the Mac to sleep with an activity active (for example, a running timer), then wake it. Expected: the activity's displayed state is consistent with elapsed real time, not frozen at the pre-sleep value. Screenshot: the island immediately after wake.
7. **Lid close and open.** Close the lid with an external display attached (clamshell-eligible configuration), then reopen it. Expected: the island survives the display reconfiguration that lid close/open triggers. Screenshot: post-reopen state.
8. **Clamshell mode.** Close the lid with an external display attached and the Mac otherwise awake (external-display-only operation). Expected: since there is no built-in notch visible, NotchFlow enters its documented no-notch fallback rather than crashing or drawing an island with no anchor. Screenshot: the external display with no island artifact.
9. **User session switch.** Switch to a different macOS user account and back. Expected: NotchFlow's state for the original user is intact on return; no activity leaks between sessions. Screenshot: state before switch and after return.
10. **Full-screen application.** Enter full-screen mode in an app (for example, a video player). Expected: the island's panel level behaves per the full-screen policy (visible or hidden, matching spec, never rendered incorrectly beneath the full-screen content). Screenshot: full-screen app with the island in its specified state.
11. **Resolution and scaling change.** Change the built-in display's resolution or scaling in System Settings. Expected: the notch rectangle recalculates correctly at the new scale, no misalignment. Screenshot: before and after the scaling change.
12. **Different MacBook models.** Repeat the single-screen check (step 1) on each notched model available for testing (14" and 16" MacBook Pro, notched MacBook Air). Expected: correct alignment on every model, per the geometry table above. Screenshot: one per model.
13. **Dark mode and light mode.** Toggle the system appearance. Expected: the island's contents remain legible and correctly styled in both. Screenshot: one per appearance mode.
14. **Low battery.** Let the battery drop below the OS's low-battery threshold, or simulate it if the test rig allows. Expected: the charging activity (if any) and the rest of the UI remain correct; no unrelated behavior change. Screenshot: low-battery state with NotchFlow running.
15. **Many simultaneous activities.** Trigger music, a timer, a recording indicator, and an AI status update at the same time. Expected: the overflow and priority-ordering rules from `05-activity-model.md` are visibly correct, the highest-priority activities are the ones shown when not everything fits. Screenshot: the expanded view with all activities visible or correctly deprioritized.
16. **Permission dialogs and denial paths.** For each permission-gated provider (Screen Recording, Microphone, Apple Events), trigger the request once, accept it, and separately, on a fresh state, deny it. Expected: acceptance enables the activity; denial produces the documented degraded behavior, never a crash or a silently stuck state. Screenshot: the system permission dialog and the resulting NotchFlow state for both accept and deny.
17. **Real agent hook round-trip.** Run an actual Claude Code, Codex CLI, or OpenCode session with the hook installed, and drive it through at least one full state sequence (`thinking` through `completed`). Expected: every state the agent state machine defines renders as specified in `07-ai-integration.md`. Screenshot: the expanded AI activity view at two or more distinct states in the sequence.
18. **Idle CPU and wakeup measurement.** With no activity active and no user interaction for at least 10 seconds, run the `02-performance-contract.md` `powermetrics` sampler. Expected: every budget row in that document's table holds. Screenshot: the `powermetrics` output or the Activity Monitor Energy tab.

## CI configuration

- **Runner image and Xcode version policy.** CI runs on the latest GitHub-hosted macOS runner image that ships the Xcode version NotchFlow targets as its minimum supported toolchain; the Xcode version is pinned explicitly in the workflow file (via `xcode-select` or the runner's Xcode-selection action) rather than left to whatever the image defaults to, so a runner image update can never silently change which compiler and SDK build the app.
- **The `xcodebuild test` invocation.** Both schemes are tested independently: `xcodebuild test -scheme "NotchFlow (App Store)" -destination "platform=macOS"` and the equivalent for `NotchFlow (Direct)`, since the two configurations link different music providers (`10-build-and-distribution.md`) and a test that only runs against one scheme could miss a `Direct`-only or `AppStore`-only regression.
- **Coverage reporting.** `xcodebuild test` runs with code coverage enabled (`-enableCodeCoverage YES`), and the resulting `xcresult` bundle is processed into a coverage report uploaded as a CI artifact. Coverage is tracked, not gated on a hard percentage threshold: `NotchFlowCore` and pure functions are expected to sit near 100% given the TDD boundary above, while AppKit/SwiftUI glue is expected to sit lower, and a single blended threshold would either be meaningless for the first case or punitive for the second.
- **`swiftlint` and `swift-format` gates.** Both run as a build phase (per `14-glossary-and-conventions.md`) and also as an explicit, separate CI step that fails the workflow on any violation, so a local build-phase warning that a contributor ignores still blocks the PR.
- **`xcbeautify` for readable logs.** The raw `xcodebuild test` output is piped through `xcbeautify` in CI so a failing test's location and message are readable in the GitHub Actions log without scrolling through raw `xcodebuild` noise.

## Definition of done for a todo

A todo in this plan is done only when all of the following hold:

- Every acceptance criterion stated in the todo's own entry is met, verified by inspecting the actual artifact (file, test output, build log), not by trusting a description of it.
- Every CI-column item the todo touches has a passing automated test in the same change; there is no "will add tests later" state for CI-testable logic.
- Every HW-column item the todo touches, if any, has a completed hardware-checklist entry with a screenshot in the corresponding `.omo/evidence/` file.
- `swiftlint`, `swift-format`, and the architecture guard (where applicable) all pass with no suppressed or ignored violations.

## Anti-patterns (forbidden, no exceptions)

- **No test that asserts nothing.** A test that calls a function and checks only that it didn't throw, with no assertion on the actual return value or side effect, provides no coverage and must not be counted as one.
- **No grep-as-verification for behavioral claims.** Confirming a string like `"@Test"` or a function name exists in a file is not the same as confirming the behavior it implements is correct; a behavioral claim is verified by running the test and reading its result, never by searching source text for the shape of a test.
- **No completion claimed on a worker's self-report.** A todo is marked done after its evidence file, its test output, and, where applicable, its screenshots are independently inspected, not because whoever implemented it reported success.
