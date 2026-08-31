# App Store Submission Handoff

## Ready locally

- App Store scheme: `NotchFlow (App Store)` using the `AppStore` configuration
- Bundle identifier: `com.notchflow.NotchFlow`
- Version/build: `1.0.0` (`1`)
- Sandbox entitlements: `NotchFlow-AppStore.entitlements`
- Export options: `AppStore-ExportOptions.plist`
- English metadata: `docs/store/en/metadata.md`
- Turkish metadata: `docs/store/tr/metadata.md`
- Privacy policy: `docs/PRIVACY.md`
- Screenshot manifest: `docs/store/screenshots/README.md`

## Local validation

```bash
./scripts/package-app-store.sh
./scripts/check-app-store-screenshots.sh
```

Without an Apple Developer Program team, the first command creates an unsigned local archive and runs every offline check. The script reports distribution signing, provisioning, and App Store Connect validation as skipped instead of implying those checks passed.

## Complete after membership enrollment

1. Replace `DEVELOPER_TEAM_ID` in `AppStore-ExportOptions.plist` with the enrolled team ID.
2. Register `com.notchflow.NotchFlow` and create the app record in App Store Connect.
3. Create an Apple Distribution certificate and provisioning profile, then run:

   ```bash
   APPLE_TEAM_ID=YOUR_TEAM_ID ./scripts/package-app-store.sh
   ```

4. Open `dist/app-store/NotchFlow.xcarchive` in Xcode Organizer and run **Validate App**. Resolve every App Store Connect validation error before upload.
5. Capture or replace all five files in `docs/store/screenshots/en-US/`, then run the screenshot check.
6. Copy the localized metadata into App Store Connect, complete pricing/availability and the age-rating questionnaire, and confirm every privacy category is **Not Collected**.
7. Upload the validated archive from Organizer and submit it with the English review notes in `docs/store/en/metadata.md`.

Actual validation against App Store Connect and upload require active membership, distribution credentials, and an app record; they cannot be truthfully completed with an unsigned archive.
