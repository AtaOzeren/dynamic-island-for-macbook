# NotchFlow — Composition & Wiring Audit / Repair Task

## Context

Repository: `dynamic-island-for-macbook` (product name **NotchFlow**), a macOS 14+ menu-bar/notch
overlay app. Swift 6.2, Xcode 26. Branch `01-foundation`.

Module layout, per `docs/01-architecture.md`:

| Module | Role |
|---|---|
| `NotchFlowCore` | Pure logic. Imports nothing but Foundation. |
| `NotchFlowProviders` | System-framework integrations (MediaRemote, IOKit, ScreenCaptureKit, file-system installers). |
| `NotchFlowUI` | SwiftUI views + the `NSPanel` overlay controller. |
| `NotchFlow` (app target) | **Composition root only** — wires providers to the manager and the manager to the UI. Contains no business logic. |

### The defect class you are hunting

This project has a systematic, repeating defect: **components are fully implemented and
unit-tested inside the library modules, but the app target never instantiates them.** The test
suite passes, CI is green, guard scripts pass — because every test drives the class directly and
nothing asserts that the shipping app actually uses it.

A previous session already fixed part of this. Your job is to finish it, and to look for further
instances of the same class of defect that neither of us has found yet.

**Do not trust "task complete" markers in `docs/roadmap/` or evidence files in `.omo/evidence/`.**
At least one task (todo 23) is marked done while its stated acceptance criteria were never
implemented, because the recorded evidence checked something unrelated.

---

## Already fixed — do NOT redo these

These landed in the working tree (uncommitted). Read the diff before you start:
`git diff` plus the untracked file `NotchFlow/IslandPresenter.swift`.

1. **`MenuBarExtra` status item** added in `NotchFlow/NotchFlowApp.swift` — "Settings…" via
   `SettingsLink` + "Quit NotchFlow". Uses the existing `MenuBarIcon` template imageset.
2. **`NotchFlow/IslandPresenter.swift`** (new) — composes `NotchPanel` +
   `PresentationController` + `SystemMouseLocationObserver` + a screen adapter, and binds an
   `IslandViewModel` so the panel re-renders on activity changes. The notch now actually draws.
3. **`PresentationController.onSynchronize`** — new additive public callback in
   `Sources/NotchFlowUI/PresentationController.swift`, fired at the end of `synchronize()`, so a
   presenter can refresh content on changes that do not move the panel between states.
4. **`URLSchemeAppDelegate`** in `NotchFlow/URLSchemeReceiver.swift` + `@NSApplicationDelegateAdaptor`
   — `notchflow://` URLs are now delivered with no window open. Previously `.onOpenURL` was attached
   to the `Settings` scene's content view, which never instantiates unless the user opens Settings,
   so every hook message was dropped.
5. **Receiver preferences seeded from the store** — `urlSchemeReceiver.preferences` was left at
   `AIIntegrationPreferences.default`, which has `enabledAgentIDs = []` (every agent off), so the
   gate rejected 100% of messages. Now seeded in `init` from `settingsStore`.
6. **`onMessage` → `ActivityManager`** — `URLSchemeReceiver.onMessage` was never assigned in
   production. Now converts to `AIAgentActivity(message:)` and calls `register` / `end`.
7. **"Open Settings" button** in onboarding — `NSApp.sendAction` silently failed because an
   accessory app that is not frontmost has an empty responder chain. Now activates first and tries
   both `showSettingsWindow:` and `showPreferencesWindow:`.
8. **Onboarding copy corrected** — the agent step claimed hooks are installed when you finish
   setup; they are not. Toggle relabelled, body text rewritten, both string catalogs updated with
   Turkish translations.

Verified working end to end: with all system providers disabled, sending
`notchflow://ai-status?payload=…` with `state=working` orders the panel on screen, and `state=idle`
orders it out.

---

## Part 1 — Blocking design decision (resolve this first)

