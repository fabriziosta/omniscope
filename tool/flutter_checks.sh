#!/usr/bin/env bash
# Shared Flutter gate used by pre-push hooks (and manual runs).
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

usage() {
  echo "usage: $0 analyze|test|all" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
ensure_flutter

# Flutter bundles `.env` as an asset for LLM + exchange credential preload.
# Keep a local copy (gitignored); never commit real keys.
if [[ ! -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env.example" "$ROOT/.env"
  echo "note: created .env from .env.example (fill in API keys locally)" >&2
fi

case "$1" in
  analyze)
    flutter analyze
    ;;
  test)
    flutter test
    ;;
  all)
    flutter analyze
    flutter test
    ;;
  *)
    usage
    ;;
esac
