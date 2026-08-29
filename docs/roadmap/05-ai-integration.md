# Phase 5: AI Integration

**Status:** NOT STARTED
**Todos:** 50-58 (Wave 5 in `.omo/plans/notchflow-v1.md`)
**Depends on:** Phase 2 (Core, under TDD): the IPC core (todo 31) that parses and validates every inbound event, and the `ActivityProvider` protocol the AI provider registers against. Phase 3 (Window and UI): the compact/expanded view containers the AI activity renders into.
**Unblocks:** Phase 6 (Settings, Localization, Polish): the AI integrations pane and the per-agent/per-event toggles need the receivers, installers, and controls built here. Phase 7 (Performance, Packaging, Distribution): both build configurations must carry the AI surface before the sandbox and packaging checks can run against the real app.
**Parallelism:** 5-wide

## What this phase delivers

Everything that lets an AI coding agent drive the island: the two inbound channels (a custom URL scheme and a loopback-only listener), the AI activity with compact and expanded renderings for all seven agent states, detection of Claude Code, Codex CLI, and OpenCode, one installer per agent that writes hook or plugin configuration behind explicit consent with backup and clean uninstall, a manual-setup fallback for when installation is unavailable or declined, and per-agent plus per-event controls that drop disabled events at the receiver rather than merely hiding them.

## Todos

### 50. Implement the URL-scheme receiver

Register the custom scheme, parse and validate incoming URLs through the core validator, and reject anything invalid without side effects.

- **Acceptance:** A valid `open -g` invocation produces an agent activity; malformed and hostile inputs are rejected silently.
- **QA (CI + HW):** Unit tests for parsing; on hardware, invoke the scheme for each of the seven states and one malformed case. Evidence: `.omo/evidence/task-50-notchflow-v1.log`.
- **Commit:** `feat(ai): add URL scheme event receiver`

### 51. Implement the loopback listener

Bind `127.0.0.1` on an ephemeral port, publish the port to the documented discovery location, enforce the size and rate limits, and validate every payload. Starts only when at least one AI integration is enabled; stops when the last is disabled.

- **Acceptance:** Bound to loopback only (verified by an external-interface connection attempt failing); no socket exists while all integrations are disabled.
- **QA (HW):** Confirm the listening socket's bind address; attempt a connection from a non-loopback address and assert refusal; disable all integrations and assert the socket is gone. Evidence: `.omo/evidence/task-51-notchflow-v1.log`.
- **Commit:** `feat(ai): add loopback event listener`

### 52. Implement the AI activity and its views

Compact and expanded renderings for all seven states, the agent label, the tool name, optional progress, and the primary action that activates the originating app.

- **Acceptance:** Every state renders distinctly; the completed and error states auto-dismiss per `docs/05`.
- **QA (CI):** Structural tests per state; on hardware, drive all seven states and screenshot each. Evidence: `.omo/evidence/task-52-notchflow-v1/`.
- **Commit:** `feat(ai): add AI agent activity and views`

### 53. Implement agent detection

Detect which of Claude Code, Codex CLI, and OpenCode are present, in a way that works in both builds (and degrades to "unknown, offer manual setup" when the sandbox prevents inspection).

- **Acceptance:** Present agents are detected in the Direct build; the App Store build offers manual setup rather than failing.
- **QA (HW):** Run in both configurations with at least one agent installed; confirm the expected path in each. Evidence: `.omo/evidence/task-53-notchflow-v1.log`.
- **Commit:** `feat(ai): detect installed agents`

### 54. Implement the Claude Code hook installer

Shows the exact proposed change, requires explicit consent, backs up the existing settings file, writes the async hook configuration, and supports full uninstall restoring the backup.

- **Acceptance:** Installing then uninstalling leaves the settings file byte-identical to the original; the installed hook is async and cannot block the agent.
- **QA (HW):** Install, diff, run a Claude Code session and observe states in the island, uninstall, and diff against the original. Evidence: `.omo/evidence/task-54-notchflow-v1/`.
- **Commit:** `feat(ai): add Claude Code hook installer`

### 55. Implement the Codex CLI hook installer

Same consent, backup, and uninstall contract, targeting the `notify` setting.

- **Acceptance:** Round-trip install/uninstall is byte-identical; a Codex session drives the island.
- **QA (HW):** As todo 54, with Codex. Evidence: `.omo/evidence/task-55-notchflow-v1/`.
- **Commit:** `feat(ai): add Codex CLI hook installer`

### 56. Implement the OpenCode plugin installer

Writes the plugin file with the same consent, backup, and uninstall contract.

- **Acceptance:** Round-trip is clean; an OpenCode session drives the island.
- **QA (HW):** As todo 54, with OpenCode. Evidence: `.omo/evidence/task-56-notchflow-v1/`.
- **Commit:** `feat(ai): add OpenCode plugin installer`

### 57. Implement the manual-setup fallback UI

When automatic installation is unavailable or declined, display the exact snippet with a copy button and instructions.

- **Acceptance:** The displayed snippet is identical to what the installer would have written.
- **QA (CI):** Assert the UI snippet and the installer output are produced by the same generator and are string-equal. Evidence: `.omo/evidence/task-57-notchflow-v1.log`.
- **Commit:** `feat(ai): add manual hook setup fallback`

### 58. Implement per-agent and per-event toggles

Enable/disable each agent and each event class per `docs/08`; disabled events are dropped at the receiver, not merely hidden.

- **Acceptance:** A disabled event class produces no activity and no UI work.
- **QA (HW):** Disable one event class, emit it, and assert no activity is created. Evidence: `.omo/evidence/task-58-notchflow-v1.log`.
- **Commit:** `feat(ai): add per-agent and per-event controls`

## Verification tiers

Per the plan's verification strategy: `CI` is verifiable headlessly by `xcodebuild test` / a script on a GitHub Actions macOS runner; `HW` requires the physical notched MacBook (a real agent session driving the island) and is collected into the Final Verification Wave.

| Todo | Tier |
|---|---|
| 50 | CI + HW |
| 51 | HW |
| 52 | CI + HW |
| 53 | HW |
| 54 | HW |
| 55 | HW |
| 56 | HW |
| 57 | CI |
| 58 | HW |

Todo 52 is tagged `CI` in the plan, but the same QA line also requires driving all seven states on hardware with screenshots, so it lands in both tiers.

## Source references

- `docs/07-ai-integration.md` — the agent state machine (seven states), the IPC protocol (URL scheme and loopback listener), per-agent integration details, the hook installer contract, and the privacy rules.
- `docs/05-activity-model.md` — auto-dismiss timing for the completed and error states.
- `docs/08-settings-and-localization.md` — per-agent and per-event toggle keys and semantics.
- `.omo/plans/notchflow-v1.md` — Wave 5 (lines 403-457), dependency matrix (lines 84-95).
