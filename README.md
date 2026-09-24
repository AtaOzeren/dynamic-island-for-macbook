# KerNotch

> Live activities and AI agent status surface for your MacBook notch.

KerNotch turns your MacBook notch into a functional status and control surface. It presents live activity cards — music playback controls, countdown timers and stopwatches, recording indicators, charging status, and live AI agent status (Claude Code, Codex CLI, OpenCode) — right where your notch is, while staying at zero CPU when idle.

![KerNotch Screenshot Placeholder](docs/assets/screenshot-placeholder.png)

## Overview & Documentation

For complete technical documentation, architecture decisions, and design specifications, see the [Documentation Index](docs/README.md).

> **Naming Note:** KerNotch is an independent project. Apple, MacBook, and Dynamic Island are trademarks of Apple Inc. KerNotch does not use Apple trademarks in its product name or metadata.

## Installation

KerNotch ships as one Developer ID signed, notarized build, in two packagings:

- **Notarized DMG:** `KerNotch-<version>.dmg` from [GitHub Releases](https://github.com/AtaOzeren/dynamic-island-for-macbook/releases), and later from the project website. *Coming Soon*
- **Homebrew Cask:** `brew install --cask kernotch`. *Coming Soon*

## Building from Source

### Prerequisites

- macOS 14.0 or later
- Xcode 26.0 or later (Swift 6.2 toolchain; `isolated deinit` requires it)

### Build Commands

Build the Swift Package and run tests:

```bash
swift test
```

Build the app with the `KerNotch` scheme:

```bash
# Debug build, for development
xcodebuild -scheme KerNotch -configuration Debug build

# Release build, the configuration that is signed, notarized and packaged
xcodebuild -scheme KerNotch -configuration Release build
```

Package the DMG locally (ad-hoc signed unless Developer ID and notarization credentials are set):

```bash
./scripts/package-release.sh
```

See [docs/10-build-and-distribution.md](docs/10-build-and-distribution.md) for signing, notarization and the release workflow.

### Discord integration in forks

The Discord integration connects through KerNotch's own Discord application, whose Client ID is set in [`Config/Discord.xcconfig`](Config/Discord.xcconfig). A Client ID is public, and no client secret exists in this repository. If you distribute your own build, put the Client ID of a Discord application you own there, or leave it empty to ship without the connection. See [docs/16-discord-application.md](docs/16-discord-application.md).

## License

KerNotch is released under the [MIT License](LICENSE).
