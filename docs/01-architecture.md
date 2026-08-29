# Architecture

This document specifies the module graph, the dependency rule that keeps it enforceable, the end-to-end event flow, and the threading model. It is a design specification — nothing in this folder is code.

## Module graph

```
┌─────────────────────────────────────────────────────────┐
│                      NotchFlow (app)                     │
│              composition root — wires everything          │
└───────────────┬───────────────┬───────────────┬─────────┘
                │               │               │
                ▼               ▼               ▼
      ┌─────────────────┐ ┌───────────┐ ┌──────────────────┐
      │ NotchFlowUI      │ │ Notch-    │ │ NotchFlowProviders│
      │ (SwiftUI views + │ │ FlowCore  │ │ (system framework │
      │  NSPanel ctrl)   │ │           │ │  integrations)     │
      └────────┬─────────┘ └─────┬─────┘ └─────────┬─────────┘
               │                 ▲                 │
               └─────────────────┴─────────────────┘
                     imports point inward only
```

| Module | Imports | Owns |
|---|---|---|
| `NotchFlowCore` | Foundation only | `Activity` protocol, `ActivityManager`, `ActivityPriority`, notch geometry math (pure functions), the AI agent state machine, IPC message types |
| `NotchFlowProviders` | `NotchFlowCore` + system frameworks (MediaRemote/ScriptingBridge, ScreenCaptureKit, AVFoundation, IOKit, etc.) | One provider per activity source; translates OS/IPC events into `Activity` updates |
| `NotchFlowUI` | `NotchFlowCore` | SwiftUI compact/expanded views, the `NSPanel` controller that positions and orders the overlay window |
| `NotchFlow` (app target) | All three | Composition root only — wires providers to the manager and the manager to the UI; contains no business logic |

## The dependency rule

Dependencies point inward, toward `NotchFlowCore`. `NotchFlowCore` **imports nothing but Foundation** — no AppKit, no SwiftUI, no provider module, no app-target code. `NotchFlowProviders` and `NotchFlowUI` may depend on `NotchFlowCore`, but `NotchFlowCore` never depends on them.

This is an enforceable invariant, not a convention: **the architecture guard script (todo 20) fails the build if any `NotchFlowCore` source imports AppKit, SwiftUI, or a provider module.** The guard runs in CI on every change.

Why this shape:
- **Testability in headless CI.** `NotchFlowCore` has no UI or system-framework dependency, so its state machine, priority resolution, and geometry math run as fast, deterministic unit tests with no window server, no display, no permissions.
- **Provider swap per build configuration.** Because `NotchFlowProviders` depends on `NotchFlowCore` and not the reverse, the App Store build and the Homebrew build can link different music providers (see `docs/06-activity-providers.md`) without touching `NotchFlowCore` or `NotchFlowUI` at all.

## End-to-end event flow

```
OS event or IPC message
        │
        ▼
    Provider                (NotchFlowProviders)
        │  translates raw event → Activity update
        ▼
  ActivityManager           (NotchFlowCore, @MainActor)
        │  register / update / end
        ▼
  Priority resolution       (NotchFlowCore)
        │  decides what is visible and in what order
        ▼
  Panel state change        (NotchFlowUI)
        │
        ▼
      Render                (NotchFlowUI)
        │
        ▼
   Activity ends
        │
        ▼
  Panel ordered out
        │
        ▼
       Idle
```

The panel is ordered out when, and only when, the active-activity set becomes empty. This single rule is what guarantees the idle performance budget in `docs/02-performance-contract.md`: no activities means no timers, no re-renders, and no visible window.

### Sequence diagram: track change while a timer is running

```
MusicProvider          TimerActivity        ActivityManager        NotchFlowUI
     │                       │                     │                    │
     │                       │  (timer already running, panel visible)  │
     │                       │                     │                    │
     │  trackDidChange(t2)   │                     │                    │
     ├──────────────────────────────────────────► │                    │
     │                       │  update(music, t2)  │                    │
     │                       │                     │                    │
     │                       │  ┌──────────────────┤                    │
     │                       │  │ priority resolve: │                    │
     │                       │  │ music=low,        │                    │
     │                       │  │ timer=high         │                    │
     │                       │  │ → both fit in     │                    │
     │                       │  │   compact view     │                    │
     │                       │  └──────────────────┤                    │
     │                       │                     │  panelState(       │
     │                       │                     │   [timer, music])  │
     │                       │                     ├──────────────────► │
     │                       │                     │                    │  render
     │                       │                     │                    │  compact view:
     │                       │                     │                    │  ⏱ 24:32  🎵 t2
```

The timer keeps its slot and priority throughout; the music activity's content updates in place without disturbing panel ordering or triggering a hide/show cycle.

## Threading model

- Providers may receive callbacks on arbitrary queues — whatever thread the underlying framework delivers on (a `DispatchQueue` from MediaRemote, a background queue from `ScreenCaptureKit`, an IPC read loop, etc.).
- All `ActivityManager` mutation is `@MainActor`. Providers never mutate manager state directly from a background queue.
- The documented hop pattern: a provider receives an event on its own queue, constructs an immutable `Activity` update value, then hops to the main actor (`Task { @MainActor in ... }` or an `@MainActor` method call) to hand that value to `ActivityManager`. No provider holds a reference to mutable manager state across the hop.

This keeps `ActivityManager` free of locks while still accepting input from concurrent, uncoordinated sources.
