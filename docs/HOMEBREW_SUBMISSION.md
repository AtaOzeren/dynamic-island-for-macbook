# Homebrew Cask Submission Checklist

The repository keeps the proposed cask at `Casks/notchflow.rb`. It is ready for
local validation, but it must not be submitted to `Homebrew/homebrew-cask` until
the Direct release is signed with Developer ID, notarized, stapled, and published
as a stable GitHub Release.

## Release gate

- [ ] Purchase the Apple Developer Program membership and configure the signing
      and notarization secrets described in `docs/10-build-and-distribution.md`.
- [ ] Create a stable `vX.Y.Z` tag whose version matches the app's
      `CFBundleShortVersionString` and the cask's `version` stanza.
- [ ] Confirm the release workflow publishes
      `NotchFlow-X.Y.Z-direct.dmg` and its `.sha256` file.
- [ ] Confirm the GitHub Release is public, stable (not a draft or prerelease),
      and uses the matching `vX.Y.Z` tag.
- [ ] Download the published DMG and verify its notarization and Gatekeeper
      acceptance:

  ```bash
  xcrun stapler validate NotchFlow-X.Y.Z-direct.dmg
  spctl --assess --type open --context context:primary-signature -vv \
    NotchFlow-X.Y.Z-direct.dmg
  ```

Do not continue if any release-gate item fails. An ad-hoc-signed local artifact
is suitable for developing the cask, but not for submission or user installation.

## Finalize the cask

- [ ] Copy `Casks/notchflow.rb` to the local `Homebrew/homebrew-cask` checkout at
      `Casks/n/notchflow.rb`.
- [ ] Replace `version` with the stable release version.
- [ ] Replace `REPLACE_WITH_NOTARIZED_DMG_SHA256` with the SHA-256 of the exact
      published DMG:

  ```bash
  shasum -a 256 NotchFlow-X.Y.Z-direct.dmg
  ```

- [ ] Confirm the interpolated `url` downloads that exact asset without
      authentication or redirects to a mutable artifact.
- [ ] Confirm the cask token is not already present or listed among refused casks.
- [ ] Recheck every `zap` path against the installed release. Never add a broad
      parent directory or any path shared with another app.

## Local validation

From the `Homebrew/homebrew-cask` checkout, run:

```bash
export HOMEBREW_NO_INSTALL_FROM_API=1
brew style --fix Casks/n/notchflow.rb
brew audit --cask --new --online notchflow
brew install --cask notchflow
open -a NotchFlow
brew uninstall --cask notchflow
brew install --cask notchflow
brew uninstall --cask --zap notchflow
```

- [ ] The style and audit commands finish without offenses or errors.
- [ ] Installation copies `NotchFlow.app` to `/Applications`.
- [ ] The app launches without a Gatekeeper warning on a clean macOS 14 or newer
      system.
- [ ] Ordinary uninstall removes the app and leaves user data intact.
- [ ] `--zap` removes only NotchFlow's preferences and application-support data.
- [ ] Save the complete command output as
      `.omo/evidence/task-71-notchflow-v1.log` for the plan's QA evidence.

## Submit upstream

- [ ] Create a branch in a personal fork of `Homebrew/homebrew-cask` and commit
      only `Casks/n/notchflow.rb`.
- [ ] Open the pull request using Homebrew's template.
- [ ] Confirm the submission is for a stable version and disclose any AI/LLM use
      as required by the current template.
- [ ] Check every template item only after reproducing it locally, then monitor
      CI and respond to maintainer review.

If Homebrew declines the initial submission because the app is too new to meet
its notability requirements, keep this cask in a project-owned tap and resubmit
only after the project qualifies.
