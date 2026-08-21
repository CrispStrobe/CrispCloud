# CrispCloud — Google Play submission package

Package: `com.crispstrobe.cloud`  
Release: `1.0.0` (`versionCode` 7)  
Category: Tools

## Assets

- `assets/icon-512.png` — Play Store icon, 512×512 PNG
- `assets/feature-graphic-1024x500.png` — feature graphic
- `assets/phone/*.png` — four 1080×1920 phone screenshots
- `metadata/en-US/` and `metadata/de-DE/` — localized listing copy

Regenerate visual assets deterministically. The script checks system load,
runs Flutter with one worker, and converts the output to Play-compatible
24-bit PNG without alpha:

```bash
./tool/generate_play_assets.sh
```

## Release flow

1. Run the `Google Play Bundle` GitHub Actions workflow.
2. Download `crispcloud-google-play-aab` from the workflow artifacts.
3. Create the app in Play Console with package `com.crispstrobe.cloud`.
4. Complete the declarations in `submission-checklist.md`.
5. Upload the AAB to **Testing → Closed testing**.
6. Copy its tester opt-in link into Testers Community.
7. Keep at least 12 testers opted in continuously for 14 days, then request
   production access.

Do not replace the upload keystore. Every future Play update must use the same
key already stored in the GitHub Android signing secrets.
