#!/usr/bin/env sh
set -eu

REPO="aronchick/android-build"
BINARY_NAME="expanso-edge"
VERSION="${EXPANSO_VERSION:-latest}"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
INSTALL_DIR="${EXPANSO_INSTALL_DIR:-}"
CURRENT_DIR="$(pwd)"

arch_raw="$(uname -m)"
case "$arch_raw" in
  aarch64|arm64)
    arch="arm64"
    ;;
  armv7l|armv7|arm)
    arch="armv7"
    ;;
  *)
    echo "Unsupported architecture: $arch_raw" >&2
    exit 1
    ;;
esac

choose_install_dir() {
  if [ -n "$INSTALL_DIR" ]; then
    echo "Using install directory from EXPANSO_INSTALL_DIR: $INSTALL_DIR"
    return
  fi

  echo "Selecting install directory..."

  candidates="/usr/local/bin /opt/bin"
  if [ -n "${PREFIX:-}" ]; then
    candidates="${candidates} ${PREFIX}/bin"
  fi
  if [ -n "${HOME:-}" ]; then
    candidates="${candidates} ${HOME}/.local/bin"
  fi
  candidates="${candidates} ${CURRENT_DIR}"

  for dir in $candidates; do
    echo "Checking install directory: $dir"
    if [ -d "$dir" ]; then
      if [ -w "$dir" ]; then
        INSTALL_DIR="$dir"
        echo "Selected install directory: $INSTALL_DIR"
        return
      fi
      echo "  $dir is not writable."
      continue
    fi

    case "$dir" in
      "${HOME:-}/.local/bin"|"$CURRENT_DIR"|"${PREFIX:-}/bin")
        if mkdir -p "$dir" 2>/dev/null; then
          INSTALL_DIR="$dir"
          echo "Selected install directory: $INSTALL_DIR"
          return
        fi
        echo "  Unable to create $dir."
        ;;
      *)
        echo "  $dir is not available."
        ;;
    esac
  done

  echo "No suitable install directory found."
  echo "Set EXPANSO_INSTALL_DIR to a writable path and try again."
  exit 1
}

choose_install_dir

asset_name="${BINARY_NAME}-android-${arch}"

if [ "$VERSION" = "latest" ]; then
  asset_url="https://github.com/${REPO}/releases/latest/download/${asset_name}"
else
  case "$VERSION" in
    v*) tag="$VERSION" ;;
    *) tag="v${VERSION}" ;;
  esac
  asset_url="https://github.com/${REPO}/releases/download/${tag}/${asset_name}"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if [ -n "$TOKEN" ]; then
  if ! curl -fLS -H "Authorization: token ${TOKEN}" -o "$tmp_dir/${BINARY_NAME}" "$asset_url"; then
    echo "Error: download failed for ${asset_name} (version: ${VERSION})." >&2
    echo "Check that the release exists and the asset is published." >&2
    exit 1
  fi
else
  if ! curl -fLS -o "$tmp_dir/${BINARY_NAME}" "$asset_url"; then
    echo "Error: download failed for ${asset_name} (version: ${VERSION})." >&2
    echo "Check that the release exists and the asset is published." >&2
    exit 1
  fi
fi
chmod +x "$tmp_dir/${BINARY_NAME}"

mkdir -p "$INSTALL_DIR"
mv "$tmp_dir/${BINARY_NAME}" "$INSTALL_DIR/${BINARY_NAME}"

echo "Installed ${BINARY_NAME} to ${INSTALL_DIR}/${BINARY_NAME}"
