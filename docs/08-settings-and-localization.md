# Settings and Localization

This document specifies the complete settings surface, its persistence mechanism and defaults policy, the settings window and first-run onboarding flow, and the localization mechanism NotchFlow uses for every user-visible string. It is a design specification — nothing in this folder is code.

## Design principle

Every setting NotchFlow exposes has a safe, disclosed default: nothing is enabled on first run that would surprise a user who never opened the settings window. Persistence uses a single typed wrapper over `UserDefaults` so every read and write goes through one place, with one naming convention and one migration path. Every user-visible string ships through String Catalogs, never as a literal in a view — this is a lint-enforced rule, not a style preference.

## The settings table

Every setting below has a type, a default, a persistence key, and the screen or section it appears in. Keys use the `com.notchflow.settings.` prefix followed by a dot-separated path matching the table's grouping.

| Setting | Type | Default | Persistence key | Appears in |
|---|---|---|---|---|
| Display target | enum: `automatic` \| `builtIn` \| `named(String)` | `automatic` | `display.target` | General |
| Launch at login | Bool | `false` | `general.launchAtLogin` | General |
| Appearance | enum: `auto` \| `light` \| `dark` | `auto` | `general.appearance` | General |
| Reduced motion override | Bool? (nil = follow system) | `nil` | `general.reducedMotionOverride` | General |
| Music provider enabled | Bool | `true` | `providers.music.enabled` | Activities |
| Timer/Stopwatch provider enabled | Bool | `true` | `providers.timer.enabled` | Activities |
| Screen Recording provider enabled | Bool | `true` | `providers.screenRecording.enabled` | Activities |
| Audio Recording provider enabled | Bool | `true` | `providers.audioRecording.enabled` | Activities |
| Charging provider enabled | Bool | `true` | `providers.charging.enabled` | Activities |
| AI agent enabled — Claude Code | Bool | `false` | `ai.agents.claudeCode.enabled` | AI Integrations |
| AI agent enabled — Codex CLI | Bool | `false` | `ai.agents.codex.enabled` | AI Integrations |
| AI agent enabled — OpenCode | Bool | `false` | `ai.agents.openCode.enabled` | AI Integrations |
| Event toggle — task started (`thinking`) | Bool | `true` | `ai.events.taskStarted` | AI Integrations, per agent |
| Event toggle — task completed | Bool | `true` | `ai.events.taskCompleted` | AI Integrations, per agent |
| Event toggle — task error | Bool | `true` | `ai.events.taskError` | AI Integrations, per agent |
| Event toggle — needs input (`waitingForUser`) | Bool | `true` | `ai.events.needsInput` | AI Integrations, per agent |
| Event toggle — tool activity (`usingTool`) | Bool | `false` | `ai.events.toolActivity` | AI Integrations, per agent |
| Hook installation status (per agent) | enum: `notInstalled` \| `installed` \| `outOfDate` | computed, not stored | — (derived by reading the agent's config file, see `07-ai-integration.md`) | AI Integrations |
| Hook install / uninstall action | action, not a stored setting | — | — | AI Integrations |
| App language | picker, driven by system locale unless overridden | system default | `general.languageOverride` | About |

Two defaults are deliberately conservative and worth calling out. First, every AI agent is **disabled** by default — a user must opt in per agent before NotchFlow surfaces anything for it, matching the rule in `07-ai-integration.md` that an agent not explicitly enabled is ignored even if its hook is technically installed. Second, the `usingTool` event toggle defaults to **off** per agent, because tool-level updates are the highest-frequency, lowest-signal event in the state machine (`07-ai-integration.md`); a user who wants that level of detail turns it on deliberately.

The per-agent event toggles apply uniformly across Claude Code, Codex CLI, and OpenCode — the settings UI renders one row of five toggles per enabled agent, not five independent tables, because the underlying `AIActivity` state machine is the same regardless of which agent produced the message.

## Persistence

### Typed wrapper

NotchFlow never calls `UserDefaults.standard` directly from a view or a provider. A single typed wrapper (conceptually a property-wrapper-backed struct, one static instance) exposes every setting above as a strongly typed property. This gives three things a raw `UserDefaults` call cannot: a compile-time guarantee that a setting's type cannot drift between the reader and the writer, a single place to add a default value, and a single place to add migration logic when a key's meaning or shape changes.

### Key naming convention

Keys are dot-separated, lower-camel-case path segments, always starting with the group they belong to (`general.`, `display.`, `providers.`, `ai.`). The group prefix exists so a future settings export or reset-to-defaults operation can filter by group without a hardcoded list of every key.

### Migration policy

A settings schema change — a renamed key, a changed type, or a value whose meaning shifts — ships with a one-time migration step that runs once per app update: read the old key if present, translate it into the new key's value, and remove the old key. Migrations are additive and ordered; NotchFlow never overwrites a key it cannot confidently translate, and when a migration cannot determine a safe value it falls back to the documented default rather than guessing. There is no schema version number stored separately — the presence or absence of a given key is itself the signal a migration step checks for.

### Defaults-are-safe rule

No setting in the table above defaults to a state that would show the user something they did not ask for. Concretely: no AI agent activity appears until the user both enables that agent and (if applicable) installs its hook; no activity provider is silently disabled in a way that hides information the user would expect (all five non-AI providers default to enabled, since none of them requires an external opt-in the way agent integration does); and appearance and motion settings default to following the system rather than overriding it.

## The settings window

Settings is a standard SwiftUI `Settings` scene, giving NotchFlow the platform-native window chrome, keyboard shortcut (⌘,), and menu bar item placement for free, with no custom window-management code. It opens two ways: from the status item's menu (see `todo 23`, the accessory-app configuration), and from the last step of first-run onboarding below. Opening the settings window does not change the app's activation policy — NotchFlow remains an accessory app (`LSUIElement`, no Dock icon) whether or not the settings window is open, and closing the window returns to the same no-window, status-item-only state without any special-case handling.

The window is organized into the sections implied by the "Appears in" column above: **General** (display target, launch at login, appearance, reduced motion), **Activities** (per-provider enable toggles), **AI Integrations** (per-agent enable, per-event toggles, hook status and install/uninstall), and **About** (license, acknowledgments, language override). Each section is a single SwiftUI view backed directly by the typed settings wrapper — no intermediate view model duplicates state that already lives in `UserDefaults`.

## First-run onboarding

Onboarding runs once, on the first launch after install, gated by a single `hasCompletedOnboarding` flag in the typed wrapper (not itself listed in the settings table because it is not a user-facing preference). The flow has four steps:

1. **Welcome.** A short screen naming the product and its scope: a live activity surface around the notch for music, timers, recording indicators, charging state, and AI agent status.
2. **Permission explanation.** Before any system permission prompt fires, NotchFlow explains in plain language what it is about to ask for and why (see `09-security-privacy-permissions.md` for the entitlements and prompts this maps to) — no permission is requested without this context screen appearing first.
3. **Agent detection and hook offer.** NotchFlow runs the same detection step described in `07-ai-integration.md`'s hook installer, and if it finds a configuration file for Claude Code, Codex CLI, or OpenCode, it offers to install the corresponding hook right there, using the same consent flow (show the exact snippet, get explicit approval) the installer uses when invoked later from Settings.
4. **Done.** A closing screen confirming setup is complete, with a button that opens Settings directly, so a user who wants to review or change anything from Welcome through Agent Detection can do so immediately.

Declining a step (skipping the hook offer, for example) does not block progress to the next step or re-prompt on every launch — every onboarding decision is revisitable later from Settings, and onboarding itself never runs a second time once `hasCompletedOnboarding` is set.

## Localization

### Mechanism

String Catalogs (`.xcstrings`) are the single localization mechanism NotchFlow uses — no `.strings` files, no `NSLocalizedString` call sites, no third-party localization library. Every user-visible string is written with `String(localized:)` (or the SwiftUI `Text` initializer that resolves through the same mechanism), which reads from the catalog at the call site's declared key.

### No hardcoded strings rule

No user-visible string literal appears directly in a SwiftUI view body, an alert, a menu item title, or any other UI-facing call site. This is enforced as a lint rule (extending the `swiftlint` configuration referenced in `14-glossary-and-conventions.md`, tied to the acceptance criterion for this document) that flags a bare string literal passed to `Text`, `Label`, `Button`, `Alert`, `Menu`, or similar SwiftUI initializers outside of a small, explicitly annotated allowlist (SF Symbol names and other non-linguistic identifiers). A PR that introduces a new hardcoded user-visible string fails this lint and is not mergeable, the same way a `swift-format` violation is not mergeable.

### Plurals and units

Pluralization uses String Catalog's built-in variation support (`.xcstrings` plural variants keyed by the platform's `Plural.Rule`), not manual `if count == 1` branching in Swift code — the catalog owns the plural rule per language, including languages with more than two plural forms. Units (elapsed time in the AI activity states, timer/stopwatch duration, recording length) are formatted with `Duration.TimeFormatStyle` or `DateComponentsFormatter` rather than hand-built strings, so unit spacing and abbreviation follow the user's locale automatically instead of being hardcoded to English conventions.

