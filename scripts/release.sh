#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

"$ROOT_DIR/scripts/build-android.sh" --version "$VERSION"

VERSION_DIR="$ROOT_DIR/dist/$VERSION"
if [[ ! -d "$VERSION_DIR" ]]; then
  echo "Missing build output: $VERSION_DIR" >&2
  exit 1
fi

NOTES=$'Android/Termux build for expanso-edge.\n\nIncludes:\n- android/arm64\n\nChecksums: SHA256SUMS.txt'

gh release create "$VERSION" "$VERSION_DIR"/* \
  --repo aronchick/android-build \
  --notes "$NOTES"
