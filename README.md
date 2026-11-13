# Omniscope

Omniscope is a Flutter app for **learning investing and managing personal finance**.  
v0 is a no-accounts proof of concept: browse markets simply, inspect a price chart, and practice with a local paper portfolio.

Targets: **Linux**, **Windows**, **Android**, **Apple** (**iOS** / **macOS**), and **Web**. Every change must stay compatible across all of them.

![Omniscope Markets — Favorites, Indices, ETFs, and Stocks](docs/screenshots/markets.png)

## Features (v0)

- **Markets** — Favorites (one shared list), Indices, ETFs, Stocks, and enabled crypto exchanges (Spot pairs); star any symbol to save favorites
- **Asset detail** — price, day change, short curated overview (default symbols), 1M / 3M / 1Y history chart, paper buy/sell, plus external research links (provider page, Wikipedia when mapped, Google Finance, TradingView) opened in the system browser
- **Portfolio** — practice paper trading (default $10,000 starting cash, configurable in Settings, local holdings, P&L, reset) plus **Live** balance subgroups when API credentials are configured (Crypto.com, Alpaca, …)
- **Agents** — connect AI helpers with your own API key and model, then chat on-device (freeform + symbol Run); trading roles can Confirm into Practice or a live exchange (optional Connect default portfolio). Keys and chat threads stay local. Python CrewAI/LangGraph CLIs remain available under `agents/`
- **Settings** — sidebar section navigator (one pane at a time): appearance, data sources & credentials, practice starting cash, connections (LLM keys + agents/exchanges), data & privacy (path / import / export / clear local data), and About (tagline *My trusted learning and trading buddy* + educational disclaimer)
- **No accounts** — everything stays on device in one `omniscope.json` config (Web: browser storage + import/export)

## Market data

Equities / indices use **Yahoo Finance** chart endpoints (keyless, unofficial). Crypto uses a swappable [`CryptoExchangeClient`](lib/data/crypto/crypto_exchange_client.dart) registry; **Crypto.com Exchange** public REST is registered first (`get-tickers` / `get-candlestick` at `https://api.crypto.com/exchange/v1/`). Equity brokers (e.g. **Alpaca** paper/live) register via [`VenueCatalog`](lib/data/venues/venue_catalog.dart) for Live portfolio + agent orders — not as Markets quote sources. Optional venue API credentials can be set in [`.env`](.env.example) or under **Settings → Data sources → Credentials** (generic cards driven by the catalog; dual sync to config + `.env` when possible). Key+secret unlock Live balances and Confirm/Autopilot for that venue only. Market data is reached through [`RoutingMarketDataClient`](lib/data/market/routing_market_data_client.dart). **Settings → Data sources** enables/disables equities providers, crypto venues, and brokers (new sources default to on). Appearance prefs live under **Settings → Appearance**. Secrets and other customizations share one **`omniscope.json`**.

- Data may be delayed; endpoints can change or rate-limit without notice.
- **Web:** Yahoo’s chart host does not send CORS headers, so Chrome blocks direct `query1.finance.yahoo.com` calls. Equities requests on Web go through a public GET proxy (`https://proxy.cors.dev/…`) inside [`YahooMarketDataClient`](lib/data/market/yahoo_market_data_client.dart); native targets call Yahoo directly. Crypto.com public REST already allows browser origins. Private broker APIs may be blocked by CORS on Web — prefer native desktop/mobile for live orders.
- For **educational / personal** use in this POC only. Check Yahoo’s, Crypto.com’s, and Alpaca’s terms before redistribution or commercial use.
- To add another equities provider: implement `MarketDataClient` and register it in the equities registry in [`lib/main.dart`](lib/main.dart).
- To add another crypto exchange or broker: implement the client under `lib/data/crypto/<id>/` or `lib/data/brokers/<id>/`, then append one line in [`VenueCatalog.build`](lib/data/venues/venue_catalog.dart) (see [`AGENTS.md`](AGENTS.md)).

## Prerequisites

### Flutter

This machine can use a local SDK at `~/flutter` (stable). Add it to your PATH:

```bash
export PATH="$HOME/flutter/bin:$PATH"
flutter doctor
```

### Linux desktop

Install build tools (Fedora example):

```bash
sudo dnf install -y clang cmake ninja-build gtk3-devel pkgconf-pkg-config \
  xz-libs libstdc++-devel mesa-libEGL-devel
```

Then `flutter doctor` until the Linux toolchain is green.

