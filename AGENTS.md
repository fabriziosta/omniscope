# AGENTS.md — Omniscope

Guidance for coding agents and humans extending this repo.

## Purpose

Omniscope helps people **learn investing and personal finance** with a simple GUI.  
v0 is a Flutter POC with **no user accounts**. Supported targets: **Linux**, **Windows**, **Android**, **Apple** (**iOS** and **macOS**), and **Web**.

### Cross-platform (required)

**Every change must stay compatible** with Linux, Windows, Android, iOS, macOS, and Web. Do not ship OS-specific behavior, packages, paths, or native glue that break or omit any of those targets. See `.cursor/rules/cross-platform.mdc`.

### Non-goals (v0)

- Real brokerage, KYC, or cloud sync
- Auth / multi-user accounts
- News, fundamentals, alerts, ticker search UI

## Stack

| Layer | Choice |
|-------|--------|
| UI kit | **`shadcn_ui` only** — root app is `ShadApp` |
| Charts | In-repo `CustomPaint` ([`lib/widgets/price_line_chart.dart`](lib/widgets/price_line_chart.dart)) — do **not** add `fl_chart` or other chart UI packages unless product explicitly changes this rule |
| State | `provider` |
| HTTP | `http` |
| Local persistence | `omniscope.json` via [`UserConfigStore`](lib/data/settings/user_config_store.dart) (`path_provider`; Web uses a prefs blob) |
| Market data | `MarketDataClient` → `RoutingMarketDataClient` (Yahoo equities + crypto registry) |
| Crypto exchanges | `CryptoExchangeClient` + `CryptoExchangeRegistry` (Crypto.com first) |

Do not add Material-first screens, Cupertino app shells, or a second component library. Prefer `ShadButton`, `ShadCard`, `ShadInput`, `ShadDialog`, `ShadToast` / `ShadToaster`, `ShadProgress`, etc.

`ThemeMode` / `Brightness` may be imported from Flutter as needed to configure `ShadApp`; that does not mean building Material UIs.

## Layout conventions

```text
lib/
  main.dart                 # wire dependencies once
  app.dart                  # ShadApp + theme
  core/                     # shared pure helpers (formatting, constants, fade routes)
  data/<domain>/            # models, repositories, API clients
  features/<feature>/       # screens, feature-local widgets, screen-scoped controllers
  widgets/                  # shared presentational widgets
```

- Keep **screens thin**: load state, call services, compose UI.
- Map provider-specific JSON **inside** the Yahoo / crypto exchange client, not in widgets.
- Feature folders own their screens; shared chart stays under `widgets/`.
- **Screen-scoped `ChangeNotifier`s** (provided at the route/screen with `ChangeNotifierProvider`, not in `main.dart`) own feature async: [`QuotesListController`](lib/features/quotes/quotes_list_controller.dart), [`PortfolioScreenController`](lib/features/portfolio/portfolio_screen_controller.dart), [`AssetDetailController`](lib/features/asset_detail/asset_detail_controller.dart), [`AgentChatController`](lib/features/agents/agent_chat_controller.dart). Use load-generation tokens so stale responses are ignored.
- Shared chrome: `TabPageHeader`, `SubscreenAppBar`, `AppEmptyView`, `QuotesAsyncBody`, `MetricStat`, `SummaryWell`, `ThemedAccordionItem`, [`MasterDetailShell`](lib/widgets/master_detail_shell.dart) / `MasterDetailNavTile` / `MasterDetailContentPane` (Settings, Markets, Crypto — wide sidebar + content at ≥720; narrow list → detail with Back), `pushFadePage` / `FadePageRoute`. Prefer [`showAppToast`](lib/widgets/app_toast.dart) over raw `ShadToaster`.
- Quote lists (Markets kind + Crypto exchange) always go through [`MarketDataClient`](lib/data/market/market_data_client.dart) — never call `CryptoExchangeClient.getQuotes` from UI.