### G1. `notchflow-notify` does not exist

`HookSnippetGenerator` (`Sources/NotchFlowCore/HookSnippetGenerator.swift`) takes a
`notifierExecutablePath` and emits hook snippets that invoke that binary directly. **No such
executable exists anywhere in the repository** — no `Package.swift` product, no source file, no
build phase, nothing in the app bundle. The string `notchflow-notify` appears only as a hardcoded
literal in test files.

Consequence: wiring the hook installers into Settings without resolving this would write hook
configuration that silently fails at runtime — worse than not installing at all.

`docs/07-ai-integration.md:127` states the snippet "uses the URL-scheme transport with `open -g`
precisely because it backgrounds trivially from a shell hook" — but the generator emits a direct
binary invocation, not an `open -g` call. **The documentation and the code contradict each other.**

Pick one and make doc and code agree:

- **Option A — ship the notifier.** Add a small executable target (parse `--agent`, `--state`,
  `--session`, build the JSON envelope, percent-encode it, open `notchflow://ai-status?payload=…`),
  add it as a `Package.swift` product, and add a copy-files build phase in
  `NotchFlow.xcodeproj` placing it in `Contents/MacOS/`. Resolve the installed path at runtime from
  `Bundle.main` rather than hardcoding `/Applications/…`.
- **Option B — drop the notifier.** Change `HookSnippetGenerator` to emit
  `open -g "notchflow://ai-status?payload=…"` directly. Update its tests, the three installers, and
  `docs/07-ai-integration.md`.

State which option you chose and why before implementing. Option B is simpler and matches the
existing docs; Option A gives better shell-quoting control and a stable argument surface. Consider
that hook snippets are written into user-owned config files and must be robust to spaces and shell
metacharacters in paths — `IPCMessageValidator` already rejects shell metacharacters in display
text, and `HookSnippetGenerator.shellSingleQuotedNotifierPath()` exists for this reason.

---

## Part 2 — Components implemented and tested but never instantiated

Reproduce the audit yourself before starting, and again when you finish. A type whose only
non-declaration references live under `Tests/` is the signature of this defect:

```bash
python3 - <<'EOF'
import os, re
src, tests = [], []
for root, _, files in os.walk("."):
    if any(p in root for p in (".git", "DerivedData", ".build", "dist", "node_modules")): continue
    for f in files:
        if f.endswith(".swift"):
            p = os.path.join(root, f)
            (tests if "/Tests/" in p else src).append(p)
text = {p: open(p, encoding="utf-8").read() for p in src + tests}
decl = re.compile(r'^\s*public (?:final\s+)?(?:struct|class|actor|enum|protocol)\s+(\w+)', re.M)
symbols = {m.group(1): p for p in src for m in decl.finditer(text[p])}
def count(name, files, home=None):
    pat = re.compile(r'\b%s\b' % re.escape(name)); t = 0
    for p in files:
        n = len(pat.findall(text[p]))
        if p == home:
            n -= len(re.findall(r'\b(?:struct|class|actor|enum|protocol)\s+%s\b' % re.escape(name), text[p]))
        t += n
    return t
for name, home in sorted(symbols.items()):
    prod, t = count(name, src, home), count(name, tests)
    if prod == 0:
        print("%-36s %-56s test=%d" % (name, home.lstrip('./'), t))
EOF
```

At the time of writing this returns 12 entries. Each is listed below.

### G2. Hook installers are unreachable from the UI

`ClaudeCodeHookInstaller`, `CodexHookInstaller`, `OpenCodePluginInstaller`
(`Sources/NotchFlowProviders/`) and `ManualSetupView` (`Sources/NotchFlowUI/ManualSetupView.swift`)
are never referenced by production code.

