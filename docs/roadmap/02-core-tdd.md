# Phase 2 — Core Under TDD

**Status:** NOT STARTED
**Todos:** 24–32 (Wave 2)
**Depends on:** Phase 1, specifically todo 17 — the SPM skeleton must exist so `NotchFlowCore` and its test target are buildable.
**Unblocks:** Phase 3 (window/UI needs the core types), Phase 4 (providers implement the `ActivityProvider` protocol from todo 28), Phase 5 (AI integration builds on the IPC contract from todo 31).

## What this phase delivers

The entire `NotchFlowCore` module, written test-first. Nine pure-Swift units with no AppKit imports and no ordering constraints between them, so all nine todos can run in parallel (8-wide in the plan's matrix; todo 24 is the geometry bedrock but nothing serializes on it). Everything the rest of the app builds on lands here: notch geometry, display selection, the activity model with priorities and lifecycle, the provider protocol and registry, the activity manager with its idle signal, the AI agent state machine, the IPC message contract, and hook-snippet generation.

The rules that govern every todo in this phase, taken from the plan's verification strategy:

- **Failing test first** for every pure unit. Swift Testing (`@Test`, `#expect`) is the framework; XCTest only where no Swift Testing equivalent exists.
- **AppKit-free by construction.** Geometry takes injected values, never a live `NSScreen`, so everything runs on a headless CI runner.
- **Anti-fake-pass:** every QA names an exact command and an exact assertion on its output. A test that passes because it asserts nothing is a failure.

## Todos

### 24. TDD the notch geometry pure functions

Write failing tests first for a function computing the notch rectangle from `frame`, `safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`, and a function deciding whether a screen description represents a notched built-in display. Cover a 14" MacBook Pro, a 16" MacBook Pro, a notched Air, a non-notched Mac, a zero-inset external display, and degenerate/empty auxiliary areas. Then implement in `NotchFlowCore`.

- **Acceptance:** All cases pass; no AppKit import; the functions are total (no crash on degenerate input, returning nil instead).
- **QA (CI):** `swift test --filter Geometry`; assert all pass and that the degenerate cases return nil rather than trapping.
- **Evidence:** `.omo/evidence/task-24-notchflow-v1.log`
- **Commit:** `feat(core): add notch geometry calculations`

### 25. TDD the display-selection state machine

Failing tests first for the state table in [docs/03](../03-display-and-notch.md): available screens × user preference → target screen, including automatic mode, an explicit built-in choice, an explicit external choice that is currently connected, the same choice while disconnected (fall back to built-in), and no built-in available (clamshell).

- **Acceptance:** Every row of the documented table has a test; all pass.
- **QA (CI):** `swift test --filter DisplaySelection`; assert the test count equals the documented row count.
- **Evidence:** `.omo/evidence/task-25-notchflow-v1.log`
- **Commit:** `feat(core): add display selection policy`

### 26. TDD `ActivityPriority` and the ordering rule

Failing tests first: ordering across all four priority levels, tie-breaking by start time, and stability under repeated sorts.

- **Acceptance:** Ordering is total and deterministic.
- **QA (CI):** `swift test --filter Priority`.
- **Evidence:** `.omo/evidence/task-26-notchflow-v1.log`
- **Commit:** `feat(core): add activity priority ordering`

### 27. TDD the `Activity` protocol and lifecycle types

Define `Activity`, its identity and kind types, the lifecycle events, and the auto-dismiss descriptor, driven by tests for a stub conforming type covering start, update, end, and auto-dismiss expiry.

- **Acceptance:** A conforming stub can be driven through every lifecycle transition; illegal transitions are rejected.
- **QA (CI):** `swift test --filter ActivityLifecycle`.
- **Evidence:** `.omo/evidence/task-27-notchflow-v1.log`
- **Commit:** `feat(core): add activity protocol and lifecycle`

### 28. TDD `ActivityProvider` and the registry

Define the provider protocol (start observing, stop observing, emit activities) and a registry that starts and stops providers. Tests use fake providers and assert that stopping the registry stops every provider and leaves no retained observer.

- **Acceptance:** No provider continues to emit after the registry stops; no reference cycles (verified by a deallocation test).
- **QA (CI):** `swift test --filter ProviderRegistry`; include a test asserting a weak reference is nil after teardown.
- **Evidence:** `.omo/evidence/task-28-notchflow-v1.log`
- **Commit:** `feat(core): add provider protocol and registry`

### 29. TDD `ActivityManager`

Failing tests first for: registration, deduplication by identity, update-in-place, removal on end, ordering by priority, the compact-slot limit and overflow indicator, auto-dismiss firing, and — critically — the transition to empty producing an explicit "become idle" signal exactly once.

- **Acceptance:** The idle signal fires exactly once per emptying, never while activities remain; the worked example from [docs/05](../05-activity-model.md) (music + timer + transfer) produces the documented ordering.
- **QA (CI):** `swift test --filter ActivityManager`; assert the idle-signal count in the emptying test is exactly one.
- **Evidence:** `.omo/evidence/task-29-notchflow-v1.log`
- **Commit:** `feat(core): add activity manager`

### 30. TDD the AI agent state machine

Failing tests first for the seven states and their legal transitions, including rejection of illegal transitions, coalescing of rapid duplicate updates, and the terminal-state auto-dismiss timing.

- **Acceptance:** The transition table in [docs/07](../07-ai-integration.md) is fully covered; illegal transitions are rejected rather than silently accepted.
- **QA (CI):** `swift test --filter AgentState`.
- **Evidence:** `.omo/evidence/task-30-notchflow-v1.log`
- **Commit:** `feat(core): add AI agent state machine`

### 31. TDD the IPC message contract

Failing tests first for decoding a valid message, rejecting an unknown schema version, rejecting missing required fields, rejecting an oversized payload, rejecting a payload with a disallowed agent id, and safely handling hostile strings (very long, control characters, shell metacharacters, invalid UTF-8). Then implement the codable types and validator in `NotchFlowCore`.

- **Acceptance:** Every hostile input is rejected without crashing; no received string is ever interpolated into a shell command anywhere in the codebase.
- **QA (CI):** `swift test --filter IPCMessage`; plus a grep asserting no shell interpolation of message fields.
- **Evidence:** `.omo/evidence/task-31-notchflow-v1.log`
- **Commit:** `feat(core): add IPC message schema and validation`

### 32. TDD hook-snippet generation

Failing tests first for generating the Claude Code settings fragment, the Codex `notify` fragment, and the OpenCode plugin file, including correct escaping of paths containing spaces and quotes, and idempotence (generating twice yields identical output).

- **Acceptance:** Generated fragments parse as valid JSON/TOML/TypeScript respectively; paths with spaces are correctly escaped.
- **QA (CI):** `swift test --filter HookGeneration`; additionally pipe each generated fragment through a parser and assert success.
- **Evidence:** `.omo/evidence/task-32-notchflow-v1.log`
- **Commit:** `feat(core): add agent hook snippet generation`

## Verification

All nine todos are `CI` tier — headless, no hardware. The full phase check is one command per filter:

```bash
swift test --filter Geometry
swift test --filter DisplaySelection
swift test --filter Priority
swift test --filter ActivityLifecycle
swift test --filter ProviderRegistry
swift test --filter ActivityManager
swift test --filter AgentState
swift test --filter IPCMessage
swift test --filter HookGeneration
```

Or all at once, since the core module has nothing else yet:

```bash
swift test
```

Phase 2 is DONE when all nine filters pass on a headless runner, `NotchFlowCore` still imports nothing beyond Foundation, and each todo's evidence file exists under `.omo/evidence/`.
