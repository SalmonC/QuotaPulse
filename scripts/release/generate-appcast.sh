#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RELEASE_DIR="${RELEASE_DIR:-$PROJECT_ROOT/Artifacts/release}"
APPCAST_PATH="${APPCAST_PATH:-$RELEASE_DIR/appcast.xml}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/SalmonC/QuotaPulse/releases/download}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX%/}/"
DEFAULT_SPARKLE_KEY_PATH="$HOME/.config/quotapulse/sparkle_private_key"
SPARKLE_PRIVATE_KEY_PATH="${SPARKLE_PRIVATE_KEY_PATH:-$DEFAULT_SPARKLE_KEY_PATH}"
GENERATE_APPCAST_BIN="${GENERATE_APPCAST_BIN:-}"

if [[ ! -f "$SPARKLE_PRIVATE_KEY_PATH" ]]; then
  echo "Sparkle private key not found: $SPARKLE_PRIVATE_KEY_PATH" >&2
  echo "Set SPARKLE_PRIVATE_KEY_PATH to your EdDSA private key file." >&2
  exit 1
fi

if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "Release dir not found: $RELEASE_DIR" >&2
  exit 1
fi

if [[ -z "$GENERATE_APPCAST_BIN" ]]; then
  if command -v generate_appcast >/dev/null 2>&1; then
    GENERATE_APPCAST_BIN="$(command -v generate_appcast)"
  else
    echo "Cannot find generate_appcast. Set GENERATE_APPCAST_BIN explicitly." >&2
    exit 1
  fi
fi

echo "[appcast] Generating appcast from: $RELEASE_DIR"
"$GENERATE_APPCAST_BIN" \
  "$RELEASE_DIR" \
  --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  -o "$APPCAST_PATH"

echo "[appcast] Generated: $APPCAST_PATH"
