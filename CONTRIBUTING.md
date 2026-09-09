# Contributing to KerNotch

Thank you for your interest in contributing to KerNotch!

## Development Workflow & TDD

1. **Test-Driven Development (TDD):** All domain logic in `KerNotchCore` must be written test-first. Keep `KerNotchCore` pure Foundation without importing AppKit or SwiftUI.
2. **Module Separation:**
   - `KerNotchCore`: Pure business logic, state machines, geometry calculations, and protocols. Imports Foundation only.
   - `KerNotchProviders`: OS integrations, ScriptingBridge/MediaRemote, ScreenCaptureKit, IOKit, and IPC listeners.
   - `KerNotchUI`: SwiftUI compact/expanded view components and `NSPanel` presentation controller.
   - `KerNotch`: Application entry point and composition root.

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

KerNotch follows the [Conventional Commits](https://www.conventionalcommits.org/) specification:

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
- [ ] `KerNotchCore` does not import AppKit or SwiftUI.
- [ ] All code comments explain *why* decision was made (no change-tracking comments or obsolete code).
- [ ] Commits follow Conventional Commits formatting.