## Market data — always use `MarketDataClient`

Widgets and portfolio code must depend on [`MarketDataClient`](lib/data/market/market_data_client.dart) only.  
**Never** call Yahoo / exchange URLs from UI code.

Default wiring in [`lib/main.dart`](lib/main.dart):

```dart
RoutingMarketDataClient(
  equitiesRegistry: EquityDataSourceRegistry([
    EquityDataSourceEntry(
      source: YahooMarketDataClient.meta,
      client: YahooMarketDataClient(),
    ),
  ]),
  cryptoRegistry: CryptoExchangeRegistry([CryptoComExchangeClient()]),
  dataSources: dataSourceSettings, // Settings → enable/disable (config slice)
)
```

Settings persists opt-outs in the unified config `dataSources` slice ([`DataSourceSettings`](lib/data/settings/data_source_settings.dart)) so new providers default to on. Markets / Crypto / Portfolio / routing only use enabled sources.

### Current API

- `Future<List<Quote>> getQuotes(List<String> symbols)`
- `Future<List<Candle>> getHistory(String symbol, {required String range, required String interval})`

### Adding an equities / general provider

1. Create `lib/data/market/<name>_market_data_client.dart` implementing `MarketDataClient`.
2. Add a stable `EquityDataSource` meta (`id`, `displayName`, optional `description`) on the client (see `YahooMarketDataClient.meta`).
3. Map that provider’s DTOs → `Quote` / `Candle`.
4. Register an `EquityDataSourceEntry` in `EquityDataSourceRegistry` in [`lib/main.dart`](lib/main.dart).
5. Document keys, rate limits, and terms in the README.
6. Prefer injecting via `Provider<MarketDataClient>` so tests can fake the client.

### Yahoo notes

- Base: `https://query1.finance.yahoo.com/v8/finance/chart/{symbol}`
- Send a browser-like `User-Agent` on native targets only (browsers forbid setting it).
- **Web CORS:** Yahoo omits `Access-Control-Allow-Origin`; [`YahooMarketDataClient`](lib/data/market/yahoo_market_data_client.dart) prefixes chart URLs with `https://proxy.cors.dev/` when `kIsWeb` so Chrome/Web builds can load equities. Native keeps a direct call. Do not send custom headers that trigger preflight through the free proxy.
- Encode symbols (`^GSPC`, forex `EURUSD=X`, etc.).
- Unofficial / unstable; handle HTTP errors and empty `chart.result` gracefully.
- Educational use; do not scrape aggressively.

Default Markets watchlist: [`lib/data/market/models.dart`](lib/data/market/models.dart) (`defaultWatchlistEntries` / `defaultWatchlist`) — curated Yahoo symbols (no free “list all” API). Markets tab ([`MarketsScreen`](lib/features/markets/markets_screen.dart)) uses master–detail for **Favorites / Indices / ETFs / Stocks** ([`MarketFavoritesPane`](lib/features/markets/market_favorites_body.dart), [`MarketKindPane`](lib/features/markets/market_kind_body.dart)); each kind subgroup loads `watchlistSymbolsForKind` in pages via [`QuotesListController`](lib/features/quotes/quotes_list_controller.dart) and groups by exchange via `groupQuotesByKindAndExchange`. Crypto is **not** on the Markets tab.

## Crypto exchanges — `CryptoExchangeClient`

Reusable public-market abstraction for crypto venues (spot quotes + history). UI uses the registry / router — never venue URLs.

```text
lib/data/crypto/
  crypto_exchange.dart              # id, displayName, defaultSymbols
  crypto_exchange_client.dart       # abstract public API (+ optional live portfolio)
  crypto_exchange_registry.dart     # Crypto group subgroups + symbol routing
  exchange_portfolio.dart           # live balance snapshot models
  crypto_com/crypto_com_exchange_client.dart
```

### Adding a crypto exchange

