# Build and Distribution

KerNotch ships from one codebase as one build: a Developer ID signed, notarized app, distributed as a disk image on GitHub Releases (and later on the project website) and through a Homebrew Cask that points at the same disk image. This document specifies the build configuration, the checks CI runs against it, the release pipeline, and which steps cannot proceed until the Apple Developer Program membership is purchased. It is a design specification, nothing in this folder is code.

## The build

| | |
|---|---|
| Scheme | `KerNotch`, the only shared scheme |
| Configurations | `Debug` for development, `Release` for everything shipped; the scheme's Profile and Archive actions use `Release` |
| Signing | Developer ID Application certificate; ad-hoc until the membership exists |
| Hardened runtime | On in both configurations |
| Entitlements | `KerNotch.entitlements` in both configurations, containing only `com.apple.security.automation.apple-events` (see `09-security-privacy-permissions.md`). `Release` also sets `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`, so Xcode does not add the `get-task-allow` debugging entitlement that notarization rejects |
| App Sandbox | Off |
| Music provider | Chosen at launch by macOS release: ScriptingBridge (Spotify, Apple Music) on 15.4 and later, MediaRemote (system-wide now playing) below (see `06-activity-providers.md`) |
| Discord integration | Always compiled in |
| Distribution | `KerNotch-<version>.dmg` on GitHub Releases, later also offered on the project website, and a Homebrew Cask pointing at the GitHub Release asset |
| Update mechanism | `brew upgrade --cask kernotch`, or installing a newer `.dmg` by hand |

The app target builds on the same `KerNotchCore`, `KerNotchProviders`, and `KerNotchUI` targets described in `01-architecture.md`. There are no Swift compilation conditions selecting features: every provider and integration is in every build, and the one provider branch — the music backend — is a runtime availability check.

```bash
# Development
xcodebuild -scheme KerNotch -configuration Debug build

# The configuration that is signed, notarized and packaged
xcodebuild -scheme KerNotch -configuration Release build
```

`ExportOptions.plist` (method `developer-id`) holds the options for exporting a Developer ID archive with `xcodebuild -exportArchive`. The release script below does not archive: it builds `Release`, then signs, notarizes and packages the product itself.

## CI checks

`.github/workflows/ci.yml` runs on pushes and pull requests, on a pinned macOS runner and Xcode version:

| Step | Command | Fails when |
|---|---|---|
| Package tests | `swift test` | Any test fails |
| Format lint | `swift format lint --recursive Sources Tests KerNotch` | A file violates the checked-in format configuration |
| Core dependency guard | `./scripts/check-core-dependencies.sh` | `KerNotchCore` imports AppKit, SwiftUI, `KerNotchProviders`, or `KerNotchUI` (`01-architecture.md`) |
| Translation guard | `./scripts/check-translations.sh` | A String Catalog lacks a language another catalog carries |
| Asset guard | `./scripts/check-assets.sh` | An app icon size the asset catalog promises is missing or has the wrong pixel dimensions |
| Release build | `xcodebuild -scheme KerNotch -configuration Release -destination "platform=macOS" build` | The app does not build |
| Music backend guard | `./scripts/check-music-backend.sh` | The Release product's `--print-music-backend` output is not the backend the runner's macOS version calls for: `ScriptingBridge` on 15.4 and later, `MediaRemote` below |
| MediaRemote-linked guard | `./scripts/check-media-remote-linked.sh <binary>` | The Release binary lacks the MediaRemote framework path the bridge passes to `dlopen`, or the now-playing notification name it subscribes to |

The last guard exists because the MediaRemote backend is resolved with `dlopen`/`dlsym`: nothing at compile time notices if it drops out of the build, and on macOS releases before 15.4 that would silently remove music from the island. The check looks for the exact strings the bridge needs rather than the word "MediaRemote", which type names and the backend's display name would satisfy even with the bridge cut out:

```bash
# MediaRemote-linked guard, the check the script runs
REQUIRED_STRINGS=(
    "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
)
BINARY_STRINGS=$(strings "$BINARY_PATH")
for required in "${REQUIRED_STRINGS[@]}"; do
    grep -Fq -- "$required" <<<"$BINARY_STRINGS" || exit 1
done
```

## Version and build-number policy

- **Marketing version** (`CFBundleShortVersionString`, from `MARKETING_VERSION`) is one value per release, and every artifact carries it: tag `v1.2.0`, disk image `KerNotch-1.2.0.dmg`, cask `version "1.2.0"`.
- **Build number** (`CFBundleVersion`, from `CURRENT_PROJECT_VERSION`) increments with every build submitted for notarization.
- A release tag in git is the source of truth that ties the published disk image back to one commit. The project website, once it exists, is another download location for that same disk image.

## Release pipeline

