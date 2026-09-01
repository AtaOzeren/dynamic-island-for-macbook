# Phase 0: Documentation

**Status:** DONE
**Todos:** 1-16 (Wave 0)
**Depends on:** Nothing. The inputs were `draft.md` and the plan itself; this wave wrote the spec before any code existed.
**Unblocks:** Every later phase. The plan gates Wave 2 on this wave finishing, because these documents are the spec the code is checked against. Concretely: the architecture guard (todo 20) enforces the dependency rule stated in `docs/01`, the lint and format configuration (todo 19) follows the conventions in `docs/14`, CI (todo 22) re-runs the docs consistency checks introduced here, and the performance script (todo 66) asserts the numbers fixed in `docs/02`.

## What this phase delivers

The complete pre-implementation specification: the `docs/README.md` index plus fifteen numbered documents, one per todo. Together they fix the product scope (`00`, `13`), the architecture and its dependency rule (`01`), the measurable idle-cost budget (`02`), notch detection and display selection (`03`), the overlay panel (`04`), the activity model and its providers (`05`, `06`), the AI status protocol (`07`), the settings surface and localization rules (`08`), the privacy stance and entitlements (`09`), the dual build and release pipeline (`10`), the testing strategy (`11`), the API feasibility research record (`12`), and the shared vocabulary and conventions (`14`).

The plan's execution strategy shapes this wave: fully parallel, sixteen independent files, no code dependency, no ordering between todos. Nothing here is code. Every file is a contract that later todos either implement (the geometry formula, the `Activity` protocol, the IPC schema) or enforce (the dependency rule, the performance numbers, the naming rules). Every todo's QA is a CI-tier structural check: file counts, link resolution, keyword greps, table-shape assertions.

## Todos

### 1. Create `docs/README.md` as the documentation index

The tagline, the statement that this folder is a pre-implementation design specification containing no code, a table of contents linking all fifteen documents with a one-line description each, and the "five decisions everything depends on": dual distribution from one codebase, the split music provider and why the App Store build cannot contain MediaRemote, idle means genuinely idle, the screen is never looked at, and AI status as the differentiator with no model ever running in NotchFlow. Plus a pointer to the executable plan, the MIT note, and the naming note that Apple marks are not used.

- **Acceptance:** File exists; all fifteen sibling documents are linked and every link resolves.
- **QA (CI):** Count of `docs/*.md` (the index plus fifteen documents) and a link-check script resolving every relative link in `docs/README.md`, non-zero exit on any miss. Evidence: `.omo/evidence/task-1-notchflow-v1.txt`.
- **Commit:** `docs(readme): add documentation index`

### 2. Create `docs/00-product-overview.md`

What NotchFlow is, who it is for (MacBook owners with a notch; developers using AI coding agents), the problem statement, and explicit non-goals. The full V1 feature list restated as user-visible capabilities, and a "what V1 deliberately excludes" section listing incoming calls, AirDrop progress, third-party download progress, and the V1.5/V2 items, each with a one-line reason linking to `13-deferred-backlog.md`. Success criteria in user terms.

- **Acceptance:** Every V1 feature in `draft.md:222-285` appears in the included or the excluded list; nothing is silently dropped.
- **QA (CI):** Keyword greps for the ten V1 feature terms (music, timer, stopwatch, screen recording, audio recording, charging, AI, multi-activity, call, AirDrop), plus a manual read-back diff against `draft.md` recorded in evidence. Evidence: `.omo/evidence/task-2-notchflow-v1.txt`.
- **Commit:** `docs(overview): add product overview and V1 scope`

### 3. Create `docs/01-architecture.md`

The module graph as diagram and table: `NotchFlowCore` (pure Swift, zero AppKit/SwiftUI import), `NotchFlowProviders`, `NotchFlowUI`, and the `NotchFlow` app target as composition root only. The dependency rule stated as an enforceable invariant: dependencies point inward and `NotchFlowCore` imports nothing but Foundation. The end-to-end event flow, a sequence diagram for a track change during a running timer, and the threading model (provider callbacks on arbitrary queues hop to a `@MainActor` `ActivityManager`).

- **Acceptance:** The dependency rule is stated as an enforceable invariant with the enforcement mechanism named.
- **QA (CI):** Document contains the four module names and "imports nothing but Foundation" (or equivalent); this is the invariant todo 20's guard script enforces. Evidence transcript absent from `.omo/evidence/`; the check re-runs against the file.
- **Commit:** `docs(architecture): add module graph and event flow`

### 4. Create `docs/02-performance-contract.md`