1. Create `lib/data/crypto/<venue>/<venue>_exchange_client.dart` implementing `CryptoExchangeClient`.
2. Map that venue’s DTOs → `Quote` / `Candle`; implement `handlesSymbol`.
3. Optionally override `canFetchPortfolio` / `fetchPortfolio` for live Portfolio subgroups.
4. Register in `CryptoExchangeRegistry([...])` in [`lib/main.dart`](lib/main.dart); inject credentials from [`EnvSecretsRepository`](lib/data/settings/env_secrets_repository.dart) / [`ExchangeCredentialsConfig.forId`](lib/data/market/exchange_credentials.dart) when the venue needs a key.
5. Add `OMNISCOPE_<EXCHANGE_ID>_API_{KEY|SECRET|TOKEN}` placeholders to [`.env.example`](.env.example) and append the id to [`ExchangeCredentialsConfig.defaultExchangeIds`](lib/data/market/exchange_credentials.dart).
6. It appears in Settings → Crypto exchanges automatically (enabled by default via [`DataSourceSettings`](lib/data/settings/data_source_settings.dart)). Add a credentials editor when the venue needs keys (Crypto.com is the template).
7. Document public endpoints / terms in the README.

### Crypto.com notes

- Base: `https://api.crypto.com/exchange/v1/`
- Public (no key): `get-tickers`, `get-candlestick`
- Optional private credentials (dual sync): `OMNISCOPE_CRYPTO_COM_API_KEY`, `_API_SECRET`, `_API_TOKEN` via `.env` **or** Settings → Crypto → Configure (persisted in `omniscope.json` + best-effort `.env` write on desktop)
- Live portfolio (key **and** secret): `POST /private/user-balance` (HMAC-SHA256) → Portfolio tab **Live** subgroup
- Spot symbols: `BTC_USD`, `ETH_USD`, … Curated `defaultSymbols` plus live catalog from `public/get-instruments` (`browseSymbols`); exchange screen paginates quote fetches.
- Educational use; do not scrape aggressively.

### Crypto UI

- Shell tab **Crypto** → [`CryptoGroupScreen`](lib/features/crypto/crypto_group_screen.dart) (master–detail of exchanges).
- Exchange content → [`CryptoExchangeHub`](lib/features/crypto/crypto_exchange_hub.dart) (nested master–detail: Favorites + Spot pairs).
- Panes → [`CryptoExchangeFavoritesPane`](lib/features/crypto/crypto_exchange_favorites_body.dart) / [`CryptoExchangePairsPane`](lib/features/crypto/crypto_exchange_pairs_body.dart).

## Agents (AI helpers)

Optional local LLM connections for roles listed in the agents package manifest. Educational / paper-trading context only — **no real brokerage**.

### Role → framework (fixed — do not swap)

| Role | Framework | Workload | Model preset |
|------|-----------|----------|--------------|
| **Market Research & Analysis** | **Always CrewAI** | Investigation | Prefer **lighter** models |
| **Intraday Execution & Risk Control** | **Always LangGraph** | Trading | Prefer **heavier** models |
| **Hedge Fund Desk** | **LangGraph** orchestration (CrewAI for analyst + bull/bear stages) | Trading | Prefer **heavier** models |

The Agents tab role list is **populated from** [`agents/omniscope_agents/manifest.json`](agents/omniscope_agents/manifest.json) (not hard-coded in the UI). When you add a CrewAI or LangGraph package under `agents/omniscope_agents/`, register it in that manifest so Flutter discovers it.

Users choose the **LLM provider** (Gemini, ChatGPT/OpenAI, Claude, DeepSeek, Grok, Custom), **API key**, and **model**. Frameworks are read-only per role. Connect dialog **preselects** the role’s `suggestedModels` entry for the chosen provider (lighter for investigation, heavier for trading).

