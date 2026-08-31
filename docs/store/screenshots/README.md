# Mac App Store Screenshot Set

Upload the five `2560 × 1600` PNG files in `en-US/` in filename order. This is an accepted macOS screenshot size and supplies a complete default-localization set; App Store Connect can reuse it for Turkish until localized captures are available.

| File | Feature shown | Capture direction |
|---|---|---|
| `01-music.png` | Music playback | Expanded island with synthetic track and playback progress |
| `02-timer.png` | Countdown timer | Expanded island showing a running focus timer |
| `03-ai-agent.png` | AI agent progress | Expanded island showing synthetic agent progress |
| `04-recording.png` | Recording awareness | Expanded island showing an active recording and elapsed time |
| `05-settings.png` | Settings | Settings overview and available sections |

## Capture rules

- Regenerate the deterministic set with `swift scripts/generate-app-store-screenshots.swift`.
- Keep every image at exactly `2560 × 1600` pixels.
- Show only NotchFlow and neutral desktop content. Remove notifications, personal files, usernames, terminal text, and third-party account data.
- Use synthetic track, timer, agent, and recording content. Do not include real transcripts or media artwork without redistribution rights.
- Keep the illustrated Mac screen and notch visible in activity captures so placement is clear.
- Do not add device frames or claims that are absent from the metadata.
- Export 24-bit RGB PNG without alpha.

Run `./scripts/check-app-store-screenshots.sh` before upload. It rejects missing files, incorrect dimensions, transparency, and unexpected files.

Apple's current macOS screenshot specification accepts one to ten screenshots at `1280 × 800`, `1440 × 900`, `2560 × 1600`, or `2880 × 1800`: <https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications>.
