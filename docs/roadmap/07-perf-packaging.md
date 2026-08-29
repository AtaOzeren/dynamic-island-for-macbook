# Phase 7 — Performance, Packaging, Distribution

**Status:** NOT STARTED
**Todos:** 66–74 (Wave 7)
**Depends on:** Phase 6 — the plan places this wave last because it needs a feature-complete app: every provider wired in, every AI integration point live, and settings/localization done, so the idle-cost measurement and the packaging artifacts reflect the real shipped surface.
**Unblocks:** Phase F (Final Verification Wave) — the hardware matrix and release checks in the final wave assume the performance budget is already met and both build configurations already exist.

## What this phase delivers

The last wave before ship: proof that the app is actually cheap when idle, both distributable artifacts (a notarizable `.dmg` for Direct, a submittable archive for the App Store), the Homebrew Cask, the store metadata and privacy policy, a tag-triggered release workflow, and a final pass reconciling the 15 `docs/` files against whatever actually got built along the way.

Three of the nine todos — 70, 71, 72 — are marked `BLOCKED-ON-MEMBERSHIP` in the plan. They are not skipped: each produces everything an Apple Developer Program membership doesn't gate (a `.dmg` with ad-hoc signing, a locally-audited Cask, a validated local archive) and explicitly reports the membership-dependent step as skipped rather than pretending it succeeded. The remaining six todos have no such gate.

## Todos

### 66. Implement the performance measurement script

A script that launches the app, waits for idle, samples for the documented duration, and asserts the `docs/02` thresholds for CPU, wakeups, and memory, failing non-zero on a breach.

- **Acceptance:** The script runs unattended and produces a machine-readable result plus a human summary.
- **QA (HW):** Run on the notched MacBook with no activities; capture the report.
- **Evidence:** `.omo/evidence/task-66-notchflow-v1/`
- **Commit:** `test(perf): add idle cost measurement script`

### 67. Meet the idle performance budget

Profile and fix until the script from todo 66 passes. Expected work: eliminating any retained observer, confirming the window is truly ordered out, removing incidental timers, and verifying App Nap cooperation.

- **Acceptance:** Todo 66's script passes on real hardware with every provider enabled and no activity present.
- **QA (HW):** The script's passing report, plus an Instruments capture confirming no periodic work.
- **Evidence:** `.omo/evidence/task-67-notchflow-v1/`
- **Commit:** `perf: meet the idle cost budget`

### 68. Author both entitlements files and both build configurations

Per `docs/09` and `docs/10`, with the guards from todos 20 and 21 wired into both.

- **Acceptance:** Both configurations build; the App Store configuration passes the symbol guard; each entitlement present is justified in `docs/09`.
- **QA (CI):** Build both; run both guards; diff the effective entitlements against the documented table.
- **Evidence:** `.omo/evidence/task-68-notchflow-v1.log`
- **Commit:** `build: add per-configuration entitlements`

### 69. Write the privacy policy and App Store metadata

Privacy policy file in the repository, plus the App Store description, keywords, review notes explaining the overlay window and the absence of private API, and the privacy nutrition label answers — all localized.

- **Acceptance:** The privacy policy matches the actual data behaviour described in `docs/09`; review notes address the overlay question directly.
- **QA (CI):** Consistency check between the privacy policy claims and the entitlements table.
- **Evidence:** `.omo/evidence/task-69-notchflow-v1.txt`
- **Commit:** `docs(store): add privacy policy and App Store metadata`

### 70. Implement the Direct build packaging pipeline — BLOCKED-ON-MEMBERSHIP for signing

Script producing a `.dmg`: build, sign with Developer ID, enable the hardened runtime, submit to `notarytool`, staple, and package. Until the membership exists, the script runs end-to-end with ad-hoc signing and clearly reports the signing steps as skipped.

- **Acceptance:** The script produces a mountable `.dmg` today; every membership-dependent step is explicitly reported as skipped rather than silently omitted.
- **QA (HW):** Run the script; mount the `.dmg`; confirm the skipped-step report.
- **Evidence:** `.omo/evidence/task-70-notchflow-v1/`
- **Commit:** `build: add direct distribution packaging pipeline`

