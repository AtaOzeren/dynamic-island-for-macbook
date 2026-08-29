# NotchFlow

> Live activities and AI agent status surface for your MacBook notch.

NotchFlow turns your MacBook notch into a functional status and control surface. It presents live activity cards — music playback controls, countdown timers and stopwatches, recording indicators, charging status, and live AI agent status (Claude Code, Codex CLI, OpenCode) — right where your notch is, while staying at zero CPU when idle.

![NotchFlow Screenshot Placeholder](docs/assets/screenshot-placeholder.png)

## Overview & Documentation

For complete technical documentation, architecture decisions, and design specifications, see the [Documentation Index](docs/README.md).

> **Naming Note:** NotchFlow is an independent project. Apple, MacBook, and Dynamic Island are trademarks of Apple Inc. NotchFlow does not use Apple trademarks in its product name or metadata.

## Installation

- **Direct Download (Homebrew / Notarized DMG):** *Coming Soon*
- **Mac App Store:** *Coming Soon*

## Building from Source

### Prerequisites

- macOS 14.0 or later
- Xcode 16.0 or later (Swift 6 toolchain)

### Build Commands

Build the Swift Package and run tests:

```bash
swift test
```

Build the Xcode schemes:

```bash
# Debug build
xcodebuild -scheme NotchFlow build

# App Store build configuration
xcodebuild -scheme "NotchFlow (App Store)" build

# Direct / Homebrew build configuration
xcodebuild -scheme "NotchFlow (Direct)" build
```

## License

NotchFlow is released under the [MIT License](LICENSE).