1. **Tag.** Pushing a `v*` tag runs `.github/workflows/release.yml` ("Release").
2. **Signing credentials.** When the `DEVELOPER_ID_APPLICATION` secret is set, the workflow imports the Developer ID certificate into a temporary keychain and stores a `notarytool` keychain profile in it. Without the secrets the workflow still runs and produces an ad-hoc signed disk image.
3. **Tests.** `swift test`.
4. **Package.** `./scripts/package-release.sh`:
   - builds `-scheme KerNotch -configuration Release` with Xcode signing off, into `DerivedData.noindex/ReleasePackage` by default (the `.noindex` suffix keeps the build product out of Spotlight and Launchpad);
   - signs the app with `codesign --options runtime --entitlements KerNotch.entitlements --timestamp` using the Developer ID identity, or ad-hoc when `DEVELOPER_ID_APPLICATION` is unset, reporting `SKIPPED (no membership): Developer ID signing`;
   - verifies the signature with `codesign --verify --deep --strict`;
   - when `NOTARYTOOL_KEYCHAIN_PROFILE` is set, zips the app, submits it with `xcrun notarytool submit --wait`, then staples and validates the ticket; otherwise it reports notarization and stapling as skipped;
   - builds `KerNotch-<version>.dmg` with `hdiutil` from a folder holding `KerNotch.app` and an `Applications` symlink, and, with credentials present, notarizes, staples and validates the disk image as well;
   - writes `KerNotch-<version>.dmg.sha256` beside it, in `dist/` by default;
   - withdraws the build products' LaunchServices registration, so no second `KerNotch.app` appears beside the installed one.

   `DEVELOPER_ID_APPLICATION` and `NOTARYTOOL_KEYCHAIN_PROFILE` must be set together; the script refuses one without the other.
5. **MediaRemote-linked guard** against the packaged binary.
6. **Publish.** The disk image and its checksum are uploaded as a workflow artifact and attached to a GitHub Release for the tag, with generated release notes.
7. **Homebrew Cask.** `Casks/kernotch.rb` points at the GitHub Release asset. `docs/HOMEBREW_SUBMISSION.md` is the checklist for finalizing and submitting it once a notarized release exists:

```ruby
cask "kernotch" do
  version "1.0.0"
  sha256 "REPLACE_WITH_NOTARIZED_DMG_SHA256"

  url "https://github.com/AtaOzeren/dynamic-island-for-macbook/releases/download/v#{version}/KerNotch-#{version}.dmg"
  name "KerNotch"
  desc "Live activities and AI agent status in the MacBook notch"
  homepage "https://github.com/AtaOzeren/dynamic-island-for-macbook"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "KerNotch.app"

  zap trash: [
    "~/Library/Application Support/KerNotch",
    "~/Library/Preferences/com.kernotch.KerNotch.plist",
  ]
end
```

**Membership-gated:** Developer ID certificate issuance, the `notarytool` submission itself, and stapling (since a stapled ticket only exists after a successful notarization) all require the paid Apple Developer Program membership, and the Homebrew submission waits on a notarized release. Local development and ad-hoc-signed builds are not blocked, only the signed release is.

## Blocked-on-membership summary

As of this writing, the Apple Developer Program membership has not been purchased. Every step above that needs it is listed explicitly rather than skipped, so the pipeline is ready to run the moment membership is active:

- Developer ID Application certificate issuance.
- `notarytool` submission and stapling.
- Submitting the Homebrew Cask upstream, which requires a notarized, stapled release.

Local development and the release workflow proceed today with ad-hoc signing; only the steps above are on hold.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `codesign` fails with "no identity found" | Wrong keychain selected, or certificate not yet issued | Confirm the certificate is in the login keychain with `security find-identity -v -p codesigning` |
| `notarytool submit` returns `Invalid` | Missing hardened runtime, an unsigned nested binary, a debugging entitlement, or a disallowed entitlement | Run `xcrun notarytool log <submission-id>` for the itemized reason, then re-check `KerNotch.entitlements` and the signing flags |
| Notarization succeeds but Gatekeeper still blocks the app | Stapling step was skipped or ran before notarization finished | Re-run `xcrun stapler staple`, and verify with `xcrun stapler validate` |
| The MediaRemote-linked guard fails | `KerNotch/MediaRemoteMusicProvider.swift` or `KerNotch/SystemNowPlayingBridge+MediaRemote.swift` left the `KerNotch` target, or the check ran against the wrong binary | Restore target membership, and confirm the path points at `Release/KerNotch.app/Contents/MacOS/KerNotch` |
| The music backend guard reports the wrong backend | The availability branch in `KerNotch/MusicBackend.swift` changed, or a stale product was checked | Fix the branch, then re-run `./scripts/check-music-backend.sh --force` to rebuild before checking |
| Homebrew Cask install fails with a checksum mismatch | The `.dmg` was rebuilt after the cask stanza was written | Recompute `sha256` from the actual released asset, never from a local rebuild |