The intended design is documented in `NotchFlow/NotchFlowApp.swift` (`applyHookOffers` doc comment):
onboarding records consent only, and "the installer's own approval flow — the one Settings uses —
stays the single place bytes reach an agent's configuration file." That Settings flow was never
built. `Sources/NotchFlowUI/AIIntegrationsSettingsView.swift` contains only two `Toggle` rows and no
install affordance.

Build it. All three installers share a uniform API:

```swift
init(homeDirectory: URL = …, notifierExecutablePath: String, fileSystem: … = Foundation…())
func manualSetupInstructions() throws -> ManualSetupInstructions
func install() throws
func uninstall() throws
```

Requirements:

- Per detected agent, show current state (installed / not installed) and an Install / Uninstall
  action. There is currently **no `isInstalled` query** on any installer — the information exists
  internally (`install()` computes a `merged.changed` flag and returns early when false). Add a
  narrow public accessor rather than duplicating the merge logic in the view.
- Before writing, show the exact snippet and require explicit approval. `ManualSetupView` already
  renders `ManualSetupInstructions` (title, summary, numbered steps, snippet, copy button) and is
  documented as "the fallback shown when automatic installation is unavailable or declined" — use
  it for both the approval preview and the manual fallback.
- Surface `install()` / `uninstall()` failures in the UI. Each installer has a typed error enum
  (`ClaudeCodeHookInstallerError`, etc.). Do not swallow them.
- Installers write a `.notchflow-backup` sibling before their first modification and restore from it
  on uninstall. Verify this round-trips against a real file with pre-existing unrelated content.
- Respect `AgentDetector` — only offer agents whose configuration exists.

Depends on **G1**.

### G3. `LoopbackHTTPListener` is never started

`Sources/NotchFlowProviders/LoopbackHTTPListener.swift` is a complete actor implementing the second
IPC transport described in `docs/07-ai-integration.md`, with `LoopbackListenerPolicy` in Core
governing it. Nothing in the app target ever constructs or starts it.

Decide whether V1 ships it. If yes: start it from the composition root, route its messages through
the same sink the URL scheme now uses (`AIAgentActivity` → `ActivityManager`), apply the same
`AIIntegrationPreferences` gate, and shut it down cleanly. If no: say so explicitly and record the
deferral in `docs/13-deferred-backlog.md` rather than leaving dead code that reads as shipped.

**Security note:** this opens a local listening socket. Before enabling it, verify
`LoopbackListenerPolicy` actually binds to loopback only, that it rejects non-local peers, and that
`IPCMessageValidator`'s payload size cap (16 KiB) and field allow-list are enforced on this path too,
not just the URL path.

### G4. `SystemScreenChangeObserver` is never started

`Sources/NotchFlowProviders/SystemScreenChangeObserver.swift` wraps
`NSApplication.didChangeScreenParametersNotification`, `NSWorkspace.willSleepNotification`, and
`didWakeNotification`. Nothing starts it.

Consequence: the overlay panel is positioned when it is ordered in and never re-resolved. Plugging in
or unplugging a display, changing resolution, or waking from sleep can leave the island on the wrong
screen or mispositioned. `docs/03-display-and-notch.md` requires re-resolution on these events.

Wire it to `IslandPresenter`: on a screen change, re-run the screen resolution and call
`panel.reposition(on:)` (and refresh the cached notch size, which `IslandPresenter` derives via
`notchRect(...)`). Note the panel is deliberately never resized during expand/collapse — only on a
display change — per `docs/04-overlay-window.md`.

### G5. Rich per-activity views are never rendered — expanded detail is a stub

These four views exist, are unit-tested, and are rendered by nothing:

| View | File | What is lost |
|---|---|---|
| `MusicExpandedView` | `Sources/NotchFlowUI/MusicActivityView.swift` | Artwork, transport controls (`MusicTransportControl`), track metadata |
| `TimerExpandedView` | `Sources/NotchFlowUI/TimerActivityView.swift` | Timer face, `TimerControlCommand` controls |
| `AIAgentActivityView` | `Sources/NotchFlowUI/AIAgentActivityView.swift` | Agent name, state text, tool name, elapsed time |
| `ChargingActivityView` | `Sources/NotchFlowUI/ChargingActivityView.swift` | Charging detail |

