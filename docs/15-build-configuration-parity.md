# Build Configuration Parity

NotchFlow ships in two configurations — `AppStore` (sandboxed, distributed through the Mac App Store) and `Direct` (unsandboxed, distributed as a `.dmg` and a Homebrew Cask). `docs/10-build-and-distribution.md` describes how the two are built. This document describes what a user actually gets in each, which capabilities are unavailable in the sandboxed build, and for each gap, what would have to become true to close it.

It exists because the differences are not obvious from the entitlements file. Two of them — the process table and the home directory — are silent: the API returns an empty result rather than an error, so a feature built against it degrades into doing nothing without any code path reporting a failure.

**Manual setup is a defect, not a feature.** Every item below that asks the user to paste something by hand is tracked as a gap to close, not as an accepted design. See *Closing the manual-setup gap*.

## How the measurements in this document were taken

Every claim marked **measured** was produced by running the same binary twice: once ad-hoc signed with no entitlements, and once inside an `.app` bundle ad-hoc signed with `com.apple.security.app-sandbox`, `com.apple.security.network.server` and `com.apple.security.automation.apple-events` — the entitlement set in `NotchFlow-AppStore.entitlements`. Claims marked **reasoned** follow from Apple's documented sandbox rules and were not executed.

Re-running these takes minutes and is worth doing whenever a macOS major release lands, because two of the results below are the kind Apple changes between releases.

## What is identical in both builds

The whole AI agent status pipeline, once the hooks are installed:

| Capability | Result |
|---|---|
| Loopback HTTP listener binds a socket | **Measured:** works in both. The sandboxed build declares `com.apple.security.network.server`; without it the socket would not bind at all |
| `notchflow://` URL scheme delivery | **Reasoned:** needs no entitlement in either build |
| Every agent state — `thinking`, `working`, `usingTool`, `waitingForUser`, `completed`, `error`, `idle` | Identical. This is `NotchFlowCore` logic with no system API underneath it |
| Compact session grouping and its count badge, per-session expanded cards, ordering, the completed tick and its timer | Identical |
| `NSWorkspace` running-application list, bundle identifiers, frontmost application | **Measured:** identical — 91 applications and 74 bundle identifiers in both, same frontmost |
| Resolving which application handles a URL scheme | **Measured:** identical — `vscode://` resolved to `com.microsoft.VSCode` in both |
| Opening a URL to focus an editor window | **Measured:** the sandboxed build opened `vscode://file/<folder>` and the editor's window for that folder came forward |
| The island itself — geometry, animation, timers, hover, expansion | Identical. `NotchFlowCore` and `NotchFlowUI` touch no platform-privileged API |

The last two rows matter more than they look: they mean the *acting* half of "open the agent's editor" is fully available to the sandboxed build. What it loses is only the *knowing* half. See the gap below.

## What the sandbox takes away

### 1. Writing the agent hook files

**What it is:** Enabling an agent in Settings writes its hook into `~/.claude/settings.json`, `~/.codex/config.toml` and `~/.codex/hooks.json`, or `~/.config/opencode/plugins/notchflow.ts`.

**Status in `AppStore`:** Blocked. **Measured:**

| | `Direct` | `AppStore` |
|---|---|---|
| `FileManager.homeDirectoryForCurrentUser` | `/Users/<user>` | `~/Library/Containers/<bundle-id>/Data` |
| `~/.claude/settings.json` readable | yes | **no** |
| `~/.claude/settings.json` writable | yes | **no** |
| `~/.codex/config.toml` | yes / yes | **no / no** |
| `~/.config/opencode/plugins/` | yes / yes | **no / no** |

The sandboxed build does not merely lack write permission — its home directory is redirected into the container, so the real paths are not visible at all. The installers already treat this correctly: `install()` throws, and `ManualSetupInstructions` presents the exact bytes as copyable text.

**Consequence for the user:** the agent integration works fully in the App Store build, but the user has to paste one snippet per agent by hand the first time. Everything after that — including "Claude is waiting for your input" — behaves identically.

**What would have to become true:** any one of these closes it:

- **A user-selected file grant.** Adding `com.apple.security.files.user-selected.read-write` plus an `NSOpenPanel` pointed at `~/.claude` would let the user grant access once, after which the installer writes normally and a security-scoped bookmark keeps the grant across launches. This is sanctioned and reviewable; the cost is one file-picker step instead of one paste, which is better but still not invisible.
- **The agents adopting a discovery directory.** If Claude Code, Codex and OpenCode read hooks from a directory a sandboxed app can write — an app group container, or a per-agent "plugins" path under `~/Library/Application Support` — the installer writes there with no prompt at all. This is the clean answer and it is not ours to decide alone; it is worth raising with each agent's maintainers.
- **A companion CLI.** Shipping a small unsandboxed helper the user runs once (`brew install notchflow-hooks`, or a `curl | sh` line) reduces the manual step to one command. It trades a paste for a terminal command, which is not obviously better for the audience.

**Work estimate:** Small for the user-selected grant — one entitlement, one panel, and bookmark persistence in `SettingsStore`. The installers and their tests need no change.

### 2. Linking an agent to the application it is running in

