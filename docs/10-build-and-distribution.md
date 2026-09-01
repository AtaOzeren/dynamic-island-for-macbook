# Build and Distribution

NotchFlow ships from one codebase in two forms: a sandboxed Mac App Store build and a Developer ID signed, notarized build for direct download and Homebrew. This document specifies how the split is implemented, the release pipeline for each channel, and which steps cannot proceed until the Apple Developer Program membership is purchased. It is a design specification, nothing in this folder is code.

## The two build configurations

| | `AppStore` | `Direct` |
|---|---|---|
| Sandbox | App Sandbox on | Sandbox on where possible, hardened runtime is the primary constraint |
| Signing | Apple Distribution certificate | Developer ID Application certificate |
| Music provider | AppleScript (Spotify, Apple Music) | MediaRemote (any media app) |
| AI integration | IPC only | IPC, plus optional agent session log reading |
| Private frameworks | None, enforced by build guard | Allowed, MediaRemote is a private framework |
| Distribution | App Store Connect, reviewed | `.dmg` on GitHub Releases, and a Homebrew Cask |
| Update mechanism | App Store automatic updates | Homebrew Cask upgrade, or manual `.dmg` reinstall |

`docs/15-build-configuration-parity.md` carries the user-facing consequences of this table — which capabilities the sandbox removes, measured rather than inferred, and what would have to become true to close each gap.

Both configurations build from the same `NotchFlowCore`, `NotchFlowProviders`, and `NotchFlowUI` targets described in `01-architecture.md`. Only the provider chosen at compile time and the entitlements file differ.

## How the split is implemented

- **Build configurations.** Two Xcode build configurations, `AppStore` and `Direct`, each inheriting from Debug/Release as needed. Every scheme picks one configuration; there is no configuration that mixes the two.
- **Swift compilation conditions.** Each configuration defines a matching active compilation condition (`APPSTORE_BUILD` or `DIRECT_BUILD`). `NotchFlowProviders` uses this to select the music provider implementation at compile time, not at runtime, so the App Store binary never links the MediaRemote symbol table at all.
- **Per-configuration entitlements files.** `NotchFlow-AppStore.entitlements` and `NotchFlow-Direct.entitlements`, each listing only the entitlements that configuration needs, per the table in `09-security-privacy-permissions.md`.
- **Separate schemes.** `NotchFlow (App Store)` and `NotchFlow (Direct)`, each pinned to its configuration, its entitlements file, and its signing identity, so `xcodebuild -scheme "NotchFlow (App Store)"` and `xcodebuild -scheme "NotchFlow (Direct)"` are the two build entry points CI and local development both use.
- **Forbidden-symbol build guard.** A post-build script phase, attached only to the `AppStore` scheme, that runs `nm` (or `strings`, as a fallback for stripped binaries) against the built product and greps for `MediaRemote` and `MRMediaRemote`. Any match exits non-zero and fails the build before it reaches archiving. This is the same guard specified in todo 21 of the work plan; this document is the contract it must satisfy, and that todo is the implementation.

```bash
# Forbidden-symbol guard, sketch of the check the script phase runs
BINARY_PATH="$TARGET_BUILD_DIR/$EXECUTABLE_PATH"
if nm "$BINARY_PATH" 2>/dev/null | grep -qi "mediaremote"; then
  echo "error: forbidden MediaRemote symbol found in App Store binary"
  exit 1
fi
if strings "$BINARY_PATH" | grep -qi "mediaremote"; then
  echo "error: forbidden MediaRemote string found in App Store binary"
  exit 1
fi
```

## Version and build-number policy

- **Marketing version** (`CFBundleShortVersionString`) is one value shared by both configurations for a given release, so `AppStore` 1.2.0 and `Direct` 1.2.0 ship the same feature set.
- **Build number** (`CFBundleVersion`) increments per submission, independently per channel, since App Store Connect and notarization each track their own build history. A release tag in git (`v1.2.0`) is the source of truth that ties the two channel-specific build numbers back to one point in the codebase.
- Both channels are cut from the same tagged commit. A channel is never released from a commit the other channel has not also been offered, so a user on either channel is never more than one release behind the other in features.

## App Store pipeline