DeepSeek and Grok use OpenAI-compatible APIs (`https://api.deepseek.com`, `https://api.x.ai/v1`) with the user’s own key; model IDs live in the catalog JSON (`weight`: `light` / `heavy`).

### Layout

```text
agents/                         # Python package (CLI runners)
  omniscope_agents/
    manifest.json               # available roles + model presets (Flutter asset)
    llm.py                      # provider + model + api_key → LLM
    market_research/            # CrewAI
    trading/                    # LangGraph
    hedge_fund/                 # LangGraph desk + CrewAI analysts/debate + live tools

assets/agents/llm_models.json   # selectable models per provider (data-driven)
.env.example / .env             # optional local secrets: LLM + exchange/market (gitignored)

lib/data/agents/                # Flutter models + AgentsRepository + catalog loaders
lib/features/agents/            # Agents tab UI
```

### Hedge Fund Desk

Paper-only multi-agent pipeline inspired by TradingAgents-style role separation:

1. **Analysts (CrewAI)** — Technical (yfinance + pandas-ta), Sentiment & News (Yahoo news + public RSS), Fundamental (SEC EDGAR via edgartools).
2. **Researchers (CrewAI)** — Bullish vs Bearish dialectical debate over the analyst packet.
3. **Risk Manager + Head Trader (LangGraph)** — hard educational gates (position %, cash, max shares, realized-vol cap) with absolute veto; approved trades emit JSON `{ticker, action, quantity, rationale, risk_approved}` (no broker API).

CLI: `python -m omniscope_agents.hedge_fund.run --symbol AAPL ...` (see [`agents/README.md`](agents/README.md)).

### Persistence & keys

- All customization lives in one document managed by [`UserConfigStore`](lib/data/settings/user_config_store.dart) (see **User config file** below): agents connections, chat threads, secrets, favorites, theme/display, data sources, paper portfolio.
- Chat threads: one thread per role via [`AgentChatRepository`](lib/data/agents/agent_chat_repository.dart) (`agentChats` slice).
- API keys stay **on device only** (plaintext in the config file / Web blob; no cloud sync).
- Disconnect clears the stored API key (chat history is kept until Clear).
- Role list: [`AgentRoleCatalog`](lib/data/agents/agent_role_catalog.dart) ← `agents/omniscope_agents/manifest.json`.
- Model IDs come from [`assets/agents/llm_models.json`](assets/agents/llm_models.json) via `LlmModelCatalog` — refresh that JSON later without changing UI code. Custom provider uses free-text model id + base URL.
- Optional **local `.env`** (same file for LLM and venues): copy [`.env.example`](.env.example) → `.env`. Dual sync via [`EnvSecretsRepository`](lib/data/settings/env_secrets_repository.dart) (asset + live file bootstrap, config `secrets` overlay, UI write-back).
  - LLM: `OMNISCOPE_<PROVIDER>_API_KEY` → Agents → Connect suggests the key; connecting saves to the config file and upserts `.env` when the project file is writable (desktop checkout).
  - Exchanges: `OMNISCOPE_<EXCHANGE_ID>_API_{KEY|SECRET|TOKEN}` (e.g. Crypto.com) → Settings → Configure suggests values; save/clear syncs config + `.env` when possible. Injected into clients such as [`CryptoComExchangeClient`](lib/data/crypto/crypto_com/crypto_com_exchange_client.dart). Public market data still works with empty values.
  - Web / mobile keep full UX via the config blob; `.env` file write is a no-op there.
  - `.env` is gitignored and bundled as an asset — run `make get` / `make check` (or `tool/flutter_checks.sh`, or copy the example) so the file exists before `flutter run` / test.

### In-app chat

