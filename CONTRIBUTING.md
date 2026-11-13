# Contributing to Omniscope

Thanks for helping improve Omniscope. This guide covers how to set up a
development environment and open a pull request.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## What this project is

Omniscope is a Flutter app for **learning investing and personal finance**.
v0 has **no user accounts**. Supported targets: **Linux**, **Windows**,
**Android**, **iOS**, **macOS**, and **Web**. Every change must stay compatible
across all of them.

Architecture and product rules live in [AGENTS.md](AGENTS.md) — read that
before larger changes (UI kit, market data, agents, portfolio).

## Prerequisites

- Flutter SDK (stable; see [README](README.md))
- For desktop/mobile targets: the matching toolchain (`flutter doctor`)
- Optional: `pre-commit` for local hooks
- Optional (Python agents CLI): Python 3 + `make agents-setup`

## Setup

```bash
git clone https://github.com/fabriziosta/omniscope.git
cd omniscope
make get                 # flutter pub get + ensure .env from .env.example
make hooks               # install pre-commit + pre-push (recommended)
make check               # analyze + test
make run                 # DEVICE=linux by default
# make run DEVICE=chrome
```

Copy [`.env.example`](.env.example) → `.env` for local LLM / exchange keys.
**Never commit `.env` or real secrets.**

## Development norms

- **Cross-platform** — no Linux-only (or other single-OS) behavior without a
  working path on every target. Prefer portable Flutter APIs; Web must keep
  compiling.
- **UI** — `shadcn_ui` only (`ShadApp`). Mobile-first, then responsive for wide
  screens. Brand colors from [`lib/core/brand_colors.dart`](lib/core/brand_colors.dart).
- **Market data** — UI and portfolio code use `MarketDataClient` only; never
  call Yahoo / exchange URLs from widgets.
- **Screens** — keep them thin; feature folders own their screens; shared
  widgets under `lib/widgets/`.

## Before you open a PR

1. Branch from `main` with a short, descriptive name.
2. Run `make check` (same as the pre-push hook: analyze + test).
3. Keep the diff focused; update README / AGENTS.md when behavior or
   architecture changes.
4. Do not commit secrets, large binaries, or generated `build/` output.

## Pull requests

- Describe **why** the change exists and what you tested (which devices /
  platforms if UI-related).
- Link related issues when applicable.
- Prefer small PRs over large mixed refactors + features.

Use the [pull request template](.github/PULL_REQUEST_TEMPLATE.md).

## Issues

- Bug reports and feature ideas: use the GitHub issue forms.
- Security issues: see [SECURITY.md](SECURITY.md) — do **not** file public
  issues for vulnerabilities.

## License

Contributions are licensed under the [MIT License](LICENSE).
