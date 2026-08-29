# Contributing to NotchFlow

Thank you for your interest in contributing to NotchFlow!

## Development Workflow & TDD

1. **Test-Driven Development (TDD):** All domain logic in `NotchFlowCore` must be written test-first. Keep `NotchFlowCore` pure Foundation without importing AppKit or SwiftUI.
2. **Module Separation:**
   - `NotchFlowCore`: Pure business logic, state machines, geometry calculations, and protocols. Imports Foundation only.
   - `NotchFlowProviders`: OS integrations, ScriptingBridge/MediaRemote, ScreenCaptureKit, IOKit, and IPC listeners.
   - `NotchFlowUI`: SwiftUI compact/expanded view components and `NSPanel` presentation controller.
   - `NotchFlow`: Application entry point and composition root.

## Building and Testing

Run tests locally:
```bash
swift test
```

Check code formatting and linting:
```bash
swiftformat --lint .
swiftlint --strict
```

## Commit Convention

NotchFlow follows the [Conventional Commits](https://www.conventionalcommits.org/) specification:

- `feat(<scope>): description` — New functionality
- `fix(<scope>): description` — Bug fixes
- `docs(<scope>): description` — Documentation changes
- `refactor(<scope>): description` — Code refactoring
- `test(<scope>): description` — Adding or modifying tests
- `build(<scope>): description` — Build system or tooling changes
- `ci(<scope>): description` — CI workflow updates

Scope rules:
- Feature scopes (e.g. `(display)`, `(ui)`, `(ipc)`) or architecture layers.

## Pull Request Checklist

Before submitting a PR, ensure:
- [ ] `swift test` passes with zero failures.
- [ ] `NotchFlowCore` does not import AppKit or SwiftUI.
- [ ] All code comments explain *why* decision was made (no change-tracking comments or obsolete code).
- [ ] Commits follow Conventional Commits formatting.
