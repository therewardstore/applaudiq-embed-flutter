#!/usr/bin/env bash
# Publish applaudiq_embed to pub.dev. Run from anywhere; resolves the package dir itself.
# Usage:
#   tool/publish.sh            # validate + dry-run + publish (prompts before publishing)
#   tool/publish.sh --dry-run  # validate + dry-run only, no publish
#   tool/publish.sh --tag      # also create & push the git tag after a successful publish
set -euo pipefail

# --- locate flutter/dart (added to PATH if missing) ---
if ! command -v flutter >/dev/null 2>&1; then
  export PATH="$HOME/development/flutter/bin:$PATH"
fi
command -v flutter >/dev/null 2>&1 || { echo "ERROR: flutter not found on PATH"; exit 1; }

# --- always operate from the package root (dir above tool/) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

DRY_ONLY=false
DO_TAG=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_ONLY=true ;;
    --tag)     DO_TAG=true ;;
    *) echo "Unknown arg: $arg"; exit 2 ;;
  esac
done

VERSION="$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')"
echo "==> applaudiq_embed v${VERSION}"

echo "==> flutter pub get";  flutter pub get
echo "==> flutter analyze";  flutter analyze
echo "==> flutter test";     flutter test
echo "==> dart pub publish --dry-run"; dart pub publish --dry-run

if [ "$DRY_ONLY" = true ]; then
  echo "==> dry-run only; stopping before publish."; exit 0
fi

echo "==> flutter pub publish (will prompt for confirmation)"
flutter pub publish

if [ "$DO_TAG" = true ]; then
  echo "==> tagging v${VERSION}"
  git tag "$VERSION"
  git push origin --tags
fi

echo "==> done. Check https://pub.dev/packages/applaudiq_embed"
