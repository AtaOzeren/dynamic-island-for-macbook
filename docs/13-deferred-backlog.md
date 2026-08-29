# Deferred Backlog

This document is the standing note for everything NotchFlow recognizes as valuable but does not build in V1. Every item here is postponed, not cancelled — each has a reason tied to a specific API gap or a deliberate sequencing choice, and each will be revisited when its trigger fires. It is a design specification — nothing in this folder is code.

Anything listed here must also appear in the "What V1 Deliberately Excludes" section of `docs/00-product-overview.md`, and the two documents must never disagree. If an item is added to or removed from this backlog, update that section in the same change.

## Deferred out of V1: no public API

### Incoming call activity

**What it is:** A live-activity card showing an incoming or in-progress call — caller name, call source (FaceTime, Phone Link, or another calling app), and duration — the way a timer or recording indicator appears today.

**Why it is not in V1:** macOS has no public API for observing call state from third-party apps. FaceTime and Phone Link do not publish call state through `MediaRemote`, `CallKit` is not available to non-telephony apps for reading system-wide call state, and there is no distributed-notification or `NSWorkspace` equivalent for this. Reading it would require unsupported private frameworks, which is disqualifying for both build configurations (see `docs/12-api-feasibility-matrix.md`).

**What would have to become true:** Apple would need to ship a public, sandboxable API surfacing call state from FaceTime, Phone Link, or a general "Call" activity type analogous to how `MediaRemote` covers now-playing. A `CallKit`-adjacent read-only observer API would also qualify.

**Work estimate once feasible:** Small. The activity model already generalizes to arbitrary sources (see `docs/05-activity-model.md`); this would be one new provider plus one new compact/expanded view, comparable in scope to the recording indicator.

### AirDrop transfer progress

**What it is:** A live-activity card showing an in-progress AirDrop send or receive, with percentage complete and the file or peer name.

**Why it is not in V1:** There is no public, sanctioned way to read AirDrop transfer progress from outside the Finder/AirDrop process. AirDrop does not publish `NSProgress`, does not send distributed notifications with progress detail, and is not exposed through `NSWorkspace` or any documented IPC mechanism.

**What would have to become true:** Apple would need to publish AirDrop progress through `NSProgress`'s publish/subscribe mechanism (the same mechanism some apps already opt into for file operations) or a dedicated notification.

**Work estimate once feasible:** Small, contingent on the shape of whatever API appears. If it arrives as an `NSProgress` publication, it slots into the same progress-observation pattern used for the drop-shelf substitute described below.

### Generic third-party download and file-transfer progress

**What it is:** A live-activity card showing download or transfer progress from arbitrary third-party apps — a browser download, a large file copy, a cloud-sync upload — without those apps doing anything special to support NotchFlow.

**Why it is not in V1:** Showing another app's download progress would require inspecting that app's internals, which is not available through public APIs and conflicts with the App Sandbox model. `NSProgress` file-progress publishing exists but is opt-in per publishing app; Finder and Safari do not expose it to third-party subscribers today, so there is no general mechanism that covers "any app's download" without that app's cooperation.

**What would have to become true:** Either (a) more system and third-party apps voluntarily publish `NSProgress` for their transfers and NotchFlow subscribes to whichever ones do, or (b) Apple introduces a general transfer-progress observation API analogous to `MediaRemote` for media.

**Work estimate once feasible:** Medium. Unlike the single-source items above, this would need a provider capable of handling multiple concurrent, differently-labeled sources and de-duplicating or prioritizing among them — closer in complexity to the multi-activity overflow handling in `docs/05-activity-model.md` than to a single new provider.

### NotchFlow-owned drop shelf (partial substitute)

**What it is:** Instead of observing other apps' transfers, NotchFlow could offer its own drag-and-drop shelf: the user drags a file onto the island, NotchFlow itself manages a local copy, share-sheet hand-off, or AirDrop send, and shows progress because it is the one doing the work rather than trying to observe someone else's process.

**Why it is not in V1:** This is a meaningfully different feature — a new activity source that NotchFlow originates rather than observes — and was not part of the V1 feature list committed to in `docs/00-product-overview.md`. It is recorded here as the most viable path to delivering transfer-progress value without a new public API, not as a workaround being built now.

**What would have to become true:** A product decision to add NotchFlow-originated file handling as a feature, plus the standard AirDrop/share-sheet integration work, both public and available in V1's target macOS range.

**Work estimate once feasible:** Medium. NotchFlow would own the entire lifecycle (drop target, transfer mechanism, progress reporting) rather than subscribing to an external source, which is more code than any provider in V1 but does not depend on an API that does not yet exist.

## V1.5: sequenced after the core system is stable

### Live Activities: navigation, food delivery, shipping, live scores

**What it is:** Live-activity cards mirroring iOS Live Activities for turn-by-turn navigation, food delivery status, package shipping, and live sports scores.