### Podman (slim Linux runtime image)

A multi-stage [`Containerfile`](Containerfile) builds the Flutter Linux release bundle in a throwaway stage and ships only **`omniscope:runtime`** (GTK/EGL runtime libs + the bundle). No Flutter SDK in the final image. Linux/x64 GUI only — forward the host display.

```bash
make container-build     # podman build -t omniscope:runtime
make container-run       # needs DISPLAY; mounts /tmp/.X11-unix
```

On each `v*` tag (and via **Actions → Container → Run workflow**), CI builds the same [`Containerfile`](Containerfile) and pushes to GitHub Container Registry:

```bash
# After a release tag (example)
podman pull ghcr.io/fabriziosta/omniscope:latest
# or: podman pull ghcr.io/fabriziosta/omniscope:1.0.1
podman run --rm -it -e DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
  ghcr.io/fabriziosta/omniscope:latest
```

Packages start **private** on first publish; set visibility under the repo’s **Packages** settings if you want public pulls. Auth for private images: [GitHub Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Do not bake secrets into the image (builder copies `.env.example` for the asset requirement). When Linux packages or Flutter install flags change, update the Containerfile in the same change (see [`AGENTS.md`](AGENTS.md)).

### Android

Install Android Studio / SDK, accept licenses, and connect a device or emulator.  
The `android/` tree is generated; Internet permission is already declared for market requests.

## Run

Prefer the root [`Makefile`](Makefile) (`make help` lists targets). On Windows, use Git Bash or WSL (same as `tool/*.sh`).

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

### Release builds

Flutter does **not** cross-compile every desktop/iOS binary from one machine. Prefer per-platform targets, or `make build` for whatever the current host can produce:

```bash
make build               # Linux → linux+apk+web; macOS → macos+ios+apk+web; Windows → windows+apk+web
make build-linux         # flutter build linux --release
make build-windows       # Windows host
make build-macos         # macOS host
make build-ios           # macOS; unsigned (--no-codesign)
make build-apk           # Android APK (needs Android SDK)
make build-appbundle     # Android AAB for Play Store
make build-web
```

| Artifact | Target | Host needed |
|----------|--------|-------------|
| Linux desktop | `build-linux` | Linux + GTK toolchain |
| Windows desktop | `build-windows` | Windows |
| macOS desktop | `build-macos` | macOS + Xcode |
| iOS (unsigned `.app`) | `build-ios` | macOS + Xcode |
| Android APK / AAB | `build-apk` / `build-appbundle` | any + Android SDK |
| Web | `build-web` | any |

Artifacts land under `build/` (e.g. Linux `build/linux/x64/release/bundle/`, APK `build/app/outputs/flutter-apk/app-release.apk`, Web `build/web/`).

Underlying Flutter commands still work: `flutter pub get`, `flutter run -d linux`, `flutter analyze`, `flutter test`.

### CI (GitHub Actions)

Linux runners only (`.github/workflows/`):

| Workflow | When | What |
|----------|------|------|
| **CI** ([`ci.yml`](.github/workflows/ci.yml)) | PR + push to `main` | Gitleaks + `tool/flutter_checks.sh all` (analyze + test); `flutter build web` and `flutter build linux` as compile smoke (no artifact upload) |
| **Release** ([`release.yml`](.github/workflows/release.yml)) | Push tag `v*` only | Build web + Linux + APK and attach them to a GitHub Release |
| **Container** ([`container.yml`](.github/workflows/container.yml)) | Push tag `v*` + manual | Build [`Containerfile`](Containerfile) and push `ghcr.io/<owner>/omniscope` (`:latest`, semver tags) |
| **Bump patch** ([`bump-patch-version.yml`](.github/workflows/bump-patch-version.yml)) | Push to `main` | Auto-increments patch in `pubspec.yaml` / AppInfo (does **not** create tags) |

Optional: enable branch protection required checks for CI jobs `check`, `build-web`, and `build-linux`.

**Cutting a release** (after merge + auto patch bump on `main`):

```bash
# Tag should match pubspec / AppInfo MAJOR.MINOR.PATCH (e.g. 1.0.1 → v1.0.1)
git checkout main && git pull
VERSION="$(tool/bump_patch_version.sh --check | cut -d+ -f1)"
git tag "v${VERSION}"
git push origin "v${VERSION}"
```

Or tag explicitly: `git tag v1.0.1 && git push origin v1.0.1`. Release assets: `omniscope-web.zip`, `omniscope-linux.tar.gz`, `omniscope.apk`. The same tag also triggers the Container workflow → `ghcr.io/fabriziosta/omniscope:<version>`.

### Pre-commit / pre-push hooks

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

## Architecture

```text
lib/
  main.dart                 # DI: router + crypto registry + portfolio + agents
  app.dart                  # ShadApp theme shell
  core/                     # formatting + brand colors
  data/market/              # MarketDataClient, Yahoo, routing
  data/crypto/              # CryptoExchangeClient + Crypto.com adapter
  data/brokers/             # Alpaca (+ future equity brokers)
  data/venues/              # VenueCatalog, shared live portfolio models
  data/portfolio/           # local paper portfolio (shared_preferences)
  data/agents/              # connections, chat threads, LlmChatClient, catalog
  features/markets|crypto|asset_detail|portfolio|agents|shell/
  widgets/                  # chart + brand mark
agents/                     # Python CrewAI + LangGraph CLI agents
assets/brand/               # master app icon (launchers + Android/iOS/Web splash)
assets/agents/              # llm_models.json (selectable models)
```

UI uses **[`shadcn_ui`](https://pub.dev/packages/shadcn_ui)** only (`ShadApp`). Charts are drawn with `CustomPaint` so no second UI kit is required.

Non-UI packages: `http`, `shared_preferences`, `intl`, `provider`.

### App icon and splash

Master art lives in [`assets/brand/app_icon.png`](assets/brand/app_icon.png) (adaptive foreground: [`app_icon_foreground.png`](assets/brand/app_icon_foreground.png)). After editing the masters, regenerate launchers and splash:

```bash
make icons
# or: tool/regen_icons.sh
```

That runs:

- [`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons) — Android / iOS / macOS / Web / Windows icons (config in [`pubspec.yaml`](pubspec.yaml))
- Linux window icons under [`linux/runner/resources/`](linux/runner/resources/)
- [`flutter_native_splash`](https://pub.dev/packages/flutter_native_splash) — branded Teal splash for **Android, iOS, and Web** (including Android 12+). Desktop (Linux / Windows / macOS) has no native OS splash; window/launcher icons still come from the same masters.

[`lib/main.dart`](lib/main.dart) keeps the native splash visible with `FlutterNativeSplash.preserve` until config/repos finish loading, then calls `remove` before `runApp`.

Selectable LLM models live in [`assets/agents/llm_models.json`](assets/agents/llm_models.json) so the list can be refreshed later without changing Flutter UI code. Optional local secrets: copy [`.env.example`](.env.example) → `.env` (gitignored) for LLM provider keys and exchange credentials (e.g. Crypto.com). The UI suggests those values and saves edits back to `.env` when running from a desktop checkout (prefs cover every platform). Agent role → framework rules and layout are in [`AGENTS.md`](AGENTS.md).

## Docs for agents

See [`AGENTS.md`](AGENTS.md) for conventions when extending Omniscope (UI rules, provider swaps, portfolio contract, AI agent roles).

### AI coding assistants

Shared guidance for Cursor, Codex, and Claude Code lives in [`AGENTS.md`](AGENTS.md) plus vendored Flutter + Dart [Agent Skills](https://docs.flutter.dev/ai/tools) under [`.agents/skills/`](.agents/skills/) (separate from the in-app Agents tab and the Python [`agents/`](agents/) CLIs). Do not add parallel `.claude/` / `.codex/` instruction mirrors. Cursor-only product rules live in [`.cursor/rules/`](.cursor/rules/); Dart MCP is in [`.cursor/mcp.json`](.cursor/mcp.json). Refresh skills with `make agent-skills`. Details: [`AGENTS.md`](AGENTS.md) **Coding-assistant tooling**.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).
Security reports: [SECURITY.md](SECURITY.md).

## License / disclaimer

Released under the [MIT License](LICENSE).

**Use at your own risk.** Omniscope is an educational proof of concept, not a brokerage or financial-advice product. Nothing in the app (quotes, charts, paper trades, agent chat, or CLI pipelines) is investment, legal, or tax advice. You are solely responsible for any decisions you make. Authors and contributors accept no liability for losses, damages, or data issues arising from use of this software, market data, or third-party APIs.

Not financial advice. Paper trading is simulated. Market data ownership remains with the originating exchanges and Yahoo Finance. API keys and secrets stay on your device — protect them accordingly.
