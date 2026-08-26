# Sparkle Release Workflow (Stable Channel)

This directory contains release helpers for Sparkle-based in-app updates.

## Prerequisites

1. `Info.plist` has valid Sparkle settings:
   - `SUFeedURL`
   - `SUPublicEDKey`
2. You have:
   - Developer ID Application certificate
   - Notarytool keychain profile
   - Sparkle private EdDSA key file
3. `generate_appcast` is installed or built from Sparkle.

## 1) Build, Sign, Notarize, Package

```bash
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
NOTARY_PROFILE="notary-profile-name" \
./scripts/release/build-signed-archive.sh
```

Outputs in `Artifacts/release/`:
- `QuotaPulse-Release.zip` (Sparkle feed archive)
- `QuotaPulse-Release.dmg` (manual install)

## 2) Generate appcast.xml

```bash
SPARKLE_PRIVATE_KEY_PATH="/path/to/eddsa_private_key" \
DOWNLOAD_URL_PREFIX="https://github.com/SalmonC/ApiUsageTrackerForMac/releases/download/vX.Y.Z" \
./scripts/release/generate-appcast.sh
```

If `SPARKLE_PRIVATE_KEY_PATH` is omitted, the script defaults to:

`$HOME/.config/quotapulse/sparkle_private_key`

Notes:
- This script uses Sparkle `generate_appcast` with `-o` output.
- Keep only stable release assets in the release directory used for appcast generation.

## 3) Publish appcast.xml to GitHub Pages

```bash
APPCAST_PATH="Artifacts/release/appcast.xml" \
PAGES_BRANCH="gh-pages" \
PAGES_SUBDIR="." \
./scripts/release/publish-pages.sh
```

## 4) Publish GitHub Release

Upload the generated `.zip` and `.dmg` to the matching stable GitHub Release tag.

Recommended order:
1. Create stable tag/release.
2. Upload `.zip` + `.dmg`.
3. Publish `appcast.xml` to Pages.
4. Click in-app "Check for Updates" for validation.

## Publish the Codex pricing catalog

QuotaPulse checks a small validated catalog on GitHub Pages at most once per
day. After updating `Config/codex-pricing-v1.json` from the official OpenAI
pricing page, publish it with:

```bash
SOURCE_PATH="Config/codex-pricing-v1.json" \
TARGET_NAME="pricing-v1.json" \
COMMIT_MESSAGE="chore(pricing): update Codex API prices" \
./scripts/release/publish-pages.sh
```

The app keeps the last valid catalog and falls back to built-in prices when the
remote document is unavailable or fails validation.