1. **Bundle identifier.** Reverse-DNS under the developer's own domain, for example `dev.<author>.notchflow`. Never contains "dynamicisland" or "macbook", per the naming rule in `14-glossary-and-conventions.md`.
2. **Category.** Utilities, as the closest fit for a menu-bar-adjacent, always-on-top status surface.
3. **Required metadata.** App name, subtitle, description, keywords, support URL, marketing URL, and the privacy policy URL, all drafted in `docs/` before submission so review notes and App Store copy stay in sync.
4. **Screenshots.** One set per required display size, captured with the notch overlay actively showing at least one real activity (music, timer, AI status) so reviewers see the feature working, not an empty state.
5. **Privacy nutrition label.** Answered directly from the data collection statement in `09-security-privacy-permissions.md`: no data collected, no tracking, since NotchFlow has no analytics and no network calls beyond the loopback listener.
6. **Review notes.** A short explanation, submitted with every version, stating that the always-on-top overlay window is core to the app's function (an ambient status surface, not an interstitial or ad), and that no private API or private framework is present, backed by the forbidden-symbol guard's build log.
7. **Review risk.** An always-on-top, click-through overlay is an unusual window class for reviewers to evaluate, and Apple's guidelines on overlay windows have tightened before without notice. The mitigation is the review notes above, a demo video attached to the submission, and a fallback plan of shipping the `Direct` build first if the App Store submission is rejected or delayed, since the two channels are independent.

**Membership-gated:** bundle identifier registration, App Store Connect record creation, and TestFlight or App Store submission itself all require an active, paid Apple Developer Program membership and cannot proceed without it.

## Direct pipeline

1. **Developer ID signing.** The `Direct` scheme's archive is signed with a Developer ID Application certificate rather than an Apple Distribution certificate.
2. **Hardened runtime.** Enabled on the `Direct` configuration with the minimum entitlement set from `09-security-privacy-permissions.md`; this is a notarization requirement, not optional hardening.
3. **`notarytool` submission.** The archived, signed app is zipped and submitted with `xcrun notarytool submit`, then the result is checked with `xcrun notarytool log` if it fails.

```bash
xcrun notarytool submit NotchFlow.zip \
  --keychain-profile "notchflow-notary" \
  --wait
```

4. **Stapling.** On success, the notarization ticket is attached to the app bundle with `xcrun stapler staple NotchFlow.app`, so the app opens offline without a Gatekeeper network check.
5. **`.dmg` layout.** A disk image containing `NotchFlow.app` and an `Applications` symlink, background image optional, built with `create-dmg` or a hand-rolled `hdiutil` script, then itself notarized and stapled.
6. **GitHub Releases.** The stapled `.dmg`, its SHA-256 checksum, and release notes are attached to a GitHub Release tagged with the version, which is also the artifact the Homebrew Cask points to.
7. **Homebrew Cask submission.** A cask stanza submitted to `homebrew-cask` (or a project-owned tap for early releases), pointing at the GitHub Release asset:

```ruby
cask "notchflow" do
  version "1.2.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/<owner>/notchflow/releases/download/v#{version}/NotchFlow-#{version}.dmg"
  name "NotchFlow"
  desc "Turns the MacBook notch into a live-activity island"
  homepage "https://github.com/<owner>/notchflow"

  depends_on macos: ">= :sonoma"

  app "NotchFlow.app"

  zap trash: [
    "~/Library/Preferences/dev.<author>.notchflow.plist",
    "~/Library/Application Support/NotchFlow",
  ]
end
```

**Membership-gated:** Developer ID certificate issuance, the `notarytool` submission itself, and stapling (since a stapled ticket only exists after a successful notarization) all require the paid Apple Developer Program membership. Local development and ad-hoc-signed debug builds are not blocked, only the release pipeline is.

## Blocked-on-membership summary

As of this writing, the Apple Developer Program membership has not been purchased. Every step above that needs it is listed explicitly rather than skipped, so the pipeline is ready to run the moment membership is active:

- Bundle identifier registration and App Store Connect record creation.
- TestFlight distribution and App Store submission.
- Developer ID Application certificate issuance.
- `notarytool` submission and stapling.

Local development proceeds today with ad-hoc signing on both schemes; only the four steps above are on hold.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `codesign` fails with "no identity found" | Wrong keychain selected, or certificate not yet issued | Confirm the certificate is in the login keychain with `security find-identity -v -p codesigning` |
| `notarytool submit` returns `Invalid` | Missing hardened runtime, an unsigned nested binary, or a disallowed entitlement | Run `xcrun notarytool log <submission-id>` for the itemized reason, then re-check the entitlements file |
| Notarization succeeds but Gatekeeper still blocks the app | Stapling step was skipped or ran before notarization finished | Re-run `xcrun stapler staple`, and verify with `xcrun stapler validate` |
| App Store build fails at the forbidden-symbol guard | A dependency (including a transitive one) pulled in MediaRemote | Check `Direct`-only dependencies did not leak into the shared target, then re-run `nm` locally before resubmitting |
| Homebrew Cask install fails with a checksum mismatch | The `.dmg` was rebuilt after the cask stanza was written | Recompute `sha256` from the actual released asset, never from a local rebuild |
