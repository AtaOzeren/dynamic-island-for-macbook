# Phase 6 — Settings, Localization, Polish

**Status:** NOT STARTED
**Todos:** 59–65 (Wave 6 in `.omo/plans/notchflow-v1.md`)
**Depends on:** Phase 3 (Window and UI), Phase 4 (Activity Providers), Phase 5 (AI Integration)
**Unblocks:** Phase 7 (Performance, Packaging, Distribution)
**Parallelism:** 3-wide

## Why this phase exists

Every earlier phase adds a feature that needs a setting to expose it, per the plan's dependency matrix: "Depends on everything having settings to expose." Phase 6 turns the app from a set of working features into a coherent, localized, first-run-ready product: a typed settings store, the settings window itself, first-run onboarding, string extraction and Turkish localization, lazy permission requests, and the app's visual assets.

## Todos

### 59. Implement the settings store
Typed `UserDefaults` wrapper with the exact keys and defaults from `docs/08`, plus the migration hook.
- **Acceptance:** Every documented setting round-trips; first launch produces exactly the documented defaults.
- **QA (CI):** Tests over a clean defaults domain asserting each default. Evidence: `.omo/evidence/task-59-notchflow-v1.log`.
- **Commit:** `feat(settings): add typed preferences store`

### 60. Implement the settings window
All panes from `docs/08`: general, display, activities, AI integrations, about.
- **Acceptance:** Every documented setting is reachable and functional.
- **QA (HW):** Walk every pane and exercise every control; screenshot each pane. Evidence: `.omo/evidence/task-60-notchflow-v1/`.
- **Commit:** `feat(settings): add settings window`

### 61. Implement the first-run onboarding flow
Welcome, permission explanation, agent detection and hook offer, done — per `docs/08`.
- **Acceptance:** Shown exactly once on first launch; skippable; never requests a permission the user has not opted into.
- **QA (HW):** Reset the defaults domain and launch; confirm the flow and that no permission prompt appears unless a feature is enabled. Evidence: `.omo/evidence/task-61-notchflow-v1/`.
- **Commit:** `feat(onboarding): add first-run setup flow`

### 62. Add the String Catalog and extract every user-visible string
Create the `.xcstrings` catalog; move every user-visible literal into it; add the lint rule enforcement from todo 19.
- **Acceptance:** The lint rule reports zero hardcoded user-visible strings.
- **QA (CI):** `swiftlint --strict` passes with the custom rule enabled. Evidence: `.omo/evidence/task-62-notchflow-v1.log`.
- **Commit:** `feat(i18n): add string catalog and extract strings`

### 63. Add the Turkish localization
Translate every catalog entry; ensure date, duration, and number formatting is locale-driven rather than hardcoded.
- **Acceptance:** No untranslated key remains; the UI is legible in Turkish without truncation.
- **QA (CI + HW):** A script asserts zero missing translations; on hardware, run in Turkish and screenshot every surface. Evidence: `.omo/evidence/task-63-notchflow-v1/`.
- **Commit:** `feat(i18n): add Turkish localization`

### 64. Implement the permission request flow
Lazy, explained, per-feature requests with graceful degradation on denial, per `docs/09`.
- **Acceptance:** No permission is requested at launch; denying any permission disables only the dependent feature, with an explanatory state in settings.
- **QA (HW):** Fresh install, launch, confirm no prompts; enable each feature in turn and confirm one explained prompt each; deny each and confirm graceful degradation. Evidence: `.omo/evidence/task-64-notchflow-v1/`.
- **Commit:** `feat(permissions): add lazy permission flow with graceful degradation`

### 65. Add the app icon and visual assets
App icon at all required sizes, status item symbol, and any activity glyphs, in light and dark variants.
- **Acceptance:** No missing icon size; the status item renders correctly in both appearances and in the menu bar's reduced contrast.
- **QA (CI + HW):** Asset validation in the build; screenshots of the status item in both appearances. Evidence: `.omo/evidence/task-65-notchflow-v1/`.
- **Commit:** `feat(assets): add app icon and visual assets`

## Verification tiers

Per the plan's verification strategy: `CI` is verifiable headlessly by `xcodebuild test` / a script on a GitHub Actions macOS runner; `HW` requires the physical notched MacBook plus one external monitor and is collected into the Final Verification Wave.

| Todo | Tier |
|---|---|
| 59 | CI |
| 60 | HW |
| 61 | HW |
| 62 | CI |
| 63 | CI + HW |
| 64 | HW |
| 65 | CI + HW |

## Source references

- `docs/08-settings-and-localization.md` — settings table, persistence rules, settings window layout, onboarding flow, localization mechanism and rules.
- `docs/09-security-privacy-permissions.md` — permission request flow and graceful degradation.
- `.omo/plans/notchflow-v1.md` — Wave 6 (lines 459–501), dependency matrix (lines 84–95).
