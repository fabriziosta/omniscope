#!/usr/bin/env bash
# Bump Flutter patch version in pubspec.yaml and sync lib/core/app_info.dart.
#
# pubspec:  MAJOR.MINOR.PATCH+BUILD   (BUILD stays numeric — Android versionCode)
# AppInfo:  MAJOR.MINOR.PATCH+SHORTSHA  (About display; SHORTSHA = 7-char commit)
#
# Major / minor: edit pubspec manually, then re-run this script (or CI) so AppInfo
# picks up the new X.Y.Z + current HEAD short SHA.
#
# Usage:
#   tool/bump_patch_version.sh              # 1.2.3+9 → pubspec 1.2.4+10, AppInfo 1.2.4+<sha>
#   tool/bump_patch_version.sh --check      # print pubspec version; exit 0
#   tool/bump_patch_version.sh --dry-run    # show next versions; do not write
#   tool/bump_patch_version.sh --verify     # fail if AppInfo X.Y.Z ≠ pubspec X.Y.Z
#
# Env:
#   OMNISCOPE_VERSION_SHA  optional full/short commit; default: git rev-parse HEAD
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBSPEC="$ROOT/pubspec.yaml"
APP_INFO="$ROOT/lib/core/app_info.dart"
SHORT_LEN=7

mode="bump"
case "${1:-}" in
  --check) mode="check" ;;
  --dry-run) mode="dry-run" ;;
  --verify) mode="verify" ;;
  "" ) ;;
  -h|--help)
    sed -n '2,18p' "$0"
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

short_sha() {
  local full="${OMNISCOPE_VERSION_SHA:-}"
  if [[ -z "$full" ]]; then
    if ! full="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"; then
      echo "error: cannot resolve commit SHA (set OMNISCOPE_VERSION_SHA or run inside a git repo)" >&2
      exit 1
    fi
  fi
  # Normalize to lowercase hex, then take short prefix.
  full="$(echo "$full" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if ! [[ "$full" =~ ^[0-9a-f]+$ ]]; then
    echo "error: invalid commit SHA '$full'" >&2
    exit 1
  fi
  echo "${full:0:$SHORT_LEN}"
}

app_info_semver() {
  if [[ ! -f "$APP_INFO" ]]; then
    echo ""
    return 0
  fi
  local v
  v="$(sed -nE "s/^[[:space:]]*static const version = '([^']+)';/\1/p" "$APP_INFO" | head -n1)"
  # Strip +suffix (commit) for comparison with pubspec X.Y.Z
  echo "${v%%+*}"
}

case "$mode" in
  check)
    echo "$raw"
    exit 0
    ;;
  verify)
    info_semver="$(app_info_semver)"
    if [[ -z "$info_semver" ]]; then
      echo "error: missing or unreadable AppInfo.version in $APP_INFO" >&2
      exit 1
    fi
    if [[ "$info_semver" != "$semver" ]]; then
      echo "error: version drift — pubspec $semver vs AppInfo $info_semver" >&2
      exit 1
    fi
    echo "ok: $semver (pubspec $raw)"
    exit 0
    ;;
esac

sha="$(short_sha)"
next_patch=$((patch + 1))
next_build=$((build + 1))
next_semver="${major}.${minor}.${next_patch}"
next_full="${next_semver}+${next_build}"
next_display="${next_semver}+${sha}"

case "$mode" in
  dry-run)
    echo "pubspec: $raw -> $next_full"
    echo "AppInfo:  -> $next_display"
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
  sed -E "s/^([[:space:]]*static const version = ')[^']+(';)/\\1${next_display}\\2/" \
    "$APP_INFO" >"$tmp"
  mv "$tmp" "$APP_INFO"
  trap - EXIT
else
  echo "warning: missing $APP_INFO (pubspec updated only)" >&2
fi

echo "bumped version: pubspec $raw -> $next_full ; AppInfo $next_display"
