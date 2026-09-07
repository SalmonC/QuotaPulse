#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_PATH="${SOURCE_PATH:-${APPCAST_PATH:-$PROJECT_ROOT/Artifacts/release/appcast.xml}}"
TARGET_NAME="${TARGET_NAME:-appcast.xml}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
PAGES_SUBDIR="${PAGES_SUBDIR:-.}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-chore(release): update appcast}"
PUBLISH_LEGACY_APPCAST="${PUBLISH_LEGACY_APPCAST:-1}"
LEGACY_APPCAST_REPO="${LEGACY_APPCAST_REPO:-SalmonC/salmonc.github.io}"
LEGACY_APPCAST_BRANCH="${LEGACY_APPCAST_BRANCH:-main}"
LEGACY_APPCAST_PATH="${LEGACY_APPCAST_PATH:-ApiUsageTrackerForMac/appcast.xml}"

if [[ ! -f "$SOURCE_PATH" ]]; then
  echo "Pages source not found: $SOURCE_PATH" >&2
  exit 1
fi

if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: $PROJECT_ROOT" >&2
  exit 1
fi

WORKTREE_DIR="$(mktemp -d /tmp/quotapulse-pages.XXXXXX)"
cleanup() {
  git -C "$PROJECT_ROOT" worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "[pages] Preparing worktree for branch: $PAGES_BRANCH"
git -C "$PROJECT_ROOT" fetch origin "$PAGES_BRANCH":"$PAGES_BRANCH" >/dev/null 2>&1 || true
git -C "$PROJECT_ROOT" worktree add "$WORKTREE_DIR" "$PAGES_BRANCH"

TARGET_DIR="$WORKTREE_DIR/$PAGES_SUBDIR"
mkdir -p "$TARGET_DIR"
cp "$SOURCE_PATH" "$TARGET_DIR/$TARGET_NAME"

if [[ -n "$(git -C "$WORKTREE_DIR" status --porcelain)" ]]; then
  git -C "$WORKTREE_DIR" add "$TARGET_DIR/$TARGET_NAME"
  git -C "$WORKTREE_DIR" commit -m "$COMMIT_MESSAGE"
  git -C "$WORKTREE_DIR" push origin "$PAGES_BRANCH"
  echo "[pages] Published $TARGET_NAME to $PAGES_BRANCH/$PAGES_SUBDIR"
else
  echo "[pages] No $TARGET_NAME changes to publish."
fi

# Repository renames change a GitHub Pages project URL. Keep the old Sparkle
# feed alive from the account-level Pages site so already-installed versions
# can still discover future releases.
if [[ "$PUBLISH_LEGACY_APPCAST" == "1" && "$TARGET_NAME" == "appcast.xml" && "$PAGES_SUBDIR" == "." ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "[pages] gh is required to publish the legacy appcast feed." >&2
    exit 1
  fi

  LEGACY_CONTENT_B64="$(base64 < "$SOURCE_PATH" | tr -d '\n')"
  LEGACY_ENDPOINT="repos/$LEGACY_APPCAST_REPO/contents/$LEGACY_APPCAST_PATH"
  LEGACY_SHA="$(gh api "$LEGACY_ENDPOINT?ref=$LEGACY_APPCAST_BRANCH" --jq .sha 2>/dev/null || true)"

  LEGACY_ARGS=(
    -X PUT "$LEGACY_ENDPOINT"
    -f "message=chore(compat): update legacy Sparkle feed"
    -f "branch=$LEGACY_APPCAST_BRANCH"
    -f "content=$LEGACY_CONTENT_B64"
  )
  if [[ -n "$LEGACY_SHA" ]]; then
    LEGACY_ARGS+=( -f "sha=$LEGACY_SHA" )
  fi

  gh api "${LEGACY_ARGS[@]}" --jq '{commit:.commit.sha,path:.content.path}'
  echo "[pages] Published legacy appcast to $LEGACY_APPCAST_REPO/$LEGACY_APPCAST_PATH"
fi