### 71. Prepare the Homebrew Cask definition — BLOCKED-ON-MEMBERSHIP for submission

The cask file with the correct stanzas, plus the submission checklist. Submission itself waits on a notarized release.

- **Acceptance:** The cask file is syntactically valid and passes local audit against a locally-produced artifact.
- **QA (CI):** Run the cask audit; capture output.
- **Evidence:** `.omo/evidence/task-71-notchflow-v1.log`
- **Commit:** `build: add homebrew cask definition`

### 72. Prepare the App Store submission — BLOCKED-ON-MEMBERSHIP

Archive the App Store configuration, run the full validation locally, and assemble screenshots and metadata. Actual upload waits on the membership.

- **Acceptance:** A validated archive exists locally with zero validation errors; the screenshot set is complete for every required size.
- **QA (HW):** Produce the archive and run validation; capture the report.
- **Evidence:** `.omo/evidence/task-72-notchflow-v1/`
- **Commit:** `build: prepare App Store submission artifacts`

### 73. Add the release workflow

A tag-triggered GitHub Actions workflow producing the `.dmg`, attaching it to a release, and generating release notes. Signing steps are conditional on the secrets existing, so the workflow is usable before and after the membership.

- **Acceptance:** A dry-run on a test tag produces an artifact; the workflow does not fail merely because signing secrets are absent.
- **QA (CI):** Trigger on a test tag; record the run conclusion and artifact.
- **Evidence:** `.omo/evidence/task-73-notchflow-v1.txt`
- **Commit:** `ci: add release workflow`

### 74. Reconcile documentation with the implementation

Re-read all 15 documents against the shipped code and correct every divergence. Update `docs/12` with anything learned during implementation, and update `docs/13` if any deferred item's status changed.

- **Acceptance:** No document contradicts the code. Every API row in `docs/12` reflects what was actually built.
- **QA (CI):** The docs consistency scripts pass; a reviewer diff of each document against the corresponding implementation is recorded.
- **Evidence:** `.omo/evidence/task-74-notchflow-v1.txt`
- **Commit:** `docs: reconcile specification with implementation`

## Verification

Six of the nine todos are `CI` tier; three (66, 67, 70, 72 — the idle-cost measurement and the two artifact-producing todos that touch real signing state) are `HW` tier and need the physical notched MacBook.

CI-tier, runnable unattended:

```bash
# 68 — both configurations build, both guards pass
xcodebuild -scheme NotchFlow -configuration AppStore build
xcodebuild -scheme NotchFlow -configuration Direct build
./Scripts/guard-core-imports.sh
./Scripts/guard-forbidden-symbols.sh

# 69 — privacy policy matches entitlements
./Scripts/check-privacy-consistency.sh

# 71 — cask audit
brew audit --cask --online Casks/notchflow.rb

# 73 — release workflow dry run (test tag)
gh workflow run release.yml --ref <test-tag>

# 74 — docs consistency
./Scripts/check-docs-consistency.sh
```

HW-tier, on the notched MacBook:

```bash
# 66/67 — idle cost script; must pass with every provider enabled, no activity present
./Scripts/measure-idle-cost.sh

# 70 — Direct packaging pipeline, ad-hoc signed until membership exists
./Scripts/package-dmg.sh
hdiutil attach NotchFlow.dmg   # confirm it mounts; check the skipped-step report

# 72 — App Store archive validation
xcodebuild -scheme NotchFlow -configuration AppStore archive -archivePath build/NotchFlow.xcarchive
xcodebuild -exportArchive -archivePath build/NotchFlow.xcarchive -exportOptionsPlist ExportOptions-AppStore.plist
```

Every command's exact invocation and pass criteria live in `docs/02` (performance budget), `docs/09` (entitlements and privacy), and `docs/10` (build and distribution) — this file only maps plan todos to the commands that verify them.
