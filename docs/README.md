# NotchFlow Documentation

**Your notch, alive with what matters.**

This folder is a design specification, not code. Every document here describes what NotchFlow must do and why, before a single line of Swift gets written. Read them in order the first time; after that, jump straight to the one you need.

## Contents

| # | Document | What it covers |
|---|----------|-----------------|
| 00 | [Product Overview](00-product-overview.md) | What NotchFlow is, who it's for, the problem it solves |
| 01 | [Architecture](01-architecture.md) | Module graph, dependency rule, event flow, threading model |
| 02 | [Performance Contract](02-performance-contract.md) | The idle-CPU and memory budget every build must satisfy |
| 03 | [Display and Notch](03-display-and-notch.md) | Finding the notch, computing its rectangle, reacting to display changes |
| 04 | [Overlay Window](04-overlay-window.md) | The `NSPanel` that draws the island: states, geometry, animation, edge cases |
| 05 | [Activity Model](05-activity-model.md) | The `Activity` protocol, priority rules, and the `ActivityManager` contract |
| 06 | [Activity Providers](06-activity-providers.md) | Every data source shipping in V1: music, timers, recording, charging, and more |
| 07 | [AI Integration](07-ai-integration.md) | The agent state machine and hook integrations for Claude Code, Codex, and OpenCode |
| 08 | [Settings and Localization](08-settings-and-localization.md) | The settings surface, persistence, onboarding, and localization mechanism |
| 09 | [Security, Privacy, and Permissions](09-security-privacy-permissions.md) | Privacy stance, entitlements, permission flow, and the IPC threat model |
| 10 | [Build and Distribution](10-build-and-distribution.md) | The dual-channel build (Mac App Store and Homebrew) and release pipeline |
| 11 | [Testing Strategy](11-testing-strategy.md) | TDD boundary, CI/hardware verifiability matrix, definition of done |
| 12 | [API Feasibility Matrix](12-api-feasibility-matrix.md) | Which macOS APIs are usable, sandbox-blocked, or impossible, and why |
| 13 | [Deferred Backlog](13-deferred-backlog.md) | Everything valuable that didn't make V1, and the trigger that revives it |
| 14 | [Glossary and Conventions](14-glossary-and-conventions.md) | Shared vocabulary, naming rules, and code/git/documentation conventions |

## How to use this folder

- Start with **00-product-overview** for the why, then **01-architecture** for the how everything fits together.
- Building a specific piece? Jump directly to its document — each one is self-contained enough to implement from.
- Unsure whether an API is usable? Check **12-api-feasibility-matrix** before you design around it.
- Wondering why something isn't in V1? It's probably in **13-deferred-backlog**, with the reason and the trigger to revisit it.