The numeric idle budget as a table: CPU < 0.1% averaged over 60s, wakeups < 1/s, resident memory < 60 MB, no continuously committed GPU frames while compact-idle, energy impact "Low". A forbidden-patterns list with a one-line reason each (`while true`, repeating `Timer` while idle, periodic re-query, screen scanning, animation while idle, unnecessary network, retained render loop) and the required patterns (OS notifications, leeway'd `DispatchSourceTimer` only while a time-based activity is visible, static compact content, passive `NSEvent` monitors, narrow `ProcessInfo.beginActivity`). The measurement protocol with exact commands, and the statement that todo 66 asserts these numbers automatically.

- **Acceptance:** Every budget line has a number and a measurement command; no aspirational language without a threshold.
- **QA (CI):** Script asserts at least five numeric budget lines and copy-pasteable measurement commands. Evidence: `.omo/evidence/task-4-notchflow-v1.txt`.
- **Commit:** `docs(performance): add measurable idle-cost contract`

### 5. Create `docs/03-display-and-notch.md`

Identifying the built-in notched display via `NSScreen.safeAreaInsets`, and the exact notch rectangle formula as a pure function over four inputs (`frame`, `safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`) so it is unit-testable without a live screen. The no-notch degraded mode (anchor to the top-centre of the menu bar), the notification sources for reacting without polling, the display-selection policy as a state table over screens-present × user-setting, and the edge cases: clamshell, mirroring, a display appearing before its `localizedName` exists.

- **Acceptance:** The geometry formula is expressed as a pure function signature; the state table is complete over its inputs.
- **QA (CI):** Document contains the four-input function signature and a state table with at least six rows. Evidence: `.omo/evidence/task-5-notchflow-v1.txt`.
- **Commit:** `docs(display): specify notch detection and geometry`

### 6. Create `docs/04-overlay-window.md`

The `NSPanel` specification as a property table (style mask, floating level above the menu bar, clear opaque-free background, collection behavior, `ignoresMouseEvents` toggled by state), each property with one line on what breaks if it is wrong. The three visual states with geometry (hidden, compact pill, expanded panel), the sizing strategy of animating SwiftUI content inside a fixed maximum-bounds window rather than resizing per frame, the interaction rules (hover to peek, click to expand, Escape or outside click to collapse, never stealing menu-bar clicks while collapsed), animation parameters, behaviour over full-screen apps and Spaces, and the accessibility appearance settings.

- **Acceptance:** Every listed property has a stated value and a failure mode.
- **QA (CI):** Structural script check over the property table and the visual-state list. Evidence: `.omo/evidence/task-6-notchflow-v1.txt`.
- **Commit:** `docs(overlay): specify the notch panel window`

### 7. Create `docs/05-activity-model.md`

The `Activity` protocol in full: identity, kind, priority, lifecycle, compact and expanded view builders, optional auto-dismiss, optional primary action. The `ActivityPriority` enum with the V1 assignment table (AI needs-input high, AI completed high and auto-dismissing, recording high, timer expiring high, charging normal and auto-dismissing, music low). The `ActivityManager` contract: registration, deduplication by identity, ordering, the compact-view overflow rule, expanded shows all active ordered, and the hidden/compact/expanded transition rules. The guarantee that an empty activity set collapses to a static compact island without timers or animation, which keeps the island present while preserving the idle budget. A worked music + timer + transfer example, and a contributor extension guide.

- **Acceptance:** The priority table covers every V1 activity; the overflow rule is unambiguous.
- **QA (CI):** Document contains the protocol member list and a priority table with a row per V1 activity kind. Evidence: `.omo/evidence/task-7-notchflow-v1.txt`.
- **Commit:** `docs(activities): specify the activity protocol and manager`

### 8. Create `docs/06-activity-providers.md`

One section per V1 provider, each stating the event source, exact API, permission needs, produced activity, priority, update cadence, teardown, and CI-vs-hardware verifiability. Music gets the longest section: the `MusicProvider` protocol, `AppleScriptMusicProvider` for the App Store build (ScriptingBridge plus distributed notifications, with the honest limitation on browser audio), `MediaRemoteMusicProvider` for the Direct build (dynamically resolved, never linked), compile-time selection, and the prohibition on any MediaRemote symbol in the App Store binary (Guideline 2.5.1). Timer/stopwatch owns the only repeating tick and only while visible. Screen and audio recording state what is honestly detectable. Charging uses IOKit with the never-display-a-persistent-percentage rule. Closes with the provider × build configuration table.

- **Acceptance:** The music section states the App Store constraint and its guideline; every provider has a permission line, even "none".
- **QA (CI):** Document contains a section per provider and the string "2.5.1"; a script asserts the provider × build table has a row per provider. Evidence: `.omo/evidence/task-8-notchflow-v1.txt`.
- **Commit:** `docs(providers): specify V1 activity providers and the music split`

### 9. Create `docs/07-ai-integration.md`

The design principle first: NotchFlow is a status surface, runs no model, holds no API key, never reads the screen. The seven-state agent state machine (idle, thinking, working, using tool, waiting for user, completed, error) with legal transitions and renderings. The versioned IPC contract: message envelope, JSON schema, and two transports (a custom URL scheme via `open -g`, and a loopback HTTP listener on an ephemeral port), with preference order and the loopback security rules (validation, rate limit, size limit, per-agent opt-in). Per-agent sections for Claude Code hooks, Codex CLI notify, and OpenCode plugins with the exact snippets generated. The consent-based hook installer UX with backup and uninstall, the sandbox difference (manual copy-paste in App Store vs direct write in Direct), the privacy statement, and why agents with no public status hook are not in V1.

- **Acceptance:** The message schema is fully specified with every field typed; the consent-before-writing rule is unambiguous.
- **QA (CI):** Document contains a JSON schema block, the seven state names, and the three agent sections. Evidence: `.omo/evidence/task-9-notchflow-v1.txt`.
- **Commit:** `docs(ai): specify the AI status protocol and hook installers`

### 10. Create `docs/08-settings-and-localization.md`

The complete settings surface as a table (setting, type, default, persistence key, where it appears) covering display target, launch at login, appearance, provider toggles, per-agent and per-event AI toggles, hook installation status, and the about pane. Persistence via a typed `UserDefaults` wrapper with a key convention, a migration policy, and safe defaults. The SwiftUI settings scene and the first-run onboarding flow. Localization through String Catalogs, `String(localized:)`, the enforceable no-hardcoded-user-visible-strings rule, plurals and per-locale formatting, RTL readiness, and the ship set (English, Turkish) with a contributor guide for new languages.

- **Acceptance:** Every setting has a default value; the no-hardcoded-strings rule is stated as an enforceable lint.
- **QA (CI):** Document contains a settings table with a defaults column and the string `.xcstrings`. Evidence: `.omo/evidence/task-10-notchflow-v1.txt`.
- **Commit:** `docs(settings): specify preferences and localization`

### 11. Create `docs/09-security-privacy-permissions.md`

The privacy stance up front: nothing collected, nothing sent off-device, no analytics, the only socket is loopback. The entitlements table per build configuration with justification and user-visible consequence for each row, plus the explicit not-requested list: no camera, no microphone recording, no screen recording, no Accessibility, no full disk access, no contacts, no location. Nothing is requested at launch; permissions are asked lazily with a plain-language explanation before the system prompt, and every feature degrades gracefully when denied. Verbatim purpose strings in English and Turkish, the loopback threat model and mitigations, the hook-installer trust model (consent, visible diff, backup, full uninstall), the data-at-rest statement, and the privacy-policy text reused for App Store Connect.

- **Acceptance:** Every entitlement in either build appears with a justification; the not-requested list is present.
- **QA (CI):** Document contains the per-build entitlements table, the not-requested list, and the verbatim purpose strings. Evidence: `.omo/evidence/task-11-notchflow-v1.txt`.
- **Commit:** `docs(security): specify entitlements, permissions and threat model`

### 12. Create `docs/10-build-and-distribution.md`

The two configurations side by side: `AppStore` (sandboxed, no private frameworks, AppleScript music provider, IPC-only AI) and `Direct` (Developer ID signed and notarized, MediaRemote music provider, `.dmg` on GitHub Releases, Homebrew Cask). How the split is implemented (build configurations, Swift compilation conditions, per-configuration entitlements, separate schemes, the forbidden-symbol build guard), version and build-number policy, the App Store pipeline including privacy label answers and review notes, the Direct pipeline through `notarytool` and stapling, and the blocked-on-membership note marking every signing and submission step gated on the Apple Developer Program while local development continues with ad-hoc signing. Plus a signing and notarization troubleshooting section.

- **Acceptance:** The forbidden-symbol guard is specified concretely enough to implement; every paid-membership step is marked.
- **QA (CI):** Script asserts at least three steps are marked as membership-gated. Evidence: `.omo/evidence/task-12-notchflow-v1.txt`.
- **Commit:** `docs(distribution): specify dual build and release pipelines`

### 13. Create `docs/11-testing-strategy.md`

The TDD boundary stated precisely: mandatory for `NotchFlowCore` and every pure function elsewhere, tests-after acceptable for AppKit/SwiftUI glue. The Swift Testing framework choice and XCTest coexistence policy. How event-driven code is tested (every system dependency behind a protocol, tests inject a faking emitter, with a worked screen-parameters example) and how geometry is tested without a notch (four injected values over the machine matrix). The exhaustive two-column CI/HW verifiability matrix, the numbered hardware checklist with an expected observation per step, CI configuration (pinned runner and Xcode, lint and format gates, `xcbeautify`), the definition of done, and the anti-fake-pass list: no empty-assertion tests, no grep-as-verification for behavioural claims, no completion on a worker's self-report.

- **Acceptance:** The matrix accounts for every V1 feature; the hardware checklist is numbered and observable.
- **QA (CI):** Document contains a two-column matrix with at least ten entries per column and a numbered hardware checklist. Evidence: `.omo/evidence/task-13-notchflow-v1.txt`.
- **Commit:** `docs(testing): specify TDD boundary and verification tiers`

### 14. Create `docs/12-api-feasibility-matrix.md`

The research record, so settled questions stay settled: one row per needed capability with the API, minimum macOS version, public or private, entitlement, sandbox behavior, Direct-build behavior, and a source link, covering every system touch point from notch detection through loopback listening. Each row ends in one of four verdicts: public API, feasible only unsandboxed, sandbox-blocked, or impossible. Contested rows get an evidence paragraph, especially why MediaRemote cannot ship in the App Store build, why incoming calls are impossible on macOS, and why AirDrop and transfer progress are not observable. A dated "as researched" header with an instruction to re-verify rows older than a year.

- **Acceptance:** Every capability referenced anywhere in `docs/` appears as a row; every row has a verdict and a source.
- **QA (CI):** Script asserts at least twenty rows and that every verdict cell matches one of the four allowed verdicts. Evidence: `.omo/evidence/task-14-notchflow-v1.txt`.
- **Commit:** `docs(feasibility): record the macOS API feasibility matrix`

### 15. Create `docs/13-deferred-backlog.md`

The standing note that postponed is not cancelled. One section per deferred item in a uniform shape: what the feature is, why it is not in V1 (the specific API gap), what would have to become true, and how much work it would then be. Covers incoming calls, AirDrop progress, third-party download and transfer progress, a NotchFlow drop shelf as a partial substitute, and the draft's V1.5 and V2 sets. A revisit-trigger list (macOS release notes, new public frameworks) and the consistency rule keeping this document and the exclusion list in `00-product-overview.md` in agreement.

- **Acceptance:** Every item excluded in `00-product-overview.md` has a matching section here.
- **QA (CI):** A consistency script cross-checks the overview's exclusion list against the section headings and fails on a mismatch. Evidence: `.omo/evidence/task-15-notchflow-v1.txt`.
- **Commit:** `docs(backlog): record deferred features and revisit triggers`

### 16. Create `docs/14-glossary-and-conventions.md`

One vocabulary for code and docs: island, notch, compact, expanded, activity, provider, agent, session, slot, overflow. Product naming rules: NotchFlow everywhere, Apple's marks never in the product name, bundle identifier, or App Store metadata, and how to refer to the concept in prose. Code conventions: Swift API design guidelines, the lint and format configuration summary, one type per file, the file-length policy, internal-by-default access control, the comment policy (why, never what or when; history belongs in git), and the Swift 6 concurrency hop pattern. Git conventions: Conventional Commits with the type list, branch naming, the pull-request checklist. Documentation conventions, including the rule that a code change contradicting a document updates the document in the same commit.

- **Acceptance:** The commit convention matches the one used by every todo in the plan; the comment policy is stated.
- **QA (CI):** Document contains the Conventional Commits type list and the naming prohibition. Evidence: `.omo/evidence/task-16-notchflow-v1.txt`.
- **Commit:** `docs(conventions): add glossary, naming and code conventions`

## Verification

All sixteen todos are CI-tier: headless structural checks, no build, no hardware. The phase is complete: every checkbox is ticked in the plan and all sixteen documentation commits are in history, ending with `docs(readme): add documentation index`.

QA transcripts live at `.omo/evidence/task-<N>-notchflow-v1.txt` for fifteen of the sixteen todos. Todo 3's transcript is the one gap: its deliverable and commit are in place, and its check (the four module names plus the Foundation-only dependency rule) re-runs directly against `docs/01-architecture.md`.

Still re-runnable today:

```
ls docs/*.md | wc -l        # 16: the index plus fifteen documents
grep -c "2.5.1" docs/06-activity-providers.md
grep -c "xcstrings" docs/08-settings-and-localization.md
```

Relative-link resolution over `docs/README.md`, the keyword greps over `docs/00-product-overview.md`, and the exclusion cross-check between `00-product-overview.md` and `13-deferred-backlog.md` complete the set. CI (todo 22) re-runs these docs consistency checks on every push once Phase 1 lands.
