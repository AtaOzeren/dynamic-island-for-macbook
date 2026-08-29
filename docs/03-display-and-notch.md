# Display and Notch

This document specifies how NotchFlow finds the notch, computes its exact rectangle, reacts to display changes without polling, and picks which screen to anchor to. It is a design specification — nothing in this folder is code.

## Detecting the notched display

A display has a notch if `NSScreen.safeAreaInsets.top > 0`. This API is available from macOS 12 onward; NotchFlow's minimum deployment target must be at or above that. External displays and older built-in displays without a notch always report `safeAreaInsets.top == 0`, so the check alone is sufficient to distinguish a notched screen from every other screen currently attached — no model-name sniffing is required.

Combine the safe-area check with `NSScreen.main` / the built-in-display heuristic (a screen is treated as built-in when it cannot be disconnected, i.e. it has no corresponding entry that toggles on physical unplug) only to disambiguate in multi-display setups where an external screen might, in theory, also report a non-zero inset. In practice, as of macOS 12+, only Apple's notched built-in panels report a non-zero `safeAreaInsets.top`, so this is a defensive check rather than the primary signal.

## The notch rectangle formula

The notch rectangle is computed as a pure function over four inputs already exposed by `NSScreen`:

```
func notchRect(
    frame: CGRect,
    safeAreaInsets: NSEdgeInsets,
    auxiliaryTopLeftArea: CGRect?,
    auxiliaryTopRightArea: CGRect?
) -> CGRect?
```

Given non-nil auxiliary areas:

| Component | Formula |
|---|---|
| origin x | `auxiliaryTopLeftArea.maxX` |
| origin y | `frame.maxY - safeAreaInsets.top` |
| width | `auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX` |
| height | `safeAreaInsets.top` |

If either auxiliary area is `nil` (the screen has no notch, or is running on an OS version that does not populate them), the function returns `nil` and NotchFlow falls back to the degraded mode described below. Because this is a pure function of four already-available values, it is fully unit-testable with synthetic `NSScreen`-shaped structs — no live screen or hardware is needed to cover it in CI.

## Fallback: displays without a notch

When `notchRect` returns `nil` — a Mac with no notch, an external-only setup, or a lid-closed clamshell session — NotchFlow does not disable itself. It anchors the island to the top-centre of the menu bar instead, using the standard menu bar height for that screen. This is a supported degraded mode, not an error state: every V1 activity type still renders, just without the notch-shaped cutout framing it.

## Reacting to display changes without polling

NotchFlow never polls `NSScreen.screens` on a timer. All display-state changes arrive as push notifications:

| Event | Notification | Triggers |
|---|---|---|
| Display hotplug, resolution change, arrangement change | `NSApplication.didChangeScreenParametersNotification` | Re-run display selection; recompute `notchRect` for the new configuration |
| System entering sleep | `NSWorkspace.willSleepNotification` | Order the panel out proactively so no compositing happens across the sleep transition |
| System waking | `NSWorkspace.didWakeNotification` | Re-validate the selected display and recompute geometry before showing anything again |
| Lid closed with an external display active (clamshell) | Surfaces as a `didChangeScreenParametersNotification` (the built-in screen drops out of `NSScreen.screens`) | Re-run display selection; the built-in display is no longer a candidate until the lid reopens |
| Lid reopened | Surfaces as a `didChangeScreenParametersNotification` (the built-in screen reappears) | Re-run display selection; built-in becomes a candidate again |

Each handler re-runs the same pure selection-and-geometry pipeline; there is no separate "delta" logic to keep in sync, which is also why the pipeline being pure functions matters for correctness, not just testability.

## Display-selection policy

The default selection mode is **automatic**, which always means "the built-in display." Users may override this to a specific named display; when they do, NotchFlow anchors to that display by name (`NSScreen.localizedName`) as long as it remains connected. NotchFlow never migrates the island to a different display on its own initiative — if the selected display disconnects, it falls back to the built-in display and stays there until the user picks another target or the previously selected display reconnects.

| Screens present | User setting | Target screen |
|---|---|---|
| Built-in only | Automatic | Built-in |
| Built-in + one external | Automatic | Built-in |
| Built-in + one external | Named external display, connected | Named external display |
| Built-in + one external | Named external display, now disconnected | Built-in (fallback) |
| External only (clamshell, lid closed) | Automatic | The sole external display, in the degraded (menu-bar-anchored) mode since there is no notch |
| External only (clamshell, lid closed) | Named display that is not the connected one | Fallback to the connected external display, degraded mode |
| Built-in reappears after lid reopen, external was in use as fallback | Automatic | Built-in |
| No screens report as available (transient, during wake) | Any | No panel shown until the next `didChangeScreenParametersNotification` resolves a valid screen |

## Known edge cases

- **Clamshell mode with the lid closed and no built-in screen active.** `NSScreen.screens` no longer includes the built-in panel. Automatic mode falls back to whichever external display is present, in degraded (non-notch) mode.
- **Screen mirroring.** Mirrored displays can report inconsistent or duplicated geometry; NotchFlow selects based on the built-in display's own `NSScreen` entry when it is present, regardless of mirroring state, and otherwise falls back per the table above.
- **A display appearing before its `localizedName` is populated.** On some hotplug events the new `NSScreen` entry is present in `didChangeScreenParametersNotification` before `localizedName` resolves to its final value. Named-display selection must tolerate a transient empty or placeholder name and re-match on the next parameter-change notification rather than treating an early mismatch as "display not found."
