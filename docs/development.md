# Development setup

Agent handbook: [`AGENTS.md`](../AGENTS.md). Product overview: [`README.md`](../README.md).

## Flutter

This machine can use a local SDK at `~/flutter` (stable). Add it to your PATH:

```bash
export PATH="$HOME/flutter/bin:$PATH"
flutter doctor
```

## Linux desktop

Install build tools (Fedora example):

```bash
sudo dnf install -y clang cmake ninja-build gtk3-devel pkgconf-pkg-config \
  xz-libs libstdc++-devel mesa-libEGL-devel
```

Then `flutter doctor` until the Linux toolchain is green.

Keep this Fedora package list aligned with the builder stage in [`Containerfile`](../Containerfile) and CI `apt-get` Linux deps. See also [`container.md`](container.md).

## Android

Install Android Studio / SDK, accept licenses, and connect a device or emulator.  
The `android/` tree is generated; Internet permission is already declared for market requests.

## Run

Prefer the root [`Makefile`](../Makefile) (`make help` lists targets). On Windows, use Git Bash or WSL (same as `tool/*.sh`).

```bash
cd /path/to/omniscope
make get
make run                 # DEVICE=linux by default
make run DEVICE=chrome   # or: windows / android / ios / macos
```

Analyze / test:

```bash
make check               # analyze + test (same as pre-push)
# equivalents: make analyze | make test
# or: tool/flutter_checks.sh all
```

Underlying Flutter commands still work: `flutter pub get`, `flutter run -d linux`, `flutter analyze`, `flutter test`.

Copy [`.env.example`](../.env.example) → `.env` for local LLM / exchange keys. **Never commit `.env` or real secrets.**

## Pre-commit / pre-push hooks

This repo uses [`pre-commit`](https://pre-commit.com/) to block bad commits and pushes:

| When | Checks |
|------|--------|
| **commit** | merge conflicts, private keys, [gitleaks](https://github.com/gitleaks/gitleaks) secret scan, basic file hygiene |
| **push** | gitleaks again, `flutter analyze`, `flutter test` |

Install once after clone (needs `pre-commit` on your PATH):

```bash
make hooks
make hooks-run           # optional: verify the whole tree
# or: pre-commit install --hook-type pre-commit --hook-type pre-push
#     pre-commit run --all-files
```

Hooks look for Flutter via `PATH`, `FLUTTER_ROOT`, or `~/flutter/bin`.

Config: [`.pre-commit-config.yaml`](../.pre-commit-config.yaml), [`.gitleaks.toml`](../.gitleaks.toml).