### Dates and durations

Any absolute date or time shown anywhere in the UI uses `Date.FormatStyle`, letting the system apply the user's locale and calendar preferences rather than a fixed format string. Durations (elapsed time on an in-progress AI activity, a running stopwatch, a countdown timer) use `Duration.TimeFormatStyle`, which likewise adapts separator and unit-label conventions per locale without NotchFlow special-casing any language.

### Right-to-left readiness

Layout uses SwiftUI's leading/trailing-relative modifiers (`.leading`, `.trailing`, `HStack` with natural layout direction) rather than absolute `.left`/`.right` placement, so the compact and expanded island layouts mirror correctly under a right-to-left locale without a separate RTL-specific layout branch. No V1 ship language is right-to-left, but the layout code does not assume left-to-right either — this is a readiness property, not a shipped RTL translation.

### Ship set and contributing a language

V1 ships two languages: English (base) and Turkish. Adding a language is a String Catalog operation, not a code change: a contributor adds the new locale to the catalog's language list in Xcode, translates every key (Xcode's catalog editor flags untranslated and stale entries), and opens a PR containing only the updated `.xcstrings` files. No Swift source file changes are needed to add a language, which is the direct payoff of the "no hardcoded strings" rule above — every translatable surface already routes through the catalog before a new language is ever added.

### App Store metadata localization

App Store listing text — the app name, subtitle, description, keywords, and "what's new" release notes — lives outside the `.xcstrings` mechanism entirely, in App Store Connect's own per-locale metadata fields (see `10-build-and-distribution.md` for the submission flow those fields are part of). These strings are translated and maintained separately from the in-app catalog because App Store Connect does not read `.xcstrings`; keeping this distinction explicit avoids a contributor assuming a catalog translation also updates the store listing.