- Connected role → **Open chat** → [`AgentChatScreen`](lib/features/agents/agent_chat_screen.dart).
- Flutter calls provider HTTPS directly via [`LlmChatClient`](lib/data/agents/llm_chat_client.dart) (OpenAI-compatible, Anthropic, Gemini) using the stored connection — **does not** spawn Python CrewAI/LangGraph.
- Freeform messages plus a role-aware **Run** shortcut (symbol → structured turn). Before the LLM call, a compact quote/history snapshot may be injected from [`MarketDataClient`](lib/data/market/market_data_client.dart).
- One persisted thread per role; reload on reopen. Clear chat is optional and local-only.
- Full multi-agent Python pipelines remain CLI-only under `agents/` (see [`agents/README.md`](agents/README.md)).

### UI

- Shell tab **Agents** → one card per manifest role; connect/disconnect with suggested model presets; **Open chat** when connected.

## User config file

Single JSON document for secrets, favorites, and all customizations ([`UserConfigStore`](lib/data/settings/user_config_store.dart)):

- **Default path (native):** `{getApplicationSupportDirectory()}/omniscope.json` via `path_provider`.
- **Custom path:** desktop only (Linux / Windows / macOS) — Settings → Data file; override stored in prefs key `omniscope.config_path.v1`.
- **Web:** no filesystem path — full document in prefs blob `omniscope.config.v1`; Import / Export in Settings.
- **Slices:** `theme`, `display`, `dataSources`, `secrets`, `agents`, `agentChats`, `paperPortfolio`, `favorites`.
- **Legacy migration:** first load absorbs old per-feature prefs keys then removes them.
- **`.env` dual-write:** secrets still upsert into the project `.env` when writable (Python CLI). On startup, non-empty `.env` / asset keys that are missing or empty in the config are **promoted** into `omniscope.json` so checkout edits persist for Flutter.
- Treat the file as secrets — it may contain API keys.

Favorites ([`FavoritesRepository`](lib/data/settings/favorites_repository.dart)): star quote rows; Markets landing has a **Favorites** subgroup; each Crypto exchange landing has **Favorites** + **Spot pairs**.

## Settings

Shell tab **Settings** (and Markets / Crypto) use [`MasterDetailShell`](lib/widgets/master_detail_shell.dart): wide (≥720) = persistent sidebar + content pane; narrow = list → detail with Back. Switching sections unloads the previous body ([`settings_screen.dart`](lib/features/settings/settings_screen.dart)).

- **About** — tagline ([`AppCopy`](lib/core/app_copy.dart)), version ([`AppInfo`](lib/core/app_info.dart)), educational disclaimer.
- **Appearance** — theme ([`ThemeSettings`](lib/data/settings/theme_settings.dart)), list density / price format / default chart range ([`DisplaySettings`](lib/data/settings/display_settings.dart)).
- **Data sources** — equities / crypto enable toggles + Crypto.com credentials (existing).
- **Portfolios** — practice starting cash / reset, plus status of live exchange portfolios (credentials under Data sources).
- **API keys** — all LLM providers with local key status (red = missing, green = saved); Add/Edit via dialog; keys stay on-device only ([`EnvSecretsRepository.setLlmApiKey`](lib/data/settings/env_secrets_repository.dart)).
- **Connections** — summary of exchange credentials and connected agents.
- **Data file** — effective config path, desktop custom path, Import / Export JSON.
- **Privacy & data** — clear favorites, chats, disconnect agents, reset paper, clear exchange credentials.

## Portfolio

- **Unified list** — [`PortfolioCatalog`](lib/data/portfolio/portfolio_catalog.dart) lists Practice plus each live exchange portfolio for Settings and the Portfolio tab.
- **Practice (paper)** — `paperPortfolio` slice in the unified config file.
  - Default starting cash: **$10,000** (`PortfolioState.defaultStartingCash`); configurable via Settings → Portfolios / `PortfolioRepository.startingCash` (stored in the same JSON blob).
  - Holdings: `{ symbol, shares, avgCost }`; buy averages cost; sell removes the row at zero shares.
  - Mark-to-market using `MarketDataClient.getQuotes` — never hard-code prices in the repository.
  - Reset restores configured starting cash and clears holdings (confirm in UI; does not touch live balances).
  - UI: secondary / muted chrome + **Paper** badge.
