# Activity Model

This document specifies the `Activity` protocol, the `ActivityPriority` enum and its V1 assignment table, the `ActivityManager` contract, and a worked example of multiple simultaneous activities. It is a design specification — nothing in this folder is code.

## The `Activity` protocol

Every feature in KerNotch — music, timers, recording indicators, charging state, AI status — is an `Activity`. `KerNotchCore` owns this protocol and knows nothing about any specific activity's implementation; `KerNotchProviders` supplies the concrete types (see `06-activity-providers.md`).

| Member | Kind | Purpose |
|---|---|---|
| `identity` | property | A stable, unique identifier used for deduplication — the same identity replaces an existing activity instead of creating a second one |
| `compactGroupIdentity` | property | Presentation-only grouping key; concurrent sessions from one AI agent share one compact icon while retaining separate activity identities |
| `compactInstanceIdentity` | property | What the compact group's count badge tallies; sessions sharing one count once, so an agent's sub-agents never inflate the number of agents shown as running |
| `compactRepresentationPriority` | property | Chooses the most important representative when multiple activities share a compact group |
| `compactRegion` | property | Selects the standard compact capacity or the dedicated trailing AI-agent region |
| `kind` | property | Which activity type this is (music, timer, recording, charging, AI, …), used for routing to the right view and for the priority table below |
| `priority` | property | An `ActivityPriority` value that determines ordering and, at `critical`/`high`, whether the activity forces the panel visible |
| `autoDismiss` | optional property | If set, the `ActivityManager` removes this activity automatically after the given duration elapses with no intervening registration or update; defaults to `nil` |
| `primaryAction` | optional property | If set, defines what a click on this activity's compact or expanded view does (e.g. open the source app, focus a terminal); if unset, the activity is inert to clicks beyond the panel's own expand/collapse behaviour; defaults to `nil` |

`identity`, `kind`, and `priority` are required on every activity. Compact grouping properties have defaults that keep an activity ungrouped in the standard region. `autoDismiss` and `primaryAction` are optional with `nil` defaults — the `ActivityManager` can manage any activity without them.

Lifecycle management (`register`, `update`, `end`) lives on `ActivityManager`, not on the `Activity` protocol. Providers call the manager's methods; the manager owns the active set and the auto-dismiss timers. View rendering is handled in `KerNotchUI` by type-switching on `ActivityKind`, not by view-builder methods on the protocol.

## `ActivityPriority`

```
enum ActivityPriority {
    case critical
    case high
    case normal
    case low
}
```

Priority determines one thing: ordering within the expanded view (higher priority sorts first). The compact pill has too few places for everything, so it orders by its own `compactRank` instead — see the compact view capacity rule below. The panel itself remains compact and visible while the app is running; registering an activity supplies content that can expand. `critical` is reserved and unused by any V1 activity, left for a future case (see `13-deferred-backlog.md`) that must never be silently outranked by a V1 addition.

### V1 priority assignment

| Activity kind | Priority | Compact rank | Auto-dismiss |
|---|---|---|---|
| AI needs input | `high` | — (agent region) | No — stays until the user responds or the agent's state changes |
| AI completed | `high` | — (agent region) | Yes — after 22 seconds |
| Recording (screen or audio) | `high` | `capture` | No — stays for the duration of the recording |
| Discord call | `high` | `call` | No — stays for the duration of the call |
| Watchdog notice | `high` | `notice` | Yes — after 30 seconds |
| Timer expiring | `high` | `alert` | No — stays until acknowledged |
| Charging (plug-in or unplug) | `normal` | `transition` | Yes — after 4 seconds |
| Timer running | `normal` | `tracking` | No — stays until stopped |
| Music | `low` | `ambient` | No — stays as long as something is playing |

This table is the single source of truth for ordering. A provider that introduces a new activity kind must add a row here before it ships (see the extension guide below).

## The `ActivityManager` contract

The `ActivityManager` lives in `KerNotchCore` and is the only component that providers and the UI both talk to — providers push activities in, the UI reads the active set out. Neither side talks to the other directly.

