#!/usr/bin/env sh
set -eu

REPO="aronchick/android-build"
BINARY_NAME="expanso-edge"
VERSION="${EXPANSO_VERSION:-latest}"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
INSTALL_DIR="${EXPANSO_INSTALL_DIR:-}"

if [ -z "$TOKEN" ]; then
  echo "Error: GITHUB_TOKEN (or GH_TOKEN) is required for this private repo." >&2
  exit 1
fi

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

if [ -z "$INSTALL_DIR" ]; then
  if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX}/bin" ]; then
    INSTALL_DIR="${PREFIX}/bin"
  else
    INSTALL_DIR="/usr/local/bin"
  fi
fi

if [ "$VERSION" = "latest" ]; then
  release_api="https://api.github.com/repos/${REPO}/releases/latest"
else
  release_api="https://api.github.com/repos/${REPO}/releases/tags/${VERSION}"
fi

json="$(curl -fsSL -H "Authorization: token ${TOKEN}" "$release_api")"
asset_name="${BINARY_NAME}-android-${arch}"
asset_url="$(printf '%s' "$json" | tr -d '\n' | sed -n "s/.*\"name\":\"${asset_name}\"[^}]*\"browser_download_url\":\"\([^\"]*\)\".*/\1/p")"

if [ -z "$asset_url" ]; then
  echo "Error: release asset not found for ${asset_name} (version: ${VERSION})." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fL -H "Authorization: token ${TOKEN}" -o "$tmp_dir/${BINARY_NAME}" "$asset_url"
chmod +x "$tmp_dir/${BINARY_NAME}"

mkdir -p "$INSTALL_DIR"
mv "$tmp_dir/${BINARY_NAME}" "$INSTALL_DIR/${BINARY_NAME}"

echo "Installed ${BINARY_NAME} to ${INSTALL_DIR}/${BINARY_NAME}"
