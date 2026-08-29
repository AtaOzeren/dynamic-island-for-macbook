# Phase 1 — Project Foundation

**Status:** NOT STARTED
**Todos:** 17–23 (Wave 1)
**Depends on:** Phase 0 (nothing code-related; Wave 1 can run alongside Wave 0's documentation work).
**Unblocks:** Every later phase. Todo 17 specifically gates Wave 2 (Phase 2) — `NotchFlowCore` and its test target must exist before any TDD work can start. The plan's dependency matrix marks this "2-wide after todo 17": once the skeleton exists, the remaining six todos have no ordering constraint on each other.

## What this phase delivers

The scaffolding everything else builds on: the Xcode project and SPM package skeleton, licensing and contributor docs, lint/format configuration, two architecture guard scripts (module dependency rule, forbidden-symbol check), the CI workflow, and the app's basic runtime shape as a Dock-less accessory app with launch-at-login. Nothing here is user-facing feature work — it is the machinery that lets every subsequent phase be verified automatically.

The plan calls this wave "sequential-ish": todo 17 must land first because every other todo in the wave, and every todo in every later wave, needs the project and package structure it creates. The remaining six todos (18–23) are otherwise independent of each other.

## Todos

### 17. Create the Xcode project and SPM package skeleton

Create an Xcode project for a macOS app named `NotchFlow`, deployment target macOS 14.0, Swift 6 language mode with strict concurrency. Create a local Swift package containing three library targets — `NotchFlowCore`, `NotchFlowProviders`, `NotchFlowUI` — plus three matching test targets. `NotchFlowCore` must declare no dependencies beyond Foundation. Wire the app target to depend on all three. Add `.gitignore` for Xcode/SPM artifacts.

- **Acceptance:** `xcodebuild -scheme NotchFlow build` succeeds; `swift test` runs (zero tests is acceptable at this point); `NotchFlowCore` compiles without importing AppKit.
- **QA (CI):** Run the build and the test command; capture both exit codes. Evidence: `.omo/evidence/task-17-notchflow-v1.log`.
- **Commit:** `build: scaffold Xcode project and SPM modules`

### 18. Add MIT `LICENSE`, root `README.md`, `CONTRIBUTING.md`

`LICENSE`: MIT, current year, the author's name. `README.md`: what NotchFlow is, a screenshot placeholder, install instructions for both channels marked "coming soon", a build-from-source section, a link to `docs/`, and the license and naming notes. `CONTRIBUTING.md`: how to build, the TDD expectation for core code, the commit convention, and the pull-request checklist.

- **Acceptance:** `LICENSE` is the verbatim MIT text; `README.md` links to `docs/README.md`.
- **QA (CI):** Link check on `README.md`; assert `LICENSE` contains the MIT permission clause. Evidence: `.omo/evidence/task-18-notchflow-v1.txt`.
- **Commit:** `docs: add license, readme and contribution guide`

### 19. Configure `swiftlint` and `swift-format`

Add configuration files matching the conventions in `docs/14`. Include a custom rule that flags user-visible string literals in view files, supporting the localization rule.

- **Acceptance:** Both tools run clean on the current tree.
- **QA (CI):** `swiftlint --strict` and the format check both exit zero. Evidence: `.omo/evidence/task-19-notchflow-v1.log`.
- **Commit:** `build: add lint and format configuration`

### 20. Add the architecture guard script

A script that fails if `NotchFlowCore` sources import AppKit, SwiftUI, or any provider module — enforcing the dependency rule from `docs/01`.

- **Acceptance:** The script passes on the current tree and fails when a deliberate violating import is introduced in a scratch file.
- **QA (CI):** Run both the passing case and the deliberately-failing case; assert exit codes zero and non-zero respectively. Evidence: `.omo/evidence/task-20-notchflow-v1.log`.
- **Commit:** `build: enforce core module dependency rule`

### 21. Add the forbidden-symbol guard script

A script that inspects a built binary and fails if any `MediaRemote` or `MRMediaRemote` symbol or string is present. Wired to run for the `AppStore` configuration only.

- **Acceptance:** Passes for a stub `AppStore` build; fails for a stub binary containing the symbol.
- **QA (CI):** Both cases executed with asserted exit codes. Evidence: `.omo/evidence/task-21-notchflow-v1.log`.
- **Commit:** `build: guard the App Store build against private framework symbols`

### 22. Add the GitHub Actions CI workflow

Jobs: build both configurations, run all tests, run lint, run the architecture guard, run the forbidden-symbol guard, and run the docs consistency checks from Wave 0. Pin the runner image and Xcode version. Use `xcbeautify` for readable logs. Upload test results and coverage as artifacts.

- **Acceptance:** The workflow passes on the current tree.
- **QA (CI):** The workflow run itself is the evidence; record the run URL and conclusion. Evidence: `.omo/evidence/task-22-notchflow-v1.txt`.
- **Commit:** `ci: add build, test and guard workflow`

### 23. Configure the app as an accessory app with launch-at-login

Set `LSUIElement`, set the activation policy to accessory, add a status item that opens settings and quits, and implement launch-at-login via `SMAppService.mainApp` with a settings toggle that reflects the real registration state.

- **Acceptance:** The app launches with no Dock icon and no window; the status item appears; toggling launch-at-login changes and correctly reports the registration state.
- **QA (HW):** Launch, observe no Dock icon, toggle the setting twice, and read back the service status each time. Evidence: screenshots plus status output at `.omo/evidence/task-23-notchflow-v1/`.
- **Commit:** `feat(app): run as accessory app with launch-at-login`

## Verification

Six of the seven todos are `CI` tier — headless, no hardware. Todo 23 is `HW` tier and belongs in the Final Verification Wave's scripted checklist as well as being checked here. The full phase check:

```bash
xcodebuild -scheme NotchFlow build
swift test
swiftlint --strict
swift-format lint --recursive .
./scripts/guard-core-dependencies.sh
./scripts/guard-forbidden-symbols.sh
```

Todo 22's own check is the CI workflow run itself — there is no local equivalent. Todo 23 has no CI command; it is verified on the physical hardware matrix in the Final Verification Wave.

Phase 1 is DONE when all six CI-tier todos pass locally and in the GitHub Actions workflow, the HW-tier todo 23 has recorded screenshot and status evidence, and each todo's evidence file exists under `.omo/evidence/`.