`ExpandedActivityView` instead builds a generic `ExpandedRow` per activity carrying only
`symbolName`, `title` (both from `compactSymbolName(kind)` / `compactAccessibilityLabel(kind)`), and
`primaryAction`. So the expanded island shows an icon and a kind label — not the per-activity detail
the specs describe.

Compare against the render tables in `docs/07-ai-integration.md` (the AI state machine table
specifies compact and expanded renders per state) and `docs/05-activity-model.md`. Make
`ExpandedActivityView` dispatch to the per-kind view for each activity. Keep the existing
`expandedPanelSize` / overflow-scrolling logic working — the panel frame is fixed at
`PanelMetrics.maximumExpandedSize` and content must scroll inside it rather than resize the window.

### G6. `onPrimaryAction` is a no-op, and transport controls have no path to the system

`ExpandedActivityView.onPrimaryAction: (ActivityIdentity) -> Void` defaults to `{ _ in }` and the
composition root passes nothing. `PrimaryAction` (`Sources/NotchFlowCore/PrimaryAction.swift`)
carries only `title` and `symbolName` — **there is no dispatch information in the model**, so the
button cannot be implemented without a design decision.

Same problem for `MusicTransportControl` and `TimerControlCommand`: the value types describe the
button but nothing routes the command to a player or a timer.

Design and implement the dispatch path. Keep `NotchFlowCore` free of AppKit — the command should be
a value in Core and the execution should live in Providers or the composition root. Check whether
`MusicProvider` already exposes transport methods before adding any; if it does not, decide whether
V1 ships read-only music (and record the deferral) or gains playback control.

### G7. `ActivityLifecycle` is unused in production

`Sources/NotchFlowCore/ActivityLifecycle.swift` defines `ActivityLifecycleState`,
`ActivityLifecycleEvent`, and `ActivityLifecycle`, with six test references and zero production
references. `ActivityManager` implements its own dismissal via an internal `dismissTasks` dictionary.

Determine whether this is (a) a state machine `ActivityManager` was meant to use and does not, or
(b) genuinely superseded. If (a), wire it. If (b), delete it — per the project's own clean-code rules
(`G9 — Remove Dead Code`, `F4 — Remove Dead Functions`), superseded code is deleted, not left in
place. Do not leave it in the ambiguous middle.

### G8. `SystemReduceTransparency` is dead

