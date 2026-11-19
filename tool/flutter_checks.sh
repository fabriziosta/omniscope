#!/usr/bin/env bash
# Shared Flutter gate used by pre-push hooks (and manual runs).
# `all` matches CI check + Linux compile smoke: version verify, analyze,
# offline tests, then flutter build linux --release.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ensure_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    return 0
  fi
  if [[ -n "${FLUTTER_ROOT:-}" && -x "${FLUTTER_ROOT}/bin/flutter" ]]; then
    export PATH="${FLUTTER_ROOT}/bin:${PATH}"
    return 0
  fi
  if [[ -x "${HOME}/flutter/bin/flutter" ]]; then
    export PATH="${HOME}/flutter/bin:${PATH}"
    return 0
  fi
  echo "error: flutter not found (set PATH, FLUTTER_ROOT, or install under ~/flutter)" >&2
  exit 1
}

require_linux_host() {
  local os
  os="$(uname -s 2>/dev/null || true)"
  if [[ "$os" != "Linux" ]]; then
    echo "error: Linux release compile is mandatory for make check / pre-push." >&2
    echo "  Host OS is '${os:-unknown}'. Use a Linux machine (or WSL with the" >&2
    echo "  Flutter Linux desktop toolchain + GTK deps). See docs/development.md." >&2
    exit 1
  fi
}

build_linux_release() {
  require_linux_host
  flutter build linux --release
}

usage() {
  echo "usage: $0 analyze|test|build-linux|all" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
ensure_flutter

case "$1" in
  analyze)
    flutter analyze
    ;;
  test)
    # Exclude live venue canary (needs network; run via `make venue-canary`).
    flutter test --exclude-tags live_canary
    ;;
  build-linux)
    build_linux_release
    ;;
  all)
    "$ROOT/tool/bump_patch_version.sh" --verify
    flutter analyze
    flutter test --exclude-tags live_canary
    build_linux_release
    ;;
  *)
    usage
    ;;
esac
