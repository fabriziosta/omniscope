#!/usr/bin/env bash
# Bump Flutter patch version in pubspec.yaml and sync lib/core/app_info.dart.
#
# Single version everywhere: MAJOR.MINOR.PATCH+BUILD (BUILD is numeric —
# Android versionCode / iOS). pubspec and AppInfo.version must match exactly.
#
# Major / minor: edit pubspec manually, then re-run this script (or CI) so
# AppInfo picks up the new full version string.
#
# Usage:
#   tool/bump_patch_version.sh              # 1.2.3+9 → 1.2.4+10 (pubspec + AppInfo)
#   tool/bump_patch_version.sh --check      # print pubspec version; exit 0
#   tool/bump_patch_version.sh --dry-run    # show next version; do not write
#   tool/bump_patch_version.sh --verify     # fail if AppInfo ≠ pubspec (full string)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBSPEC="$ROOT/pubspec.yaml"
APP_INFO="$ROOT/lib/core/app_info.dart"

mode="bump"
case "${1:-}" in
  --check) mode="check" ;;
  --dry-run) mode="dry-run" ;;
  --verify) mode="verify" ;;
  "" ) ;;
  -h|--help)
    sed -n '2,15p' "$0"
    exit 0
    ;;
  *)
    echo "usage: $0 [--check|--dry-run|--verify]" >&2
    exit 2
    ;;
esac

if [[ ! -f "$PUBSPEC" ]]; then
  echo "error: missing $PUBSPEC" >&2
  exit 1
fi

line="$(grep -E '^version:' "$PUBSPEC" | head -n1 || true)"
if [[ -z "$line" ]]; then
  echo "error: no version: line in pubspec.yaml" >&2
  exit 1
fi

# Expect: version: MAJOR.MINOR.PATCH+BUILD  (build optional; must be numeric for stores)
raw="${line#version:}"
raw="$(echo "$raw" | tr -d '[:space:]')"
semver="${raw%%+*}"
build="${raw##*+}"
if [[ "$raw" == "$semver" ]]; then
  build="0"
fi

IFS=. read -r major minor patch <<<"$semver"
if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
  echo "error: could not parse version '$raw' (want X.Y.Z[+N])" >&2
  exit 1
fi
if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ && "$build" =~ ^[0-9]+$ ]]; then
  echo "error: non-numeric version parts in '$raw' (build after + must be an integer)" >&2
  exit 1
fi

app_info_version() {
  if [[ ! -f "$APP_INFO" ]]; then
    echo ""
    return 0
  fi
  sed -nE "s/^[[:space:]]*static const version = '([^']+)';/\1/p" "$APP_INFO" | head -n1
}

case "$mode" in
  check)
    echo "$raw"
    exit 0
    ;;
  verify)
    info_ver="$(app_info_version)"
    if [[ -z "$info_ver" ]]; then
      echo "error: missing or unreadable AppInfo.version in $APP_INFO" >&2
      exit 1
    fi
    if [[ "$info_ver" != "$raw" ]]; then
      echo "error: version drift — pubspec $raw vs AppInfo $info_ver" >&2
      exit 1
    fi
    echo "ok: $raw"
    exit 0
    ;;
esac

next_patch=$((patch + 1))
next_build=$((build + 1))
next_full="${major}.${minor}.${next_patch}+${next_build}"

case "$mode" in
  dry-run)
    echo "pubspec / AppInfo: $raw -> $next_full"
    exit 0
    ;;
esac

tmp="$(mktemp)"
# shellcheck disable=SC2064
trap 'rm -f "$tmp"' EXIT

awk -v ver="$next_full" '
  BEGIN { done = 0 }
  /^version:/ && !done {
    print "version: " ver
    done = 1
    next
  }
  { print }
' "$PUBSPEC" >"$tmp"
mv "$tmp" "$PUBSPEC"
trap - EXIT

if [[ -f "$APP_INFO" ]]; then
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap 'rm -f "$tmp"' EXIT
  # Replace: static const version = '...';
  sed -E "s/^([[:space:]]*static const version = ')[^']+(';)/\\1${next_full}\\2/" \
    "$APP_INFO" >"$tmp"
  mv "$tmp" "$APP_INFO"
  trap - EXIT
else
  echo "warning: missing $APP_INFO (pubspec updated only)" >&2
fi

echo "bumped version: $raw -> $next_full"
