# Activity Model

This document specifies the `Activity` protocol, the `ActivityPriority` enum and its V1 assignment table, the `ActivityManager` contract, and a worked example of multiple simultaneous activities. It is a design specification — nothing in this folder is code.

## The `Activity` protocol

Every feature in NotchFlow — music, timers, recording indicators, charging state, AI status — is an `Activity`. `NotchFlowCore` owns this protocol and knows nothing about any specific activity's implementation; `NotchFlowProviders` supplies the concrete types (see `06-activity-providers.md`).

| Member | Kind | Purpose |
|---|---|---|
| `identity` | property | A stable, unique identifier used for deduplication — the same identity replaces an existing activity instead of creating a second one |
| `kind` | property | Which activity type this is (music, timer, recording, charging, AI, …), used for routing to the right view and for the priority table below |
| `priority` | property | An `ActivityPriority` value that determines ordering and, at `critical`/`high`, whether the activity forces the panel visible |
| `start()` | lifecycle | Called once when the activity is registered with the `ActivityManager`; allocates any per-activity state |
| `update()` | lifecycle | Called whenever the underlying source has new data (a new track, a tick, a changed percentage); never called on a timer of NotchFlow's own unless the activity itself owns a tick (see Timer/Stopwatch in `06-activity-providers.md`) |
| `end()` | lifecycle | Called once when the activity is dismissed, either by its own logic (auto-dismiss, completion) or by the user; the `ActivityManager` removes it from the active set |
| `compactView()` | view builder | The SwiftUI view shown when the activity is part of the compact pill |
| `expandedView()` | view builder | The SwiftUI view shown when the activity is part of the expanded list |
| auto-dismiss duration | optional property | If set, the `ActivityManager` calls `end()` on this activity automatically after the given duration elapses with no further `update()` calls |
| primary action | optional property | If set, defines what a click on this activity's compact or expanded view does (e.g. open the source app, focus a terminal); if unset, the activity is inert to clicks beyond the panel's own expand/collapse behaviour |

`identity`, `kind`, and `priority` are required on every activity. The auto-dismiss duration and the primary action are the only two optional members — everything else is mandatory because the `ActivityManager` cannot render or manage an activity without it.

## `ActivityPriority`

```
enum ActivityPriority {
    case critical
    case high
    case normal
    case low
}
```

Priority determines two things: ordering within the compact and expanded views (higher priority sorts first), and whether the presence of the activity alone is enough to justify the panel becoming visible. All four cases in V1 are capable of forcing visibility; `critical` is reserved and unused by any V1 activity, left for a future case (see `13-deferred-backlog.md`) that must never be silently outranked by a V1 addition.

### V1 priority assignment

| Activity kind | Priority | Auto-dismiss |
|---|---|---|
| AI needs input | `high` | No — stays until the user responds or the agent's state changes |
| AI completed | `high` | Yes — auto-dismissing |
| Recording (screen or audio) | `high` | No — stays for the duration of the recording |
| Timer expiring | `high` | No — stays until acknowledged |
| Charging | `normal` | Yes — auto-dismissing |
| File/transfer | `normal` | No — stays for the duration of the transfer |
| Music | `low` | No — stays as long as something is playing |

This table is the single source of truth for ordering. A provider that introduces a new activity kind must add a row here before it ships (see the extension guide below).

## The `ActivityManager` contract

The `ActivityManager` lives in `NotchFlowCore` and is the only component that providers and the UI both talk to — providers push activities in, the UI reads the active set out. Neither side talks to the other directly.

| Responsibility | Behaviour |
|---|---|
| Registration | A provider calls into the manager to register a new `Activity` or push an `update()` to an existing one |
| Deduplication | Registration is keyed by `identity`; a second registration with the same identity updates the existing activity in place rather than creating a duplicate |
| Ordering | The active set is sorted by `priority` (highest first), then by registration time (oldest first) within the same priority, so a `high` activity always outranks a `normal` one regardless of when either arrived |
| Compact view capacity | The compact pill can show a limited number of activities at once (target: up to 3, see `04-overlay-window.md` for the pill's sizing constraints); activities beyond that limit are represented by a single overflow indicator (e.g. `+2`) rather than being hidden silently |
| Expanded view | Shows every active activity, in the same priority order as the compact view, with no overflow — expansion exists precisely so nothing is truncated |
| Auto-dismiss | The manager owns the timers for any activity with an auto-dismiss duration set; when the duration elapses without an intervening `update()`, the manager calls `end()` on that activity itself, the provider does not need to |
| Panel visibility | The panel is ordered out — hidden, zero cost, per `02-performance-contract.md` — when and only when the active activity set becomes empty; the manager is therefore the sole authority the `NotchPanel` controller (`04-overlay-window.md`) consults for the hidden ↔ compact ↔ expanded transitions |

The rule "panel hidden if and only if the active set is empty" is what guarantees the idle budget: there is no other code path that can keep the panel visible, and no activity can keep it visible after calling `end()`.

## Worked example: three simultaneous activities

This follows `draft.md:189-220`. Assume music, a running timer, and a file transfer are all active at once. By the priority table above, the timer (`high`, if expiring) or the transfer (`normal`) outranks music (`low`); a non-expiring timer and a transfer are both `normal` and order by registration time.

**Compact pill** (icons only, capacity not exceeded — 3 activities fit):

```
🎵   ⏱   📥
```

**Expanded view** (same priority order, full detail per activity):

```
┌──────────────────────────────┐
│ 🎵 Spotify                    │
│ ⏱ 24:32                       │
│ 📥 Download          67%      │
└──────────────────────────────┘
```

If a fourth `normal`-or-higher activity registers while these three are active and the compact capacity is 3, the pill instead shows two of the highest-priority icons plus an overflow indicator (e.g. `🎵 ⏱ +2`); the expanded view still lists all four, because the expanded view never truncates.

## Extension guide: adding a new activity type

A contributor adding a new activity kind in a later version touches only `NotchFlowProviders` and this document — never `ActivityManager` itself:

1. Define a new type conforming to `Activity` in `NotchFlowProviders` (or a new provider module), implementing `identity`, `kind`, `priority`, `start()`, `update()`, `end()`, `compactView()`, `expandedView()`, and the optional auto-dismiss duration and primary action as needed.
2. Add a row to the V1 (or later) priority assignment table above so ordering is unambiguous and reviewable.
3. Register the new provider with the `ActivityManager` at the composition root (`NotchFlow` app target) — the manager requires no code changes to accept a new `kind`, since it operates only on the protocol, not on concrete types.
4. Document the provider's event source and permission needs in `06-activity-providers.md`.

Because the manager only ever depends on the `Activity` protocol and never on any concrete activity type, this is the entire surface a new feature needs to touch — the ordering rule, the panel visibility rule, and the compact/expanded rendering all keep working unmodified.
