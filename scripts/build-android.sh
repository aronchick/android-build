#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$ROOT_DIR/patches"

REF="${EXPANSO_REF:-main}"
VERSION="${EXPANSO_VERSION:-}"
OUT_DIR="${EXPANSO_OUT_DIR:-$ROOT_DIR/dist}"
ANDROID_API="${ANDROID_API:-21}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
ANDROID_NDK_HOST_TAG="${ANDROID_NDK_HOST_TAG:-}"

usage() {
  cat <<USAGE
Usage: $0 [--ref REF] [--version VERSION] [--out-dir DIR]

Environment overrides:
  EXPANSO_REF     Git ref (default: $REF)
  EXPANSO_VERSION Version string (default: dev-android-<shortsha>)
  EXPANSO_OUT_DIR Output directory (default: $OUT_DIR)
  ANDROID_API     Android API level (default: $ANDROID_API)
  ANDROID_NDK_HOME Android NDK root (required; can also use ANDROID_NDK_ROOT)
  ANDROID_NDK_HOST_TAG Override NDK host tag (e.g., darwin-x86_64)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      REF="$2"; shift 2 ;;
    --version)
      VERSION="$2"; shift 2 ;;
    --out-dir)
      OUT_DIR="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage; exit 1 ;;
  esac
done

WORK_DIR="$(mktemp -d)"
cleanup() {
  chmod -R u+w "$WORK_DIR" 2>/dev/null || true
  rm -rf "$WORK_DIR" || true
}
trap cleanup EXIT

if [[ -n "${GOMODCACHE:-}" ]]; then
  MODCACHE_DIR="$GOMODCACHE"
elif [[ -n "${EXPANSO_GOMODCACHE:-}" ]]; then
  MODCACHE_DIR="$EXPANSO_GOMODCACHE"
else
  MODCACHE_DIR="$WORK_DIR/gomodcache"
fi
export GOMODCACHE="$MODCACHE_DIR"

SRC_DIR="$ROOT_DIR/expanso"

ensure_submodule() {
  if [[ ! -f "$ROOT_DIR/.gitmodules" ]]; then
    echo "Missing .gitmodules. Initialize the expanso submodule first." >&2
    exit 1
  fi
  if [[ ! -d "$SRC_DIR/.git" ]]; then
    echo "Expanso submodule not found. Initializing..." >&2
    git submodule update --init --recursive expanso
  fi
}

resolve_toolchain_bin() {
  local ndk_home="$1"
  local host_os
  local host_arch
  local host_tag

  if [[ -n "$ANDROID_NDK_HOST_TAG" ]]; then
    echo "$ndk_home/toolchains/llvm/prebuilt/$ANDROID_NDK_HOST_TAG/bin"
    return
  fi

  host_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  host_arch="$(uname -m)"

  case "${host_os}-${host_arch}" in
    darwin-arm64) host_tag="darwin-arm64" ;;
    darwin-*) host_tag="darwin-x86_64" ;;
    linux-aarch64|linux-arm64) host_tag="linux-aarch64" ;;
    linux-*) host_tag="linux-x86_64" ;;
    *)
      echo "Unsupported host for Android NDK: ${host_os}-${host_arch}. Set ANDROID_NDK_HOST_TAG explicitly." >&2
      exit 1
      ;;
  esac

  echo "$ndk_home/toolchains/llvm/prebuilt/$host_tag/bin"
}

ensure_submodule
cd "$SRC_DIR"

if [[ -n "$REF" ]]; then
  git fetch --all --prune >/dev/null 2>&1 || true
  if git rev-parse --verify "$REF" >/dev/null 2>&1; then
    git checkout -q "$REF"
  else
    git checkout -q "origin/$REF" || git checkout -q "$REF"
  fi
fi

COMMIT="$(git rev-parse --short=12 HEAD)"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BUILD_USER="${USER:-android-build}"

if [[ -z "$VERSION" ]]; then
  VERSION="dev-android-${COMMIT}"
fi

if [[ -z "$ANDROID_NDK_HOME" ]]; then
  echo "ANDROID_NDK_HOME is required. Set ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) to your NDK path." >&2
  exit 1
