# Phase 3: Window and UI

**Todos:** 33-40
**Status:** COMPLETE (33-40 done)
**Depends on:** Phase 2 (Core, under TDD) — specifically the geometry functions, the activity model, and the idle signal that this phase's window and views subscribe to.
**Blocks:** Phase 4 (Activity Providers) needs the view containers built here to render provider-specific compact/expanded views. Phase 6 (Settings, Localization, Polish) needs a working window before it can wire appearance and accessibility settings into it.

## What this phase delivers

The actual notch window on screen: the borderless `NSPanel` positioned under the notch, the hidden/compact/expanded state machine that decides when it's visible, click-through so the menu bar stays usable while idle, the SwiftUI containers that render whatever activities are active, spring animations between states, and support for light/dark mode and accessibility settings. Everything in Phase 2 was pure logic with no window on screen — this phase is where the app becomes visible.

## Todos

### 33. Implement the screen observer

A `NotchFlowProviders` type wrapping `NSApplication.didChangeScreenParametersNotification`, display reconfiguration, and sleep/wake notifications behind the protocol the core tests already fake. Emits a screen-set description into the core's display-selection policy.

- **Acceptance:** Subscribes on start, fully unsubscribes on stop, and emits on every relevant system event.
- **QA (HW):** Plug and unplug an external monitor, change resolution, sleep and wake; assert one emission per event in a debug log. Evidence: `.omo/evidence/task-33-notchflow-v1.log`.
- **Commit:** `feat(display): observe screen configuration events`

### 34. Implement the `NotchPanel` window

The `NSPanel` subclass with every property from `docs/04`, positioned by the core geometry functions on the selected screen.

- **Acceptance:** The panel appears exactly under the notch on the built-in display, never on an external display unless explicitly selected.
- **QA (HW):** Screenshot on the notched MacBook with the panel visible; measure alignment against the notch edges. Evidence: `.omo/evidence/task-34-notchflow-v1/`.
- **Commit:** `feat(ui): add the notch panel window`

### 35. Implement the three-state presentation controller

Hidden, compact, expanded. Hidden means `orderOut(nil)`. The controller subscribes to the manager's activity set and the idle signal, and orders the window out on idle.

- **Acceptance:** With no activity the window is not on screen (`isVisible == false`); the transition to hidden happens within the documented delay.
- **QA (HW):** Start an activity, end it, assert `isVisible` becomes false; capture the window list before and after. Evidence: `.omo/evidence/task-35-notchflow-v1.log`.
- **Commit:** `feat(ui): add hidden/compact/expanded presentation states`

### 36. Implement click-through and hit-testing

`ignoresMouseEvents` true whenever collapsed or hidden; false only while expanded. Hover detection via a passive global monitor with a bounds check, not a polling loop.

- **Acceptance:** Menu-bar clicks near the notch reach the menu bar while collapsed; the panel receives clicks while expanded.
- **QA (HW):** Click a menu-bar item adjacent to the notch while an activity is compact; confirm the menu opens. Then expand and confirm the panel handles a click. Evidence: screen recording at `.omo/evidence/task-36-notchflow-v1/`.
- **Commit:** `feat(ui): add click-through and hover handling`

### 37. Implement the compact view container

Renders the ordered activity set as icons/pills hugging the notch, with the overflow indicator when the slot limit is exceeded.

- **Acceptance:** Matches the layout described in `docs/05` for the three-activity worked example.
- **QA (HW):** Drive three simultaneous fake activities; screenshot and compare to the documented layout. Evidence: `.omo/evidence/task-37-notchflow-v1/`.
- **Commit:** `feat(ui): add compact activity view`

### 38. Implement the expanded view container

Renders every active activity's expanded view in priority order, with the documented spacing and the primary-action affordance.

- **Acceptance:** All active activities are visible and ordered correctly.
- **QA (HW):** Same three-activity scenario, expanded; screenshot compared to `docs/05`. Evidence: `.omo/evidence/task-38-notchflow-v1/`.
- **Commit:** `feat(ui): add expanded activity view`

### 39. Implement transitions and animation

Spring animations for hidden↔compact↔expanded using the parameters in `docs/04`, honouring Reduce Motion, and running no animation while hidden.

- **Acceptance:** With Reduce Motion enabled, transitions are instant; no animation timer exists while hidden.
- **QA (HW):** Toggle Reduce Motion and record both behaviours; sample the process during the hidden state and assert no animation work. Evidence: `.omo/evidence/task-39-notchflow-v1/`.
- **Commit:** `feat(ui): add island state transitions`

### 40. Implement appearance handling

Light/dark mode, Reduce Transparency, and the appearance setting from `docs/08`.

- **Acceptance:** The island is legible in both appearances and with Reduce Transparency enabled.
- **QA (HW):** Screenshot in all four combinations. Evidence: `.omo/evidence/task-40-notchflow-v1/`.
- **Commit:** `feat(ui): honour system appearance and accessibility settings`

## Verification notes

Every todo in this phase is tagged `HW` in the plan — it needs the physical notched MacBook, since there's no way to fake an `NSPanel` positioned under a real notch on a headless CI runner. Per the plan's Final Verification Wave, these get collected into a scripted checklist with screenshot/recording evidence rather than run one-off. See the plan's [Verification strategy](../../.omo/plans/notchflow-v1.md#verification-strategy) for the anti-fake-pass rules that apply to all of them.

## Source of truth

This file quotes todos 33-40 verbatim from `.omo/plans/notchflow-v1.md`. If the plan changes, re-derive this file from it — do not let the two drift.
