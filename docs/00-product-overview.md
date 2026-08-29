# Product Overview

## What NotchFlow Is

NotchFlow is a native macOS app that turns the notch on modern MacBooks into a live-activity island, similar in spirit to iPhone's Dynamic Island but built specifically for macOS. It surfaces what's happening on your Mac right now: the song playing, a countdown running, a recording in progress, the charger just plugged in, and the live status of the AI coding agent you're working with. All of it appears in the notch area and collapses away the instant there's nothing to show.

The app runs quietly in the background and is event-driven from the ground up. It does not poll, it does not scan the screen, and it does not run a model of its own. When idle, it aims to use close to zero CPU. When something happens, it wakes up, shows the relevant activity, and goes back to sleep the moment that activity ends.

## Who It's For

- **MacBook owners with a notch** who want a single, unobtrusive place to see music controls, timers, recording status, and charging state without opening separate apps or menu bar icons.
- **Developers using AI coding agents** (Claude Code, Codex, OpenCode) who want to glance at the notch and immediately know whether their agent is thinking, waiting for input, or done, without switching windows or tabs.

## The Problem

Mac users juggle several small, ambient pieces of information throughout the day: what's playing, how much time is left on a timer, whether the screen or mic is currently recording, whether the AI agent running in a terminal or IDE needs their attention. Today that information is scattered across the menu bar, separate app windows, and terminal panes the user has to keep checking manually. There is no single, glanceable, low-effort place for it, and the tools that exist for this on iPhone don't have a macOS equivalent that respects background performance and works within App Store rules.

## Non-Goals

- NotchFlow does not run or host any AI model itself. It only displays status pushed to it by AI agent hook scripts.
- NotchFlow does not use Accessibility APIs or screen capture to observe other apps. It relies on official system APIs and scripting interfaces only.
- NotchFlow is not a general-purpose menu bar replacement or system monitor.
- NotchFlow does not attempt to be a public developer platform in V1. A public API and SDK are explicitly future work.

## V1 Feature List (User-Visible Capabilities)

The first release includes:

- **Music now-playing and transport control** — see the current track from Spotify, Apple Music, YouTube Music, and other supported sources, with play/pause and next/previous controls, in both a compact and an expanded view.
- **Countdown timer and stopwatch** — start a countdown or a stopwatch and watch the remaining or elapsed time live in the notch.
- **Screen recording indicator** — a clear "Recording" indicator with an elapsed-time counter while the screen is being recorded.
- **Audio recording indicator** — the same live indicator treatment for microphone recording.
- **Charging state** — a brief notification when the MacBook starts charging and again when it reaches a full charge, without a persistent battery-percentage display.
- **AI agent status** — live status for Claude Code, Codex, and OpenCode (terminal-based, best-effort), showing whether the agent is working, needs input, or has finished a task.
- **Multiple simultaneous activities** — several activities (for example, music plus a timer plus a file transfer) can be visible and prioritized in the same expanded view at once.

## What V1 Deliberately Excludes

The following are recognized as valuable but are intentionally out of scope for V1. Full detail, reasoning, and revisit triggers live in `docs/13-deferred-backlog.md`.

- **Incoming calls** — macOS has no public API for observing call state from third-party apps such as FaceTime or Phone Link; would require unsupported private frameworks.
- **AirDrop progress** — there is no public, sanctioned way to read AirDrop transfer progress from outside the Finder/AirDrop process.
- **Third-party download progress** — showing another app's download progress would require inspecting that app's internals, which is not available through public APIs and conflicts with the App Sandbox model.
- **Live Activities for navigation, food delivery, shipping, and live sports scores** (V1.5) — these depend on third-party data integrations that are a separate, larger effort from the core notch system.
- **Touch ID-related system status surfacing** (V1.5) — deferred until the core activity system is stable and proven in daily use.
- **Smart home status** (V2) — a distinct integration surface (HomeKit and third-party ecosystems) that deserves its own design pass.
- **Additional AI app support: ChatGPT, Gemini, Cursor, VS Code/Copilot** (V2) — V1 focuses on validating the AI-status architecture with three agents before widening the list.
- **Third-party developer API and SDK, including a `NotchFlow.show(...)`-style public interface** (V2) — opening the platform to outside developers is a governance and stability commitment that comes after the core product has shipped and settled.

## Success Criteria

NotchFlow's V1 is successful when a user can:

- Glance at the notch and correctly identify what's currently happening on their Mac (music, timer, recording, charging, or AI status) without opening any other app.
- Control music playback (play/pause, skip) directly from the notch during normal use.
- Trust that when nothing is happening, the notch is visually silent and the app is not measurably draining battery or CPU.
- See their AI coding agent's status update in near real time while working in the terminal or an IDE, without configuring anything beyond the provided hook scripts.
- Install the app from either the Mac App Store or Homebrew and get the same core experience, with only the music-provider mechanism differing under the hood.

## Source of Truth

This document is derived from `draft.md`, sections 1 (Projenin amacı), 8 (İlk sürüm özellikleri — V1), 16 (V1.5), 17 (V2), and 22 (Marka ve isim). Where `draft.md` and this document diverge, this document is the current authority for V1 scope; `draft.md` remains the original raw notes for reference.