- **Live (exchange)** — when a registered `CryptoExchangeClient` has `canFetchPortfolio` (e.g. Crypto.com key+secret) and the venue is enabled in Settings, Portfolio shows another accordion subgroup (`supportsLivePortfolio` marks venues that can unlock Live once credentials are set).
  - Fetch via `CryptoExchangeClient.fetchPortfolio()` → [`ExchangePortfolioSnapshot`](lib/data/crypto/exchange_portfolio.dart); never call venue URLs from UI.
  - UI: primary chrome + **Live** badge; read-only balances.

## UI / UX norms

**Every new feature starts with UX.** Design and implement **mobile-first**, then scale up for larger screens (Linux / Windows / macOS / Web). Do not ship desktop-only layouts that break on phone.

### Mobile-first & responsive (required)

- **Phone is the default canvas** — layouts, touch targets, and copy must work on a narrow Android / iOS / browser viewport before widening for desktop.
- Use `SafeArea`, scrollable bodies (`ListView` / `SingleChildScrollView`), and flexible children (`Expanded` / `Flexible`) so content never clips or overflows.
- Prefer `LayoutBuilder` / `MediaQuery` (or equivalent breakpoints) when a screen needs a different arrangement on wide vs narrow; avoid hard-coded widths that assume a desktop window.
- Touch targets ≥ ~44×44 logical px; primary actions stay reachable with one thumb where practical.
- Dialogs, toasts, and trade flows must remain usable on small screens (no horizontal overflow, no unreachable buttons).
- Charts and dense rows must reflow or scroll; never assume a fixed wide chart area.
- Verify **Linux**, **Windows**, **Android**, **Apple** (iOS / macOS), and **Web** when changing UI — regressing any target is a bug.

### Brand colors (required)

Canonical tokens live in [`lib/core/brand_colors.dart`](lib/core/brand_colors.dart) and are wired into `ShadThemeData` in [`lib/app.dart`](lib/app.dart). **Every** new icon, image tint, border, shadow, fill, focus ring, and chart accent must use this palette — no one-off hex colors.

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| **Primary** | `#0F766E` | `#2DD4BF` | Brand, icons, CTAs, focus/ring, shadows (primary @ ~16% alpha) |
| **Primary foreground** | `#F0FDFA` | `#042F2E` | Text/icons on primary |
| **Secondary** | `#CCFBF1` | `#134E4A` | Soft wells, selected nav, icon backgrounds |
| **Secondary foreground** | `#134E4A` | `#99F6E4` | Text on secondary |
| **Border / input** | `#B7C9C5` | `#3A5552` | Dividers, card edges, inputs (quiet slate-teal) |
| **Gain** | `#15803D` | `#4ADE80` | Positive numbers, up charts only |
| **Loss** | `#DC2626` | `#F87171` | Negative numbers, down charts (`destructive`) |

- Prefer `theme.colorScheme.primary` / `.secondary` / `.border` / `.destructive`, or `BrandColors.gainOf` / `lossOf` / `shadowOf`.
- Do **not** use primary for P&L up/down — keep gain/loss distinct so numbers stay easy to read.
- Do not invent new accent colors (no purple, terracotta, freeform grays for chrome).
- See also `.cursor/rules/brand-colors.mdc`.

### Product UX