fi
TOOLCHAIN_BIN="$(resolve_toolchain_bin "$ANDROID_NDK_HOME")"
if [[ ! -d "$TOOLCHAIN_BIN" ]]; then
  echo "Android NDK toolchain not found at $TOOLCHAIN_BIN. Check ANDROID_NDK_HOME or set ANDROID_NDK_HOST_TAG." >&2
  exit 1
fi

LDFLAGS=(
  "-s" "-w"
  "-X" "github.com/expanso-io/expanso/shared/version.Version=${VERSION}"
  "-X" "github.com/expanso-io/expanso/shared/version.Commit=${COMMIT}"
  "-X" "github.com/expanso-io/expanso/shared/version.BuildDate=${BUILD_DATE}"
  "-X" "github.com/expanso-io/expanso/shared/version.BuildUser=${BUILD_USER}"
)

# Apply patches if any exist
if [[ -d "$PATCH_DIR" ]]; then
  shopt -s nullglob
  for patch in "$PATCH_DIR"/*.patch; do
    if git apply --reverse --check "$patch" >/dev/null 2>&1; then
      echo "Skipping already-applied patch $(basename "$patch")"
      continue
    fi
    echo "Applying patch $(basename "$patch")"
    if ! git apply "$patch"; then
      echo "Patch failed, attempting 3-way apply..." >&2
      git apply --3way "$patch"
    fi
  done
fi

suppress_gosnowflake_android_warning() {
  local mod_dir
  local file
  local tmp

  if ! go mod download github.com/snowflakedb/gosnowflake >/dev/null 2>&1; then
    return 0
  fi

  mod_dir="$(go list -m -f '{{.Dir}}' github.com/snowflakedb/gosnowflake 2>/dev/null || true)"
  if [[ -z "$mod_dir" ]]; then
    return 0
  fi

  file="$mod_dir/secure_storage_manager.go"
  if [[ ! -f "$file" ]]; then
    return 0
  fi

  chmod -R u+w "$mod_dir" 2>/dev/null || true

  if grep -q 'runtime.GOOS == "android"' "$file"; then
    return 0
  fi

  if ! grep -q 'does not support credentials cache' "$file"; then
    return 0
  fi

  tmp="$(mktemp)"
  awk '
    /logger\.Warnf\("OS %v does not support credentials cache", runtime\.GOOS\)/ {
      print "\t\tif runtime.GOOS == \"android\" {"
      print "\t\t\tlogger.Debugf(\"OS %v does not support credentials cache\", runtime.GOOS)"
      print "\t\t} else {"
      print "\t\t\tlogger.Warnf(\"OS %v does not support credentials cache\", runtime.GOOS)"
      print "\t\t}"
      next
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  echo "Patched gosnowflake to silence Android credentials cache warning."
}

suppress_gosnowflake_android_warning

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
VERSION_DIR="$OUT_DIR/$VERSION"
mkdir -p "$VERSION_DIR"

build_target() {
  local goarch="$1"
  local goarm="$2"
  local suffix="$3"
  local triple="$4"
  local output="$VERSION_DIR/expanso-edge-android-${suffix}"
  local cc="${TOOLCHAIN_BIN}/${triple}${ANDROID_API}-clang"
  local cxx="${TOOLCHAIN_BIN}/${triple}${ANDROID_API}-clang++"

  if [[ ! -x "$cc" ]]; then
    echo "Android NDK compiler not found: $cc" >&2
    exit 1
  fi

  echo "Building android/${goarch}${goarm:+ (GOARM=$goarm)} -> ${output}"
  env \
    GOOS=android \
    GOARCH="$goarch" \
    ${goarm:+GOARM=$goarm} \
    CGO_ENABLED=1 \
    CC="$cc" \
    CXX="$cxx" \
    go build -trimpath -ldflags "${LDFLAGS[*]}" -o "$output" ./edge/cmd/expanso-edge

  file "$output" || true
}

build_target arm64 "" arm64 "aarch64-linux-android"

(
  cd "$VERSION_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum expanso-edge-android-* > SHA256SUMS.txt
  else
    shasum -a 256 expanso-edge-android-* > SHA256SUMS.txt
  fi
)

echo "Artifacts: $VERSION_DIR"
ls -la "$VERSION_DIR"
