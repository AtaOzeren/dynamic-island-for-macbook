# Overlay Window

This document specifies the `NSPanel` that draws the island: every property that makes it borderless, non-activating, and click-through while idle; the three visual states and their geometry; the sizing strategy; interaction rules; animation parameters; and behaviour across full-screen apps, Spaces, and accessibility settings. It is a design specification — nothing in this folder is code.

## The `NSPanel` property table

NotchFlowUI owns a single `NSPanel` subclass, created once at launch and never deallocated. Every property below is set once at creation unless the "Changes at runtime" column says otherwise.

| Property | Value | Changes at runtime | What breaks if it is wrong |
|---|---|---|---|
| `styleMask` | `[.borderless, .nonactivatingPanel]` | No | Without `.borderless`, AppKit draws a title bar and window chrome over the notch. Without `.nonactivatingPanel`, any click on the panel steals key focus from the frontmost app, interrupting typing or gameplay. |
| `isFloatingPanel` | `true` | No | Without this, the panel behaves like a document window: it can be sent behind other windows by a simple click-to-front on another app, and it participates in the regular window cycling order (Cmd-`). |
| `level` | Above `.mainMenu` (`NSWindow.Level.mainMenu + 1` or `.statusBar`, whichever is measured to sit above the system menu bar without sitting above system-critical UI like the screen-lock overlay) | No | Too low: other apps' windows, or the menu bar itself, draw over the island and it becomes invisible in normal use. Too high: the island covers system UI it has no business covering, e.g. Control Center or Notification Center panes as they animate in. |
| `isOpaque` | `false` | No | If `true`, AppKit paints an opaque backing rectangle behind the SwiftUI content, producing a visible box around the intended notch-shaped cutout instead of a seamless blend with the black notch. |
| `backgroundColor` | `.clear` | No | If any non-clear color is set, the same visible-box artifact appears even with `isOpaque = false`; the two properties must agree. |
| `hasShadow` | `false` in compact state; `true` in expanded state | Yes, per visual state | A shadow on the compact pill draws a soft grey halo around the notch at all times, which reads as a rendering glitch since the notch itself casts no shadow. A missing shadow on the expanded panel makes it look pasted onto the desktop instead of floating above it. |
| `hidesOnDeactivate` | `false` | No | If `true`, the panel disappears the moment NotchFlow itself loses focus to any other app — which is effectively always, since NotchFlow is never the active app during normal use. This would make the island invisible except while clicking on NotchFlow's own (nonexistent) windows. |
| `isMovable` | `false` | No | If `true`, an accidental drag on the panel — even though it is non-activating — repositions the island away from the notch it is supposed to be anchored to, with no way for the user to reset it short of relaunching. |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` | No | Without `.canJoinAllSpaces`, the island vanishes the moment the user switches to a different Space. Without `.fullScreenAuxiliary`, the panel cannot appear at all over an app running in full-screen/Space-per-display mode. Without `.stationary`, the panel scrolls along with Mission Control / Space-switching gesture animations instead of staying pinned to the notch. |
| `canBecomeKey` | `false` | No | If `true`, a click anywhere on the panel (even in the non-activating case) can still make it the key window, which redirects keyboard input intended for the previously-focused app into a window that has no text fields to receive it. |
| `canBecomeMain` | `false` | No | Same failure mode as `canBecomeKey`, at the main-window level: it would make NotchFlow's panel eligible to become the app's main window, which has no meaning for an accessory-style overlay and can confuse window-cycling shortcuts. |
| `ignoresMouseEvents` | `true` while collapsed (hidden or compact-idle); `false` while hovered, expanded, or mid-animation into either | Yes, per interaction state | If always `true`, the island can never be clicked to expand. If always `false`, the panel's full bounding rectangle — which is larger than the visible pill so it can grow into the expanded shape — intercepts clicks meant for the menu bar or desktop underneath it, even where nothing is visibly drawn. |

## Visual states and geometry

The panel has exactly three visual states. Normal runtime uses compact and expanded; hidden is reserved for suspension, teardown, or a missing target screen. Activity changes and direct user interaction drive compact ↔ expanded transitions.

| State | Window geometry | Content geometry |
|---|---|---|
| Hidden | Ordered out (`orderOut(_:)`) during suspension, teardown, or while no target screen exists | No content rendered; SwiftUI view tree is suspended, not merely invisible |
| Compact | Window frame is the same maximum expanded bounds as always (see sizing strategy below); visible content is a pill that hugs the left and right edges of the notch rectangle from `docs/03-display-and-notch.md`, sitting flush against its bottom edge | A narrow horizontal capsule, tall enough to match the notch height, wide enough for the current activity's compact icon(s) plus the notch width itself |
| Expanded | Same window frame; visible content is a panel of one fixed width, growing downward from the notch | The compact pill carrying two icons on each flank, widened by `expandedPanelWidthGrowth`. Fixed rather than fitted to the widest card: cards share the island's surface and stretch to whatever the panel gives them, so a width that tracked its contents would only make the island a different shape depending on what happened to be running |
| Expanded | Same window frame as compact; visible content grows downward from the notch | A larger rounded rectangle anchored at the top-centre under the notch, tall and wide enough to show full activity detail — track art and transport controls, a running timer face, recording controls, or AI agent detail — sized per-activity but capped at a maximum that keeps it clear of the Dock and any secondary display's menu bar |

## Sizing strategy: fixed window, animated content

The `NSPanel`'s own frame is set once, at its maximum possible expanded size, and is never resized after that during normal operation (it is only recomputed on a `docs/03`-style display change). What changes between hidden, compact, and expanded is the SwiftUI content's own layout inside that fixed frame — its actual drawn size, opacity, and position — animated with SwiftUI transitions, while `ignoresMouseEvents` (see table above) keeps the parts of the fixed frame that are visually empty from intercepting clicks.

The reason: resizing an `NSWindow`'s frame is a compositor-level operation — it has to inform the window server, which is measurably more expensive and more prone to visible stutter than animating a SwiftUI view's size within an already-allocated, unchanging window. Doing this once per activity transition instead of holding the window at a fixed maximum size would mean paying that window-server round trip on every single expand and collapse, which happens far more often than a display's geometry changes.

## Interaction rules

| Trigger | Effect |
|---|---|
| Mouse enters the compact pill's hit area | Peek: content grows slightly beyond the pure compact size, previewing that more detail is available, without committing to the full expanded layout |
| Click on the compact pill (or the peeked state) | Expand: content animates to the expanded geometry; `ignoresMouseEvents` becomes `false` for the whole active area |
| Click anywhere outside the expanded panel's bounds | Collapse: content animates back to compact; `ignoresMouseEvents` reverts to `true` outside the compact pill's hit area |
| Escape key, while expanded | Collapse, identical to click-outside |
| Mouse leaves the peeked (but not clicked) pill | Revert to plain compact, no click required |
| Mouse leaves the expanded panel | Hold the panel open for a short grace period, then collapse. Returning inside it cancels the pending collapse — the island never closed, so nothing reopens and nothing flickers |
| Final activity ends while expanded | Collapse to the empty compact island immediately, without the grace period: there is nothing left to come back to |
| Click or hover while no activity is running | Keep the island compact; no empty expanded surface is shown |

An agent stopped by a standing condition — an exhausted quota, rejected credentials, an unreachable provider — is announced once and then kept, rather than repeated. The compact pill draws it red for about a minute and then stops drawing it at all: the pill is an announcement surface, and an agent retrying every forty seconds for six hours would otherwise announce the same news forever. The expanded panel keeps the fact at its foot, below a hairline, in the smallest text the island draws — one line for however many sessions and agents share the cause, plus the reset time where the condition lifts on its own. Opening the island therefore still answers "why is nothing happening?" hours after the pill went quiet.

Everything the island draws is clipped to the island's own silhouette. A view leaving through a transition keeps its full layout size while it fades, so without the clip a collapse drew the expanded cards at their old size for a few frames after the black surface had already shrunk past them — the panel appeared to close and leave its contents hanging outside it. The click-anywhere-outside collapse target is deliberately *not* clipped: it covers the whole window, which is the only way a click past the island's edge can close it.

`ignoresMouseEvents` is `true` for the entire panel whenever the visual state is collapsed (hidden or plain compact), so that the invisible portion of the fixed window frame described above never steals a menu-bar click. It only becomes `false` for the region under the pointer during peek, and for the whole expanded area once expanded.

## Animation specification

| Parameter | Value | Constraint |
|---|---|---|
| Curve | Spring, `response ≈ 0.35s`, `dampingFraction ≈ 0.8` | Tuned to feel snappy without overshoot that would visually collide with the notch's hard edges |
| Peek transition duration | ~0.15s ease-out | Fast enough to feel like hover feedback, not a committed state change |
| Expand/collapse transition duration | ~0.35s spring (see curve above) | Matches the primary spring so expand and collapse feel symmetric |
| Hover expansion delay | ~0.25s | Crossing the pill on the way somewhere else must not open the island |
| Collapse grace period | ~0.5s | The panel is a target the pointer travels to, and the path from the notch to a row crosses the island's own edge. Collapsing the instant the pointer slipped off made a hand that overshot start the hover again from scratch |
| Idle-state animation budget | Zero | No animation, timer-driven or otherwise, runs while the empty compact island is idle; this is part of the idle-cost contract from `docs/02-performance-contract.md` |

No animation is ever started while the window is ordered out. Returning from suspension orders the window in at resting compact geometry first; only a later user-triggered transition animates.

## Behaviour over full-screen apps, other Spaces, and Mission Control

- **Full-screen apps.** `.fullScreenAuxiliary` in `collectionBehavior` is what permits the panel to draw over an app running in a dedicated full-screen Space at all; without it, full-screen apps would hide the island entirely, defeating the point of an always-available overlay.
- **Other Spaces.** `.canJoinAllSpaces` keeps a single panel instance visible regardless of which Space is active, rather than requiring one panel per Space or a re-creation on every Space switch.
- **Mission Control.** `.stationary` prevents the panel from participating in the Mission Control "shuffle all windows into a grid" animation and from scrolling with Space-switch gestures; the island stays pinned to the notch's screen position throughout.

## Appearance: light/dark mode and accessibility

- **Light/dark mode.** The panel's SwiftUI content observes `NSApplication.effectiveAppearance` (or the SwiftUI `colorScheme` environment value it maps to) and switches its rendering — text, icon tint, and any background material — without requiring the panel itself to be recreated or reordered.
- **Reduced motion.** When `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is `true`, the spring animations in the table above are replaced with an instant or near-instant cross-fade; no transition is skipped outright, since the state still needs to visually change, but the motion component of it is removed.
- **Reduced transparency.** When `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` is `true`, any translucent SwiftUI material backing the expanded panel is replaced with a solid, high-contrast background rather than a blurred/vibrant one, while `backgroundColor = .clear` at the `NSPanel` level is unaffected — the opacity change happens in the SwiftUI content, not the window itself.
