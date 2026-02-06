# android-build

Custom Android/Termux build + install for `expanso-edge`.

This repo builds Android binaries from `expanso-io/expanso` and hosts them as GitHub Release assets.
If this repo is private, you must provide a GitHub token to download assets.

## Quick Install (Termux)

```bash
curl -fsSL https://raw.githubusercontent.com/aronchick/android-build/main/install.sh | sh
```

If the repo is private, add a token:

```bash
export GITHUB_TOKEN=ghp_... # token with access to this repo
curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
  https://raw.githubusercontent.com/aronchick/android-build/main/install.sh | sh
```

Optional:

```bash
EXPANSO_VERSION=v2026.02.05 sh -c "$(curl -fsSL -H \"Authorization: token $GITHUB_TOKEN\" https://raw.githubusercontent.com/aronchick/android-build/main/install.sh)"
```

## Build Locally

Initialize the source submodule (fork of expanso). This uses SSH (`git@github.com:aronchick/expanso.git`),
so make sure your SSH key has access to the fork:

```bash
git submodule update --init --recursive
```

```bash
./scripts/build-android.sh --ref main --version v2026.02.05
```

Artifacts land in `dist/` with SHA256 checksums.

## Release

```bash
./scripts/release.sh v2026.02.05
```

## Notes

- Uses `GOOS=android` and `CGO_ENABLED=0` to avoid NDK requirements.
- Builds `android/arm64` by default. Set `EXPANSO_BUILD_ARMV7=1` if you want to try armv7 (requires cgo/NDK).
- Applies local patches from `patches/` (currently includes machine ID empty fallback).
 - The `expanso/` submodule points to the fork; add an `upstream` remote inside the submodule if you need to pull new commits from `expanso-io/expanso`.