| Responsibility | Behaviour |
|---|---|
| Registration | A provider calls into the manager to register a new `Activity` or push an `update()` to an existing one |
| Deduplication | Registration is keyed by `identity`; a second registration with the same identity updates the existing activity in place rather than creating a duplicate |
| Ordering | The active set is sorted by order band (media and capture pinned first), then by `priority` (highest first), then by registration time (oldest first), so a `high` activity always outranks a `normal` one in the same band regardless of when either arrived |
| Compact view capacity | Each side of the notch holds two icons. Standard activities are ordered by `compactRank`, then by registration time. Without agents the leading side fills first and keeps the odd icon (one icon: leading; two: one each side; three: two leading, one trailing; four: two each side). While any agent is drawn, the trailing side belongs to the agents and standard icons keep to the leading side. Standard icons that do not fit are not drawn, with no overflow indicator. Every agent group is drawn. |
| Expanded view | Shows every active activity, in priority order, with no overflow — expansion exists precisely so nothing is truncated |
| Auto-dismiss | The manager owns the timers for any activity with an auto-dismiss duration set; when the duration elapses without an intervening `update()`, the manager calls `end()` on that activity itself, the provider does not need to |
| Panel visibility | The panel remains in compact form when the active set is empty. The controller orders it out only for suspension, teardown, or a missing target screen; `ActivityManager` decides compact content and whether expansion is allowed. |

An empty active set guarantees a static compact surface: no provider activity may leave an animation, polling loop, or timer running after calling `end()`. This preserves the idle budget while keeping the small island visible.

## Worked example: a call, a meeting and music

A Discord call is live, another meeting holds the microphone, and a track is playing. By compact rank the microphone (`capture`) comes first, the call (`call`) second, and the music (`ambient`) last.

**Compact pill without agents** (three icons: two leading, one trailing):

```
🎙  🎧   [ notch ]   🎵
```

**Compact pill with two agents running** (the trailing side belongs to the agents, so the leading side keeps its two most important icons and the music is not drawn):

```
🎙  🎧   [ notch ]   Claude  Codex
```

**Expanded view** (priority order, every activity, full detail):

```
┌──────────────────────────────┐
│ 🎧 Discord call               │
│ 🎙 Microphone in use          │
│ 🎵 Spotify                    │
│ Claude · Working              │
│ Codex · Working               │
└──────────────────────────────┘
```

A paused track leaves the pill after twenty seconds (see `04-overlay-window.md`). It is taken out before the sides are counted, so it never holds a place another icon needs.

A screen recording and the microphone share one compact slot: the pill draws the screen mark with a red microphone badge, so one capture costs one place. The expanded view keeps a card for each, since each has its own running time.

Concurrent sessions from the same AI agent share one compact slot. The manager keeps every session independently active, but the agent group takes one place in the pill. The compact presentation reports each group's size alongside it, and a slot standing in for more than one session draws that count as a badge on the top-right corner of the agent's logo — the icon otherwise says nothing about the sessions behind the one it is drawing, so a second session could ask a question and never appear. The badge is capped at `9+`, and the slot reserves its corner whether or not a badge is drawn, so a session opening never shifts the icons already on screen.

AI slots stay together at the far-right edge, oldest first. Every agent group is drawn — KerNotch integrates three agents, and the trailing side has room for all three — so an agent waiting on the user is never dropped for another. A group draws its most urgent session.

The expanded view draws one card per *instance* — one terminal, one editor window, one conversation the user started. Where an agent has more than one instance, each card's title carries a number (`OpenCode 2`) assigned in registration order, so two identical status lines remain tellable apart and an instance changing state does not renumber the others.

An instance ending ends the sub-agents under it, since the process that would have reported their end is the one that went away. A session an agent spawned to delegate work is not an instance. It appears in the list its parent's card discloses, labelled with the delegated agent's own name, and the card's control says how many there are (`4 agents`). The card itself speaks for the most urgent session in the instance, sub-agents included, so a sub-agent blocked on a permission prompt turns the card — and the compact icon — yellow without the list having to be opened.

## Extension guide: adding a new activity type

A contributor adding a new activity kind in a later version touches only `KerNotchProviders` and this document — never `ActivityManager` itself:

1. Define a new type conforming to `Activity` in `KerNotchProviders` (or a new provider module), implementing `identity`, `kind`, `priority`, and the optional `autoDismiss` and `primaryAction` as needed. Add the corresponding compact and expanded SwiftUI views in `KerNotchUI`, keyed by the new `ActivityKind` case.
2. Add a row to the V1 (or later) priority assignment table above so ordering is unambiguous and reviewable.
3. Register the new provider with the `ActivityManager` at the composition root (`KerNotch` app target) — the manager requires no code changes to accept a new `kind`, since it operates only on the protocol, not on concrete types.
4. Document the provider's event source and permission needs in `06-activity-providers.md`.

Because the manager only ever depends on the `Activity` protocol and never on any concrete activity type, this is the entire surface a new feature needs to touch — the ordering rule, the panel visibility rule, and the compact/expanded rendering all keep working unmodified.
