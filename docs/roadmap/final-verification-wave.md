# Phase F: Final Verification Wave

**Todos:** F1–F10
**Status:** NOT STARTED
**Depends on:** Phase 7 (Performance, Packaging, Distribution). In practice it depends on everything: this wave re-runs the full build, the full test suite, and the complete hardware matrix against the finished app, so it can only start once every numbered todo (17–74) is done.
**Blocks:** Nothing. This is the terminal wave; when it passes, v1 is shippable.

## What this phase delivers

No new code. This wave proves the finished app against every contract the plan laid down: a clean build from a fresh checkout, the complete test suite with coverage, the hardware checklist from `docs/11` executed on the real notched MacBook, the multi-monitor and power-transition matrices, the full-screen and Spaces behaviour, a real end-to-end round-trip per AI agent, the idle performance budget from `docs/02`, the entitlements promised in `docs/09`, and finally a scope audit confirming every Must-have is present and every Must-NOT-have is absent.

The plan's verification strategy collects every `HW`-tier item into this wave and runs it as a scripted checklist with screenshot evidence. The anti-fake-pass rule applies here more than anywhere: a step is done when its evidence file exists and shows the asserted observation, not when someone says it passed.

## Todos

### F1. Full clean build of both configurations from a fresh checkout

Clone into a clean directory, build `AppStore` and `Direct`, and run all guards and lints. Assert zero warnings in the app targets.

- **Evidence:** `.omo/evidence/final-F1-notchflow-v1.log`

### F2. Complete automated test suite with coverage

Run every test target; assert all pass and that `NotchFlowCore` line coverage meets the threshold set in [docs/11](../11-testing-strategy.md) (near 100%, per the TDD boundary).

- **Evidence:** `.omo/evidence/final-F2-notchflow-v1.log`

### F3. Hardware matrix: single built-in display

The numbered checklist from [docs/11](../11-testing-strategy.md) on the notched MacBook alone: notch alignment, all three states, click-through, every provider, all seven AI states, light and dark, Reduce Motion, Reduce Transparency. One screenshot per step.

- **Evidence:** `.omo/evidence/final-F3-notchflow-v1/`

### F4. Hardware matrix: multi-monitor and display transitions

With one external monitor: island stays on the built-in display by default; explicit external selection works; unplugging the selected display falls back correctly; resolution change repositions correctly; mirroring behaves sanely.

- **Evidence:** `.omo/evidence/final-F4-notchflow-v1/`

### F5. Hardware matrix: power and lifecycle transitions

Sleep and wake, lid close and open, clamshell with an external display, user switch, and charging connect/disconnect. Assert the island recovers correctly and no duplicate or orphaned activity remains after each.

- **Evidence:** `.omo/evidence/final-F5-notchflow-v1/`

### F6. Hardware matrix: full-screen and Spaces behaviour

Island visibility and behaviour over a full-screen app, across multiple Spaces, and during Mission Control.

- **Evidence:** `.omo/evidence/final-F6-notchflow-v1/`

### F7. End-to-end AI round-trip for all three agents

Install each hook, run a real session per agent, observe every reachable state in the island, click through to the originating app, then uninstall and confirm each config file is byte-identical to its backup.

- **Evidence:** `.omo/evidence/final-F7-notchflow-v1/`

### F8. Idle performance verification

Run the todo 66 script with every provider enabled and no activity, for the full documented duration, and assert every [docs/02](../02-performance-contract.md) threshold.

- **Evidence:** `.omo/evidence/final-F8-notchflow-v1/`

### F9. Privacy and entitlement audit

Inspect the effective entitlements of both built binaries; assert they match [docs/09](../09-security-privacy-permissions.md) exactly with nothing extra. Confirm no network connection other than the loopback listener occurs during a full session, using a network monitor.

- **Evidence:** `.omo/evidence/final-F9-notchflow-v1/`

### F10. Scope and guardrail audit

Confirm every Must-have is present and every Must-NOT-have is absent: no MediaRemote symbol in the App Store build, no polling loop, no screen scraping, no third-party runtime dependency, no deferred feature partially implemented, no undocumented setting.

- **Evidence:** `.omo/evidence/final-F10-notchflow-v1.txt`

## Verification notes

F1, F2, and F8 through F10 are scriptable and assert on command output, matching the plan's anti-fake-pass rule. F3 through F7 are the `HW` tier: they need the physical notched MacBook (F4 and F5 additionally need one external monitor), and each step is backed by a screenshot in the evidence directory. F7 needs all three AI agents installed for a real session.

The wave has no commit strategy of its own: it lands evidence files, not code. If any step fails, the fix happens in the phase that owns the broken todo, and the failing F-step re-runs until it passes. The wave is complete when all ten evidence paths exist and every assertion inside them holds.
