# Task 70 — Direct distribution packaging

Date: 2026-08-30

## Artifact

- `dist/NotchFlow-1.0.0-direct.dmg`
- `dist/NotchFlow-1.0.0-direct.dmg.sha256`
- Format: UDZO
- Volume: `NotchFlow`
- Layout: `NotchFlow.app` at root and `/Applications` symlink

## Local ad-hoc run

- Fresh Direct build: PASS
- Hardened-runtime ad-hoc signing: PASS
- Developer ID signing: SKIPPED (no membership)
- Notarization: SKIPPED (no membership)
- Stapling: SKIPPED (no membership)
- DMG creation: PASS
- SHA-256 verification: PASS
- Read-only mount and detach: PASS
- Bundle identifier: `com.notchflow.NotchFlow`
- Executable present: PASS
- Codesign verification: PASS

## Verification

- Packaging unit tests: 6 PASS
- Shell syntax: PASS
- Workflow YAML parse: PASS
- `swift test`: 531 tests in 56 suites PASS

## Logs

- `packaging.log`: complete build, signing, and packaging output
- `skipped-report.log`: verbatim membership-gated skip report
- `mount-verify.log`, `codesign-verify.log`: mounted artifact verification
- `checksum-verify.log`: sidecar verification