`Sources/NotchFlowUI/IslandAppearance.swift` — zero references anywhere, including tests. Its sibling
`SystemReduceMotion` **is** used (as `PresentationController`'s default `reduceMotion`).

`ExpandedActivityView` reads `@Environment(\.accessibilityReduceTransparency)` directly, which may be
why the injectable seam went unused. Either wire it the way `SystemReduceMotion` is wired (so the
behaviour is testable without changing System Settings), or delete it.

---

## Part 3 — Preference toggles that do nothing

### G9. `launchAtLogin` is a no-op

`docs/roadmap/01-foundation.md` todo 23 requires: *"implement launch-at-login via
`SMAppService.mainApp` with a settings toggle that reflects the real registration state."*

Acceptance criterion: *"toggling launch-at-login changes and correctly reports the registration
state."*

Present state: `GeneralPreferences.launchAtLogin` is stored, `SettingsStore` persists it, and
`GeneralSettingsView` renders a `Toggle` bound to it. **`SMAppService` is never called anywhere in
the repository.** The toggle flips a boolean and nothing else happens.

Implement it. Requirements from the acceptance criterion: the toggle must *reflect the real
registration state*, not the stored boolean — read back `SMAppService.mainApp.status` and reconcile,
because the user can disable the login item in System Settings without the app knowing. Handle
registration failure by surfacing it, not by silently leaving the toggle on.

### G10. Verify every other preference actually takes effect

`launchAtLogin` was not special — it is the shape of bug this codebase produces. Trace each
preference from the toggle to the observable behaviour and prove it works end to end:

- `appearance` (`SettingsAppearance`) → the island panel restyles. A path now exists via
  `IslandPresenter.applyAppearance`, but it is invoked from a `.onChange` on the **Settings scene**,
  which only runs while the settings window is open. Check whether that is sufficient (the user can
  only change it from that window) or whether it needs to be store-observed.
- `displayTarget` (`DisplayPreference`) → the panel moves to the selected display. `IslandPresenter`
  re-reads this on every order-in; verify a change while the island is *already visible* also moves
  it.
- `reducedMotionOverride` → animation curves change. `PresentationController` takes a
  `ReduceMotionQuerying`; check the user's override actually reaches it rather than only the system
  setting.
- `languageOverride` → `applyLanguageOverride` writes `AppleLanguages`. The About pane says it takes
  effect at next launch; verify that is true and that the claim is accurate for all three catalogs.
- The five `providers.*.enabled` switches → `registry.setEnabled` via
  `settingsStore.observeProviderEnablement`. This one looks correctly wired; confirm it.
- `aiIntegrationPreferences` → gates the URL-scheme receiver. Now seeded at launch; confirm live
  edits in the settings window also propagate.

**Watch for the specific trap:** four `.onChange` modifiers in `NotchFlowApp.swift` hang off the
`Settings` scene's content. Anything they drive is inert until the user opens the settings window.
This is exactly what broke URL handling. Audit each one and decide whether it belongs on the store
instead.

---

## Part 4 — Process and QA gaps that let all of this ship

### G11. Recorded evidence does not match acceptance criteria

`.omo/evidence/task-23-notchflow-v1.txt` contains only:

```
=== TASK 23 QA: Entitlements and Export Plists ===
NotchFlow-AppStore.entitlements: OK
NotchFlow-Direct.entitlements: OK
AppStore-ExportOptions.plist: OK
Direct-ExportOptions.plist: OK
```

Todo 23's actual acceptance criteria are *"The app launches with no Dock icon and no window; the
status item appears; toggling launch-at-login changes and correctly reports the registration state."*
None of that was checked. The task was marked complete anyway.

**Audit every file under `.omo/evidence/` against the acceptance criteria of its corresponding todo
in `docs/roadmap/*.md`.** Report every mismatch. Expect more than one. Do not silently fix the
evidence files — report which tasks are not actually done.

### G12. Nothing tests the composition root

Every gap in this document exists because the test suite drives library classes directly and no test
asserts that the app assembles them. `NotchFlow/` has no test target at all.

Add tests, or a guard script in `scripts/` run by `.github/workflows/ci.yml`, that fail when a
public type in `Sources/` has no non-test production reference. The audit script in Part 2 is a
starting point — harden it (it is regex-based and will need an allow-list for types legitimately
used only as generic constraints or protocol witnesses, and for the injectable-seam protocols whose
only production use is a default parameter value).

This is the highest-leverage item here: without it the defect class recurs.

### G13. The translation guard has a blind spot

`scripts/check-translations.sh` verifies that every key **already present in a catalog** has every
language. It cannot see a key used in code but absent from every catalog — that string silently falls
back to its English key at runtime, which reads as correct English and is invisible in review.

This was hit during the previous session: new `localized(...)` / SwiftUI string literals were added
and the guard passed while the strings had no Turkish translation.

Extend the guard to scan `localized("…")` call sites and SwiftUI string literals in
`MenuBarExtra` / `Button` / `Text` / `Toggle` and fail on any that has no catalog entry. Also flag
orphaned catalog keys no longer referenced by any source file — the previous session left
`"Install the %@ hook"` orphaned before catching it manually.

---

## Part 5 — Verify these; state unknown

Not confirmed broken, but unverified, and each is the same shape as the confirmed defects. Check each
and report findings even where everything is fine.

1. **Onboarding permissions claims.** Step 2 asserts: *"Apple Events, so now playing and playback
   controls work with Spotify and Apple Music"*, *"Write access to an agent's configuration file,
   only when you install its hook"*, *"Recording and charging indicators need no permission at all."*
   Verify each is true of the shipping build. Note "playback controls" is claimed while G6 says no
   transport dispatch exists.
2. **Music providers end to end.** `AppleScriptMusicProvider` and `MediaRemoteMusicProvider` are
   registered. Confirm a real track playing in Spotify and in Apple Music produces a `MusicActivity`,
   and that `MusicAutomationGate` correctly reports and requests Apple Events permission. Note the
   App Store and Direct builds use different backends — `scripts/check-music-backend.sh` asserts they
   differ; verify both actually work.
3. **Timer provider.** `TimerProvider` is registered, but identify what *creates* a timer. If there
   is no user-facing way to start one, the provider can never fire and the feature does not exist.
4. **Recording providers.** `RecordingProvider(source: .screen)` and `(source: .audio)` are
   registered. Confirm they fire on a real screen recording and a real microphone capture. Note
   `docs/12-api-feasibility-matrix.md` row 15 flags microphone-in-use detection as having no reliable
   public API and marks it best-effort — verify the shipped behaviour matches that honest assessment
   rather than over-claiming in the UI.
5. **Charging provider.** Confirm `ChargingActivity` appears and clears correctly, including the
   "AC attached but not charging" state (a plugged-in Mac at 85% that has stopped charging).
6. **Auto-dismiss.** `AutoDismissDescriptor` / `ActivityManager.dismissTasks` — verify activities
   that should auto-dismiss (e.g. AI `completed`) actually disappear on schedule.
7. **Panel hit-testing.** `PresentationController` toggles `panel.ignoresMouseEvents` per state.
   Verify clicks pass through to the menu bar and desktop when the island is idle, and that the
   expanded panel does not swallow clicks meant for other apps. This is easy to get wrong and
   user-visible.
8. **Multi-display and clamshell.** `docs/03-display-and-notch.md` specifies a degraded mode for
   screens with no notch (anchor to top-centre of the menu bar). Verify on an external display and in
   a lid-closed clamshell session. This machine has an external 2560×1440 with no notch as the
   primary display and the built-in Retina as secondary — a good test bed.
9. **Idle performance contract.** `docs/02-performance-contract.md` defines an idle budget, and
   `scripts/measure-idle-performance.py` exists. Now that the panel is actually created and a mouse
   observer runs, re-measure. The window is ordered out when idle, but confirm no polling was
   introduced.
10. **App Store build viability.** The AppStore configuration builds, but `MediaRemote` is a private
    framework. Confirm which backend the App Store build uses and that
    `scripts/check-forbidden-symbols.sh` still passes on the final binary after your changes.

---

## Working agreement

- **Do not create git commits.** Leave changes in the working tree. The repository owner commits.
- **Do not use git worktrees.** Work in the existing checkout on the current branch.
- Match the surrounding code style. This codebase has an unusually high comment standard: comments
  explain *why*, never *what*, and frequently cite the doc section that motivates the decision.
  Read a few files before writing any.
- `NotchFlowCore` must import nothing but Foundation. `scripts/check-core-dependencies.sh` enforces
  this — do not weaken it.
- No TODO comments, no stubs, no placeholder implementations. If something cannot be completed,
  say so explicitly in your report rather than leaving a half-implementation.
- When you change user-facing text, update **both** `Localizable.xcstrings` catalogs and provide the
  Turkish translation. Source language is `en`; the app ships `en` and `tr`.
- If a fix requires a design decision rather than mechanical wiring, stop and ask rather than
  inventing semantics.

## Verification — all of these must pass before you report done

```bash
swift test
swift format lint --recursive Sources Tests NotchFlow
./scripts/check-core-dependencies.sh
./scripts/check-translations.sh
./scripts/check-assets.sh
./scripts/check-music-backend.sh
xcodebuild -project NotchFlow.xcodeproj -scheme "NotchFlow (Direct)" -configuration Direct -destination "platform=macOS" -derivedDataPath ./DerivedData/Dev CODE_SIGNING_ALLOWED=NO build
xcodebuild -project NotchFlow.xcodeproj -scheme "NotchFlow (App Store)" -configuration AppStore -destination "platform=macOS" -derivedDataPath ./DerivedData/Dev CODE_SIGNING_ALLOWED=NO build
```

Passing these is necessary but **not sufficient** — every defect in this document passed all of them.
For each gap you close, verify the behaviour in the running app and describe how you verified it.

### Runtime verification technique

The app is `LSUIElement` (no Dock icon), and AppleScript/System Events access is not granted, so UI
scripting is unavailable. Use the window server instead — this reliably shows whether the overlay
panel is ordered in:

```swift
// swift this-file.swift
import AppKit
import CoreGraphics
for s in NSScreen.screens { print("SCREEN \(s.localizedName): \(s.frame) safeTop=\(s.safeAreaInsets.top)") }
for (label, opts) in [("ON-SCREEN", CGWindowListOption.optionOnScreenOnly), ("ALL", .optionAll)] {
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { continue }
    let mine = raw.filter { ($0["kCGWindowOwnerName"] as? String) == "NotchFlow" }
    print("\(label): \(mine.count)")
    for w in mine {
        let b = w["kCGWindowBounds"] as? [String: Any] ?? [:]
        print("   layer=\(w["kCGWindowLayer"] ?? "?") \(b) alpha=\(w["kCGWindowAlpha"] ?? "?")")
    }
}
```

To isolate one activity source, disable the others through `UserDefaults` before launching:

```bash
for k in music timer screenRecording audioRecording charging; do
  defaults write com.notchflow.NotchFlow "com.notchflow.settings.providers.$k.enabled" -bool false
done
killall cfprefsd
```

Delete those keys afterwards to restore defaults.

To drive an AI activity without any agent installed:

```bash
SID=$(uuidgen); TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PL=$(python3 -c '
import json,sys,urllib.parse
print(urllib.parse.quote(json.dumps({"schemaVersion":"1.0","agentId":"claude-code",
"sessionId":sys.argv[1],"state":"working","detail":"probe","timestamp":sys.argv[2]}), safe=""))' "$SID" "$TS")
open -g "notchflow://ai-status?payload=$PL"
```

Valid `state` values: `idle`, `thinking`, `working`, `usingTool`, `waitingForUser`, `completed`,
`error`. Note `usingTool` maps to the `toolActivity` event class, which is **off by default** — use
`working` (which bypasses the event gate entirely) when testing the transport itself.

Install a fresh build with:

```bash
pkill -f "NotchFlow.app/Contents/MacOS/NotchFlow"; rm -rf /Applications/NotchFlow.app
cp -R ./DerivedData/Dev/Build/Products/Direct/NotchFlow.app /Applications/
xattr -dr com.apple.quarantine /Applications/NotchFlow.app
open /Applications/NotchFlow.app
```

The quarantine removal is required because there is no Developer ID certificate on this machine
(`security find-identity -v -p codesigning` returns zero identities), so builds are ad-hoc signed and
not notarized.

## Deliverable

A report covering, for each gap G1–G13 and each Part 5 item:

- What you found (confirmed broken / already fine / needs a decision).
- What you changed, with file references.
- How you verified it in the running app, not just that tests pass.
- Anything you deliberately did not do, and why.

Plus: any **additional** instances of the defect class that this document does not list. Finding
those matters more than closing the ones already named.