**Why it is not in V1:** Each depends on a third-party data integration (a maps provider, a delivery service's API, a carrier tracking API, a sports-data feed) that is a separate, larger effort from the core notch system. `draft.md` section 16 places this set in V1.5, after the core activity system ships.

**What would have to become true:** The core activity model, provider architecture, and overflow handling need to be stable and proven in daily use first, since these sources will be the first fully external, network-dependent activities NotchFlow hosts.

**Work estimate once feasible:** Large, and variable per integration — each data source is its own provider with its own auth, polling-or-push tradeoff, and view design. Expect one release cycle per integration rather than one combined effort.

### Touch ID-related system status surfacing

**What it is:** A live-activity card surfacing Touch ID-related system state — for example, a recent successful or failed authentication — in the notch.

**Why it is not in V1:** Deferred until the core activity system is stable and proven in daily use; `draft.md` section 16 groups it with the other V1.5 items as work that follows, not precedes, that stability milestone.

**What would have to become true:** V1's core system shipping and being validated in daily use, plus confirming a public, sandboxable way to observe Touch ID authentication events (not yet verified; would need its own feasibility row).

**Work estimate once feasible:** Small, assuming a public observation API exists — comparable to the charging-state provider in scope.

## V2: platform-widening features

### Smart home status

**What it is:** A live-activity card surfacing smart-home state — for example, a door lock, a thermostat, or a running appliance — from HomeKit or third-party smart-home ecosystems.

**Why it is not in V1:** A distinct integration surface (HomeKit and third-party ecosystems) that deserves its own design pass rather than being folded into the V1 activity model as an afterthought.

**What would have to become true:** A dedicated design pass covering which smart-home ecosystems to support, how HomeKit permissions and entitlements interact with NotchFlow's sandboxed build, and how third-party (non-HomeKit) ecosystems would be integrated at all.

**Work estimate once feasible:** Large. This is a new integration category, not a new provider — comparable in scope to adding AI agent integration was for V1.

### Additional AI app support: ChatGPT, Gemini, Cursor, VS Code/Copilot

**What it is:** Extending AI agent status surfacing (see `docs/07-ai-integration.md`) beyond the V1 set of Claude Code, Codex, and OpenCode to cover ChatGPT desktop, Gemini CLI, Cursor, and VS Code/Copilot.

**Why it is not in V1:** V1 focuses on validating the AI-status architecture with three agents before widening the list. No public status hook was found for Claude Desktop, ChatGPT desktop, Cursor, or Copilot during feasibility research (see `docs/12-api-feasibility-matrix.md`); `draft.md` section 17 places broader AI app support after the initial three.

**What would have to become true:** The V1 IPC protocol and hook-installer model need to prove out with real daily use across the first three agents. For each additional app, either a documented hook or extension point needs to exist, or NotchFlow needs a supported way to integrate with that app's own extension mechanism.

**Work estimate once feasible:** Small per agent, once the app in question exposes an integration point — the IPC protocol and UI are already generalized across agents; adding one is mostly a new hook script and a config entry.

### Third-party developer API, public API, and developer SDK

**What it is:** A `NotchFlow.show(...)`-style public interface letting any third-party app or script publish its own activity into the notch, plus the accompanying SDK and documentation.

**Why it is not in V1:** Opening the platform to outside developers is a governance and stability commitment — API stability guarantees, abuse prevention, review of what third parties can push into a user's notch — that comes after the core product has shipped and settled, not before.

**What would have to become true:** V1 and V1.5 shipping and proving stable, plus a deliberate decision to take on the support and governance burden of a public developer surface, including a security review of what a third-party payload is allowed to do (see the threat-model discussion in `docs/09-security-privacy-permissions.md`, which already covers the analogous problem for the AI-agent loopback listener).

**Work estimate once feasible:** Large. This is a new product commitment (versioned public API, SDK packaging, documentation, third-party review process), not an incremental feature.

### User-defined activities

**What it is:** Letting a user configure their own custom activity — its trigger, its data source, and its appearance — without NotchFlow or a third-party developer having built it in advance.

**Why it is not in V1:** This depends on the third-party developer API above existing first, or on a separate no-code configuration system that was not part of the V1 scope committed to in `docs/00-product-overview.md`.

**What would have to become true:** Either the public developer API ships and user-defined activities are built on top of it, or a standalone configuration UI is designed and built as its own effort.

**Work estimate once feasible:** Large, and dependent on which path is chosen above.

## Revisit triggers

Re-evaluate this backlog when any of the following happens:

- **A new macOS release's notes mention a relevant capability** — call state observation, AirDrop or transfer progress publication, or any framework touching the gaps listed above.
- **A new public framework ships** that closes one of the API gaps described in `docs/12-api-feasibility-matrix.md`.
- **A documented third-party integration becomes available** — for example, a delivery service, carrier, or sports-data provider publishes an official API suitable for a V1.5 Live Activity.

When a trigger fires for a specific item, move that item's re-evaluation into an active planning cycle rather than editing this document to declare it shipped; this document stays the historical record of what was deferred and why until the corresponding feature actually lands in a dated `docs/` update.
