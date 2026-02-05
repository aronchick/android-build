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

if [ "$VERSION" = "latest" ]; then
  release_api="https://api.github.com/repos/${REPO}/releases/latest"
else
  release_api="https://api.github.com/repos/${REPO}/releases/tags/${VERSION}"
fi

if [ -n "$TOKEN" ]; then
  json="$(curl -fsSL -H "Authorization: token ${TOKEN}" "$release_api")"
else
  json="$(curl -fsSL "$release_api")"
fi
asset_name="${BINARY_NAME}-android-${arch}"
# Best-effort JSON parse without extra tools (line-based on GitHub's pretty JSON).
asset_url="$(printf '%s\n' "$json" | awk -v name="$asset_name" '
  $0 ~ "\"name\"[[:space:]]*:[[:space:]]*\""name"\"" { found=1 }
  found && $0 ~ "\"browser_download_url\"[[:space:]]*:" {
    gsub(/.*\"browser_download_url\"[[:space:]]*:[[:space:]]*\"/, "");
    gsub(/\".*/, "");
    print;
    exit
  }
')"

if [ -z "$asset_url" ]; then
  message="$(printf '%s\n' "$json" | awk -F'\"' '/\"message\"[[:space:]]*:/ { print $4; exit }')"
  if [ -n "$message" ]; then
    echo "GitHub API error: $message" >&2
  fi
  echo "Error: release asset not found for ${asset_name} (version: ${VERSION})." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if [ -n "$TOKEN" ]; then
  curl -fL -H "Authorization: token ${TOKEN}" -o "$tmp_dir/${BINARY_NAME}" "$asset_url"
else
  curl -fL -o "$tmp_dir/${BINARY_NAME}" "$asset_url"
fi
chmod +x "$tmp_dir/${BINARY_NAME}"

mkdir -p "$INSTALL_DIR"
mv "$tmp_dir/${BINARY_NAME}" "$INSTALL_DIR/${BINARY_NAME}"

echo "Installed ${BINARY_NAME} to ${INSTALL_DIR}/${BINARY_NAME}"