- One clear job per screen (Markets master–detail, Crypto exchange hub, Asset detail, Portfolio summary, Agents connect).
- Asset detail: curated overviews for default symbols ([`asset_overviews.dart`](lib/data/market/asset_overviews.dart)); external research links ([`market_data_links.dart`](lib/data/market/market_data_links.dart)): provider attribution plus Wikipedia (when mapped), Google Finance / TradingView; open via `url_launcher` in the system browser (educational only).
- Settings → About: tagline from [`app_copy.dart`](lib/core/app_copy.dart) plus educational disclaimer.
- Loading: `ShadProgress`. Errors: short message + retry.
- Trade feedback: `ShadToaster` + `ShadToast` (use `.destructive` for failures).
- Theme: slate neutrals + brand primary/secondary via `BrandColors` in `app.dart`.
- Keep copy plain — this product is for people who find finance intimidating.
- Shared brand mark: [`lib/widgets/app_placeholder_icon.dart`](lib/widgets/app_placeholder_icon.dart) in a compact shell header (uses [`assets/brand/app_icon.png`](assets/brand/app_icon.png)).
- Launcher / favicon pipeline: edit masters under `assets/brand/`, then run `make icons` (or [`tool/regen_icons.sh`](tool/regen_icons.sh)) (Android / iOS / macOS / Web / Windows via `flutter_launcher_icons`, plus Linux `linux/runner/resources/`).

## Commands

Root [`Makefile`](Makefile) is the developer catalog (`make help`). On Windows hosts, use Git Bash or WSL. Hooks still call `tool/*.sh` directly.

```bash
export PATH="$HOME/flutter/bin:$PATH"
make get
make check              # analyze + test (same as pre-push)
make run                # DEVICE=linux by default
make run DEVICE=windows # needs Windows desktop toolchain
make run DEVICE=android # needs Android SDK / device
make run DEVICE=ios     # needs Xcode / Apple toolchain (macOS host)
make run DEVICE=macos   # needs Xcode / macOS desktop toolchain
make run DEVICE=chrome  # Web (or edge / web-server)
make icons
make agents-setup       # agents/ venv + pip install -e .
make bump-patch         # local patch bump (pubspec + AppInfo); CI also runs this on main
# equivalents: flutter pub get | flutter analyze | flutter test
#              tool/flutter_checks.sh all | tool/regen_icons.sh
```

### Versioning

- Flutter version lives in [`pubspec.yaml`](pubspec.yaml) as `MAJOR.MINOR.PATCH+BUILD` and Settings → About reads [`AppInfo.version`](lib/core/app_info.dart) (`MAJOR.MINOR.PATCH` only).
- **Patch (+ build)** auto-bumps on every push to `main` via [`.github/workflows/bump-patch-version.yml`](.github/workflows/bump-patch-version.yml) (`tool/bump_patch_version.sh`). Skipped when that push already edited the `version:` line (manual major/minor).
- **Major / minor**: edit `pubspec.yaml` and `AppInfo.version` yourself in a normal PR.

### Git hooks (pre-commit)

Install once: `make hooks` (or `pre-commit install --hook-type pre-commit --hook-type pre-push`)

- **pre-commit**: secret scan (gitleaks + private-key detect), merge-conflict / large-file checks
- **pre-push**: gitleaks + `flutter analyze` + `flutter test`

Do not commit `.env`, API keys, or credential JSON. Config: [`.pre-commit-config.yaml`](.pre-commit-config.yaml), [`.gitleaks.toml`](.gitleaks.toml).

Linux deps (Fedora): `clang`, `cmake`, `ninja-build`, `gtk3-devel`, `pkgconf-pkg-config`, etc. See README.

## When changing behavior

- Prefer extending `MarketDataClient` / `CryptoExchangeClient` over leaking provider details upward.
- Prefer new feature folders over dumping widgets into `main.dart`.
- Ship UX mobile-first and responsive (see **UI / UX norms** and `.cursor/rules/ux-mobile-first.mdc`).
- Keep **all** targets working: Linux, Windows, Android, iOS, macOS, Web (see `.cursor/rules/cross-platform.mdc`).
- Adhere to **Brand colors** (and `.cursor/rules/brand-colors.mdc`) for every visual token.
- Update README + this file when architecture or dependency rules change.
