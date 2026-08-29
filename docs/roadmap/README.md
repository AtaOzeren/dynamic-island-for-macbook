# Roadmap

This folder breaks the implementation plan (`.omo/plans/notchflow-v1.md`) into phases, so progress and scope are readable without opening the raw todo list. It tracks **code work only** — Wave 0 (the 15 `docs/` specification files + this index) is already complete and is not repeated here.

Each phase file states: what it delivers, which todos it covers, what it depends on, what it unblocks, and its exact verification commands, taken directly from the plan's Acceptance/QA criteria. Nothing here invents new scope — every line is traceable to a todo in the plan.

## Status legend

- `NOT STARTED` — no code written yet
- `IN PROGRESS` — some todos done, some pending
- `DONE` — all todos in the phase verified and committed
- `BLOCKED-ON-MEMBERSHIP` — plan explicitly defers this until an Apple Developer Program membership exists; work is written but not executed

## Phases

| Phase | Name | Todos | Status | Depends on |
|---|---|---|---|---|
| 0 | [Documentation](00-documentation.md) | 1–16 | DONE | — |
| 1 | [Project Foundation](01-foundation.md) | 17–23 | NOT STARTED | Phase 0 |
| 2 | [Core Under TDD](02-core-tdd.md) | 24–32 | NOT STARTED | Phase 1 (todo 17) |
| 3 | [Window and UI](03-window-ui.md) | 33–40 | NOT STARTED | Phase 2 |
| 4 | [Activity Providers](04-providers.md) | 41–49 | NOT STARTED | Phase 2, Phase 3 |
| 5 | [AI Integration](05-ai-integration.md) | 50–58 | NOT STARTED | Phase 2, Phase 3 |
| 6 | [Settings, Localization, Polish](06-settings-polish.md) | 59–65 | NOT STARTED | Phase 3, Phase 4, Phase 5 |
| 7 | [Performance, Packaging, Distribution](07-perf-packaging.md) | 66–74 | NOT STARTED | Phase 6 |
| F | [Final Verification Wave](final-verification-wave.md) | F1–F10 | NOT STARTED | Phase 7 |

## Dependency graph

```
Phase 0 (docs, done)
    │
    ▼
Phase 1 (foundation) ──────────────────────────────┐
    │                                               │
    ▼                                               │
Phase 2 (core, TDD) ──────┬──────────────┐          │
    │                     │              │          │
    ▼                     ▼              ▼          │
Phase 3 (window/UI)   Phase 4 (providers) Phase 5 (AI)
    │                     │              │
    └──────────┬──────────┴──────────────┘
               ▼
        Phase 6 (settings/i18n/polish)
               │
               ▼
        Phase 7 (perf/packaging/distribution)
               │
               ▼
        Final Verification Wave (F1–F10)
```

Phases 3, 4, and 5 have no ordering constraint between each other once Phase 2 is done — they can proceed in parallel. Phase 4 (providers) and Phase 5 (AI) each need the `ActivityProvider` protocol from Phase 2 and, where they render UI, the view containers from Phase 3.

## Source of truth

Every phase file quotes the plan's own Acceptance/QA/Commit lines rather than paraphrasing them, so a phase file going stale relative to the plan is a git-diffable event. If `.omo/plans/notchflow-v1.md` changes, re-derive the affected phase file from it — do not let the two drift.