**What it is:** `WorkspacePrimaryActionDispatcher` walks the process tree from a live `claude` / `codex` / `opencode` process up to the application hosting it, so pressing the agent's row raises the editor or terminal the agent is actually running in — and, for editors that support it, the specific *window* holding the agent's folder.

**Status in `AppStore`:** Blocked, and silently. **Measured:**

| | `Direct` | `AppStore` |
|---|---|---|
| `proc_listallpids` — processes visible | 631 | **0** |
| `proc_pidpath` — executable paths readable | 627 | **0** |
| `proc_pidinfo(PROC_PIDVNODEPATHINFO)` — working directories readable | 427 | **0** |

The sandbox hides the process table completely. `AgentHostApplicationResolver.hosts(for:)` therefore returns an empty array in the App Store build, and no error is raised anywhere: the dispatcher simply falls through to its later branches.

**Consequence for the user:** pressing an agent's row in the App Store build raises, in order: the agent's dedicated desktop app if it is running, otherwise the single running development host if there is exactly one, otherwise nothing. With two editors open it does nothing. The window-level targeting added for multiple editor windows never runs at all.

**What would have to become true:** the acting half already works — a sandboxed build opened `vscode://file/<folder>` and the right window came forward. Only the *discovery* is blocked, and it has a route that needs no new permission:

- **The hook reports its own working directory.** The hook script runs unsandboxed, inside the agent's own process, and already knows its `cwd`. Carrying it in the IPC envelope as an optional field would give both builds the same window targeting, with no process scanning at all — and would make the `Direct` build's targeting more reliable too, since it would no longer depend on reading another process's state.

  This is a deliberate change to the privacy contract in `docs/07-ai-integration.md`, which today admits only the state, the agent, a short detail line, an optional tool name and a progress fraction. A workspace path is not a prompt, a diff or a transcript — but it is user data that was previously never transmitted, and it would have to be: named explicitly in the envelope spec, listed in `docs/09-security-privacy-permissions.md` and `docs/PRIVACY.md`, validated like every other field, and ideally behind a settings switch that defaults off. **Do not add it as an implementation detail.**

- **Alternatively, drop the feature in the sandboxed build and say so.** The Settings pane can state that opening the agent's window needs the Direct build, rather than presenting a control that quietly does nothing.

**Work estimate:** Small for the envelope field — one optional field, one validator rule, three hook generators, and the dispatcher preferring it over the process walk. Medium if the settings-visible explanation and the privacy documentation are counted, which they should be.

### 3. Mirroring the Apple Clock app's timers

**What it is:** `AppleClockMirror` reads the Clock app's running timers through the Accessibility API so the island can show a timer the user started in Apple's own app.

**Status in `AppStore`:** Not built. `makeAppleClockMirror(timerProvider:)` returns `nil` outside `DIRECT_BUILD`, deliberately — reading another application's accessibility tree is not available to a sandboxed app. **Reasoned**, and already documented at the call site.

**Consequence for the user:** in the App Store build, only timers started inside NotchFlow appear. The feature is absent rather than broken, and nothing in the UI offers it.

**What would have to become true:** Apple would need a sandbox-compatible way to observe another app's timers. There is no current route: the Accessibility permission itself is not the obstacle — the sandbox is.

**Work estimate:** None; the code exists and is already behind the compile-time branch.

### 4. Music source coverage

**What it is:** which media applications the now-playing card can observe.

**Status:** different rather than blocked.

| | `Direct` | `AppStore` |
|---|---|---|
| macOS ≥ 15.4 | AppleScript — Spotify and Apple Music | AppleScript — Spotify and Apple Music |
| macOS < 15.4 | MediaRemote — any media application | AppleScript — Spotify and Apple Music |
| Apple Events prompt | Only on the AppleScript path | Yes, once per target application |

macOS 15.4 restricted MediaRemote metadata to Apple-signed processes, so on current systems the two builds behave the same. The divergence only remains on older releases. The App Store build's `com.apple.security.scripting-targets` entitlement names exactly the two players it is allowed to talk to, which is why a third player cannot be added there without a new entitlement and a new review.

**What would have to become true:** a public now-playing API that a sandboxed app may use. `docs/13-deferred-backlog.md` tracks the general shape of this.

## Closing the manual-setup gap

Ordered by what removes the most friction per unit of work.

1. **Envelope-carried working directory** (gap 2). Removes a silent no-op, closes the parity gap for window targeting, and makes the `Direct` build more reliable at the same time. Blocked on a privacy-contract decision, not on a technical one.
2. **User-selected file grant for hook installation** (gap 1). Turns a copy-paste into a single "choose this folder" step. Sanctioned, reviewable, small.
3. **Raise the discovery-directory question with the agent vendors** (gap 1). The only route that removes the step entirely rather than shortening it. Long lead time, no code.
4. **Say what is unavailable** (gaps 2 and 3). Whatever else is decided, the App Store build should not present controls that cannot work. This is small and should not wait for the others.

## Keeping this document honest

The two silent gaps — the process table and the home directory — are the ones most likely to change with a macOS release, and the ones least likely to announce that they have. When a major version lands, re-run the two probes described at the top before assuming either row still holds.

If a capability moves between the columns above, this document and the configuration table in `docs/10-build-and-distribution.md` must be updated in the same change; the two must never disagree.
