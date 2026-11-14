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

## Coding-assistant tooling

Editor AI helpers (Cursor, Codex, Claude Code, and similar) — **not** the in-app Agents tab (Genkit Dart).

**Single source of truth:** root [`AGENTS.md`](AGENTS.md) (this file) plus [`.agents/skills/`](.agents/skills/). Do **not** add parallel `.claude/` or `.codex/` instruction trees that restate product rules (brand, UX, cross-platform, in-app agents). Those rules stay in [`.cursor/rules/`](.cursor/rules/) for Cursor and in this handbook for every agent.

| Path | Role |
|------|------|
| [`AGENTS.md`](AGENTS.md) | Shared project guidance for Codex, Claude Code, Cursor, and humans |
| [`.agents/skills/`](.agents/skills/) | Official Flutter + Dart [Agent Skills](https://docs.flutter.dev/ai/tools) plus [Genkit](https://genkit.dev/docs/dart/get-started/) (on-demand recipes: layouts, tests, analysis, Genkit flows, etc.) |
| [`.cursor/rules/`](.cursor/rules/) | Cursor-only persistent Omniscope product rules plus official [`flutter-hot-reload.mdc`](.cursor/rules/flutter-hot-reload.mdc) |
| [`.cursor/mcp.json`](.cursor/mcp.json) | Cursor Dart / Flutter MCP server (`dart mcp-server`) for analyzer, tests, and runtime hot reload |

### How each tool discovers guidance

| Tool | Instructions | Skills | Notes |
|------|--------------|--------|-------|
| **Codex** | Root `AGENTS.md` | [`.agents/skills/`](.agents/skills/) | No committed `.codex/` required. Add `.codex/config.toml` later only for shared project MCP/hooks when the project is trusted; otherwise keep Codex config in `~/.codex/`. |
| **Claude Code** | Same `AGENTS.md` (Claude can load it in place of `CLAUDE.md`) | Keep skills under `.agents/skills/` (`make agent-skills`); do not re-home them under `.claude/skills/` | No committed `.claude/` instruction mirror. Add a thin root `CLAUDE.md` (pointer + `make check` / `make run` only) or `.claude/` settings/MCP only if a real Claude Code gap appears. |
| **Cursor** | This file + [`.cursor/rules/`](.cursor/rules/) | [`.agents/skills/`](.agents/skills/) | Dart MCP via [`.cursor/mcp.json`](.cursor/mcp.json). |

Refresh vendored skills from upstream:

```bash
make agent-skills
# or:
# npx skills add flutter/agent-plugins --skill '*' --agent universal --yes
# npx skills add dart-lang/skills --skill '*' --agent universal --yes
# npx skills add genkit-ai/skills --skill developing-genkit-dart --agent universal --yes
```

Optional: install the [Dart and Flutter Cursor marketplace plugin](https://docs.flutter.dev/ai/get-started) (`/add-plugin dart-flutter` or Customize → Dart and Flutter) for a machine-local bundle of skills + MCP; the committed `.agents/skills/` and `.cursor/mcp.json` already cover the project for anyone who clones the repo.

**Hot reload vs restart:** Enable the Dart MCP server in Cursor (Tools / MCP) so [`flutter-hot-reload.mdc`](.cursor/rules/flutter-hot-reload.mdc) can call `hot_reload` / `hot_restart` against a running app. UI edits under `lib/` → hot reload. Changes to [`lib/main.dart`](lib/main.dart), the provider graph, or `initState` wiring → hot restart.

Do not confuse this with **Agents** in the app (Genkit chat / Confirm trades). [`.agents/`](.agents/) is editor skills only.

## Stack

| Layer | Choice |
|-------|--------|
| UI kit | **`shadcn_ui` only** — root app is `ShadApp` |
| Charts | In-repo `CustomPaint` ([`lib/widgets/price_line_chart.dart`](lib/widgets/price_line_chart.dart)) — do **not** add `fl_chart` or other chart UI packages unless product explicitly changes this rule |
| State | `provider` |
| HTTP | `http` |
| Local persistence | `omniscope.json` via [`UserConfigStore`](lib/data/settings/user_config_store.dart) (`path_provider`; Web uses a prefs blob) |
| Market data | `MarketDataClient` → `CachingMarketDataClient` → `RoutingMarketDataClient` (Yahoo equities + crypto registry; in-memory quote/history TTL) |
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
- Shared chrome: `TabPageHeader`, `SubscreenAppBar`, `AppEmptyView`, `QuotesAsyncBody`, `MetricStat`, `SummaryWell`, `ThemedAccordionItem`, [`MasterDetailShell`](lib/widgets/master_detail_shell.dart) / `MasterDetailNavList` / `MasterDetailNavTile` / `MasterDetailContentPane` (Markets, Portfolio, Settings — wide sidebar + content at ≥720; narrow list → detail with Back), `pushFadePage` / `FadePageRoute`, [`AgentLaunchButton`](lib/widgets/agent_launch_button.dart) (in-context Investigate / Trade check). Prefer [`showAppToast`](lib/widgets/app_toast.dart) over raw `ShadToaster`.
- Quote lists (Markets equity kinds + crypto exchange spot) always go through [`MarketDataClient`](lib/data/market/market_data_client.dart) — never call `CryptoExchangeClient.getQuotes` from UI.

## Market data — always use `MarketDataClient`

Widgets and portfolio code must depend on [`MarketDataClient`](lib/data/market/market_data_client.dart) only.  
**Never** call Yahoo / exchange URLs from UI code.

Default wiring in [`lib/main.dart`](lib/main.dart):

```dart
CachingMarketDataClient(
  RoutingMarketDataClient(
    equitiesRegistry: EquityDataSourceRegistry([
      EquityDataSourceEntry(
        source: YahooMarketDataClient.meta,
        client: YahooMarketDataClient(),
      ),
    ]),
    cryptoRegistry: CryptoExchangeRegistry([CryptoComExchangeClient()]),
    dataSources: dataSourceSettings, // Settings → enable/disable (config slice)
  ),
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

Default Markets watchlist: [`lib/data/market/models.dart`](lib/data/market/models.dart) (`defaultWatchlistEntries` / `defaultWatchlist`) — curated Yahoo symbols (no free “list all” API). Markets tab ([`MarketsScreen`](lib/features/markets/markets_screen.dart)) uses master–detail for **Favorites / Indices / ETFs / Stocks** plus each enabled **crypto exchange** ([`MarketFavoritesPane`](lib/features/markets/market_favorites_body.dart), [`MarketKindPane`](lib/features/markets/market_kind_body.dart), [`CryptoExchangePairsPane`](lib/features/crypto/crypto_exchange_pairs_body.dart)); equity kinds load `watchlistSymbolsForKind` in pages via [`QuotesListController`](lib/features/quotes/quotes_list_controller.dart) and group by exchange via `groupQuotesByKindAndExchange`. Favorites is one ordered list for equities and spot pairs.

## Crypto exchanges — `CryptoExchangeClient`

Reusable public-market abstraction for crypto venues (spot quotes + history). UI uses the registry / router — never venue URLs.

```text
lib/data/venues/                    # shared LiveVenueCapabilities, credential schemas, VenueCatalog
lib/data/crypto/
  crypto_exchange.dart              # id, displayName, defaultSymbols
  crypto_exchange_client.dart       # abstract public API (+ optional live portfolio)
  crypto_exchange_registry.dart     # Crypto group subgroups + symbol routing
  exchange_portfolio.dart           # re-exports venues/exchange_portfolio.dart
  crypto_com/crypto_com_exchange_client.dart
lib/data/brokers/
  alpaca/                           # Alpaca paper/live portfolio + orders
```

Venues register in **one place**: [`VenueCatalog.build`](lib/data/venues/venue_catalog.dart) (wired from [`lib/main.dart`](lib/main.dart)). Settings → Credentials cards and `.env` dual-sync ids are **derived from the catalog** — do not hard-code per-venue Settings widgets.

### Adding a crypto exchange

1. Create `lib/data/crypto/<venue>/` with a `CryptoExchangeClient` (+ DTO mapping file).
2. Map that venue’s DTOs → `Quote` / `Candle`; implement `handlesSymbol`.
3. Optionally override `canFetchPortfolio` / `fetchPortfolio` / orders; declare a static `VenueCredentialSchema`.
4. Append one `VenueRegistration.crypto(...)` line in [`VenueCatalog.build`](lib/data/venues/venue_catalog.dart) and add the id to `VenueCatalog.knownCredentialVenueIds`.
5. Add `OMNISCOPE_<EXCHANGE_ID>_API_{KEY|SECRET|TOKEN}` placeholders to [`.env.example`](.env.example).
6. It appears under Settings → Crypto venues + generic Credentials automatically (enabled by default via [`DataSourceSettings`](lib/data/settings/data_source_settings.dart)).
7. Document public endpoints / terms in the README.
8. Add recorded response fixtures under `test/fixtures/venues/<id>/` and MockClient contract tests (see **Venue API health** below); extend [`tool/venue_canary.dart`](tool/venue_canary.dart) probes for the new venue.

### Adding a broker venue (stocks / ETFs)

1. Create `lib/data/brokers/<venue>/` implementing [`BrokerExchangeClient`](lib/data/trading/broker_exchange_client.dart) (+ DTO / auth helpers). Keep equities **quotes on Yahoo** / `MarketDataClient` — brokers are private portfolio + orders.
2. Override live portfolio + order methods; declare `VenueCredentialSchema` (use `supportsTradingMode` when paper/live hosts differ).
3. Append one `VenueRegistration.broker(...)` in [`VenueCatalog.build`](lib/data/venues/venue_catalog.dart) and update `knownCredentialVenueIds`.
4. Add env placeholders to [`.env.example`](.env.example).
5. Settings → Brokers toggle + Credentials card appear automatically; Live portfolio / Confirm stay gated until key+secret unlock `canFetchPortfolio` / `canPlaceOrders`.
6. Add fixtures + canary portfolio probe (same **Venue API health** rules as crypto).

### Venue API health

Do **not** add curl suites or live network calls to `make check` / pre-push. Track APIs with two layers:

| Layer | When | Role |
|-------|------|------|
| **Fixture contract tests** | Every PR (`make check`) | Checked-in JSON under [`test/fixtures/venues/`](test/fixtures/venues/) + [`VenueHttpFixtures`](test/support/venue_http_fixtures.dart) / `MockClient` — proves adapters still parse known shapes |
| **Live canary** | `make venue-canary` or scheduled [`.github/workflows/venue-canary.yml`](.github/workflows/venue-canary.yml) | Hits real endpoints through Dart clients ([`tool/venue_canary.dart`](tool/venue_canary.dart)); writes `build/venue-canary.json` + markdown matrix. Tag `live_canary` is excluded from [`tool/flutter_checks.sh`](tool/flutter_checks.sh) |

**Refresh ritual** when a canary fails on parse: capture a fresh public response into `test/fixtures/venues/<id>/`, fix the adapter, keep the updated fixture as the regression. Prefer fixtures over inline JSON so schema drift is visible in git diffs. Public probes always run; portfolio probes need credentials in `.env` (or optional GitHub Actions secrets). Canary **never** places live orders.

### Crypto.com notes

- Base: `https://api.crypto.com/exchange/v1/`
- Public (no key): `get-tickers`, `get-candlestick`
- Optional private credentials (dual sync): `OMNISCOPE_CRYPTO_COM_API_KEY`, `_API_SECRET`, `_API_TOKEN` via `.env` **or** Settings → Data sources → Configure (persisted in `omniscope.json` + best-effort `.env` write on desktop)
- Live portfolio (key **and** secret): `POST /private/user-balance` (HMAC-SHA256) → Portfolio tab **Live** subgroup
- Live orders (same credentials): `POST /private/create-order` (+ cancel / get-order-detail) via [`canPlaceOrders`](lib/data/crypto/crypto_exchange_client.dart) → agent Confirm / Autopilot through [`TradeExecutor`](lib/data/trading/trade_executor.dart)
- Spot symbols: `BTC_USD`, `ETH_USD`, … Curated `defaultSymbols` plus live catalog from `public/get-instruments` (`browseSymbols`); exchange screen paginates quote fetches.
- Educational use; do not scrape aggressively.

### Alpaca notes

- Paper: `https://paper-api.alpaca.markets` · Live: `https://api.alpaca.markets`
- Credentials: `OMNISCOPE_ALPACA_API_KEY` / `_API_SECRET` + optional `OMNISCOPE_ALPACA_TRADING_MODE=paper|live` (Settings Paper/Live control; paper and live use **different** Alpaca key pairs)
- Live portfolio: `GET /v2/account` + `GET /v2/positions` → Portfolio **Live**
- Orders: `POST /v2/orders` (+ cancel / get) when credentials are set → agent Confirm / Autopilot
- Not a Markets quote source — equities charts stay on Yahoo
- Educational use; review Alpaca terms before redistribution

### Crypto UI

- Markets sidebar lists each enabled venue; selecting one opens [`CryptoExchangePairsPane`](lib/features/crypto/crypto_exchange_pairs_body.dart) (Spot pairs). Starred pairs join the shared Markets Favorites list.

## Agents (AI helpers)

Optional on-device LLM connections for roles listed in the Genkit role catalog. Educational context — users Confirm live suggestions; Autopilot is opt-in per agent.

**Practice (paper) and live exchanges are both valid agent trade targets.** Connect can set an optional **default portfolio**; Confirm uses that default when set, otherwise asks the user to pick (Practice + live venues). Autopilot requires a default (or a single available target). With no live credentials, Practice alone unlocks trading Runs and is the default target. Live venues still need credentials under Settings → Data sources.

### Role → Genkit (in-process)

| Role | Framework | Workload | Model preset |
|------|-----------|----------|--------------|
| **Market Research & Analysis** | **Genkit** | Investigation | Prefer **lighter** models |
| **Live Balance Explainer** | **Genkit** | Investigation | Prefer **lighter** models |
| **Portfolio & Allocation Guide** | **Genkit** | Investigation | Prefer **lighter** models |
| **Practice Portfolio Coach** | **Genkit** | Investigation | Prefer **lighter** models |
| **Intraday Execution & Risk Control** | **Genkit** | Trading | Prefer **heavier** models |

The Agents tab role list is **populated from** [`assets/agents/manifest.json`](assets/agents/manifest.json). Chat turns run **in-process Genkit** (`defineAgent` + tools) via [`GenkitAgentRunner`](lib/data/agents/genkit/genkit_agent_runner.dart) — not hand-rolled provider HTTP and not Python. Hedge Fund Desk was dropped for this Genkit cutover.

Users choose the **LLM provider** (Gemini, ChatGPT/OpenAI, Claude, DeepSeek, Grok, Custom), **API key**, and **model**. Connect dialog **preselects** the role’s `suggestedModels` entry for the chosen provider (lighter for investigation, heavier for trading). Genkit plugins (`genkit_google_genai`, `genkit_openai`, `genkit_anthropic`) talk to providers under the hood.

### Layout

```text
assets/agents/manifest.json     # role catalog (ids, workload, model presets)
assets/agents/llm_models.json   # selectable models per provider (data-driven)
.env.example / .env             # optional local secrets: LLM + exchange/market (gitignored)

lib/data/agents/                # models, AgentsRepository, catalog, prompts
  genkit/                       # GenkitAgentRunner, tools, runtime factory
lib/data/trading/               # TradeExecutor, order models, BrokerExchangeRegistry
lib/features/agents/            # Agents tab UI (Roles / connect / chat)
lib/features/activity/          # Activity shell tab (proposals + confirm)
```

### Prompt source of truth

1. **Role catalog** — [`assets/agents/manifest.json`](assets/agents/manifest.json): ids, titles, framework (`genkit`), model presets. No prompt bodies.
2. **In-app Genkit prompts** — [`agent_role_prompts.dart`](lib/data/agents/agent_role_prompts.dart): system + Run user templates for `defineAgent`.

Trade proposal fields `{ticker, action, quantity, rationale, risk_approved}` — [`TradeProposalLlmSchema.canonicalLlmKeys`](lib/data/agents/trade_proposal.dart).

### Live trade suggestions (in-app)

- Trading role `intradayTrading` emits a fenced JSON block parsed into [`TradeProposal`](lib/data/agents/trade_proposal.dart).
- [`TradeExecutor`](lib/data/trading/trade_executor.dart) routes Confirm / Autopilot to Practice or live venues with `canPlaceOrders` (Crypto.com + Alpaca).
- Chat shows Confirm / Dismiss; Autopilot is configured on Connect/Edit (default **off**).
- Shell tab **Activity** lists proposals and events with portfolio labels; pending rows support Confirm / Dismiss.

### Persistence & keys

- All customization lives in one document managed by [`UserConfigStore`](lib/data/settings/user_config_store.dart) (see **User config file** below): agents connections, chat threads, secrets, favorites, theme/display, data sources, paper portfolio.
- Chat threads: one thread per role via [`AgentChatRepository`](lib/data/agents/agent_chat_repository.dart) (`agentChats` slice).
- API keys stay **on device only** (plaintext in the config file / Web blob; no cloud sync).
- Disconnect clears the stored API key (chat history is kept until Clear).
- Role list: [`AgentRoleCatalog`](lib/data/agents/agent_role_catalog.dart) ← `assets/agents/manifest.json`.
- Model IDs come from [`assets/agents/llm_models.json`](assets/agents/llm_models.json) via `LlmModelCatalog`. Custom provider uses free-text model id + base URL.
- Optional **local `.env`** (same file for LLM and venues): copy [`.env.example`](.env.example) → `.env`. Dual sync via [`EnvSecretsRepository`](lib/data/settings/env_secrets_repository.dart).
  - LLM: `OMNISCOPE_<PROVIDER>_API_KEY` → Agents → Connect suggests the key.
  - Exchanges: `OMNISCOPE_<EXCHANGE_ID>_API_{KEY|SECRET|TOKEN}` → Settings → Configure.
  - Web / mobile keep full UX via the config blob; `.env` file write is a no-op there.

### In-app chat

- Connected role → **Open chat** → [`AgentChatScreen`](lib/features/agents/agent_chat_screen.dart).
- Turns go through [`GenkitAgentRunner`](lib/data/agents/genkit/genkit_agent_runner.dart): in-process Genkit `defineAgent` with market/portfolio **tools** (`getQuotes`, `getHistory`, `getPracticePortfolio`, `getLiveBalances`).
- Freeform messages plus a role-aware **Run** shortcut (symbol → structured turn; Live Balance Explainer, Portfolio Guide, and Practice Coach can Run without a symbol).
- Trading Runs require a tradable exchange; otherwise the UI gates with a CTA to Settings → Data sources. Live Balance Explainer needs a venue that can fetch balances.
- Proposal cards under assistant bubbles: Confirm → [`TradeExecutor.submit`](lib/data/trading/trade_executor.dart); portfolio picker when no Connect default.
- One persisted thread per role; reload on reopen. Clear chat is optional and local-only.

### Robustness score (1–100)

Each Roles list card shows a **Robustness N** badge ([`AgentRobustness`](lib/data/agents/agent_robustness.dart)). The score is **computed** (not stored in `manifest.json`):

\[
score = \mathrm{clamp}(W + F + D + G + T,\ 1,\ 100)
\]

| Factor | Max | Points |
|--------|-----|--------|
| Workload \(W\) | 20 | investigation 8 / trading 20 |
| Framework \(F\) | 20 | Genkit 14 |
| Pipeline depth \(D\) | 25 | 1 stage 6 / 2–3 14 / 4–6 20 / 7+ 25 |
| Risk gates \(G\) | 20 | none 0 / soft 10 / hard veto + trade JSON 20 |
| Context & tools \(T\) | 15 | quotes-only 5 / portfolio snapshot 10 / multi-source 15 |

**Meaning:** higher = more complex pipeline and stronger controls — **not** “better advice” or live reliability.

Locked examples: Market Research **41**, Live Balance / Portfolio Guide / Practice Coach **46**, Intraday **78**.

### UI

- Shell tab **Activity** → pending confirmations + accepted/refused history with portfolio; Confirm / Dismiss without opening chat ([`ActivityScreen`](lib/features/activity/activity_screen.dart)). Shared confirm path: [`TradeProposalActions`](lib/data/trading/trade_proposal_actions.dart).
- Shell tab **Agents** → role cards; connect/edit/disconnect with suggested model presets + Autopilot for trading roles + optional **Schedule** (interval presets + symbols) for every role; **Open chat** when connected. Each role card shows a **Robustness N** badge (see above).
- **Schedule** (foreground only) — configured on Connect/Edit; [`AgentScheduleCoordinator`](lib/features/agents/agent_schedule_coordinator.dart) polls while the app is open and resumed (Linux / Windows / Android / iOS / macOS / Web). Pauses on background / hidden tab; does **not** run with the app closed. Each due tick Runs symbols via the same chat `sendRun` path (research or trade check + Autopilot if enabled). Activity logs `scheduledRun` events. Every scheduled outcome also enqueues a stacked shell notification ([`AppNotificationRepository`](lib/data/notifications/app_notification_repository.dart) / bell in [`HomeShell`](lib/features/shell/home_shell.dart)) so the user can **Open** Activity (when a `proposalId` is present) or chat to Confirm / review (Dismiss clears the inbox item).
- **In-app launches** — other screens deep-link into chat via [`AgentLaunchActions`](lib/features/agents/agent_launch_actions.dart) + [`AgentLaunchIntent`](lib/data/agents/agent_launch.dart) (`investigate` → Market Research; `tradeCheck` → Intraday; `explainLive` → Live Balance Explainer; `explainPortfolio` → Portfolio Guide; `paperReview` → Practice Coach). Shared CTA: [`AgentLaunchButton`](lib/widgets/agent_launch_button.dart).
  - Asset detail app bar **Investigate**; Practice trade card **Practice coach** + **Trade check**; successful paper trade offers a Trade check dialog.
  - Quote rows (Markets) sparkles icon → Investigate.
  - Portfolio practice holdings sparkles → Trade check.
  - Portfolio **Practice** summary **Allocation** / **Coach**; Portfolio **Live** **Balances** / **Allocation** + per-asset sparkles → Live Balance Explainer.
  - Settings → Portfolios Practice **Allocation** / **Coach**; live cards **Balances** / **Allocation** when credentials are ready.
  - Settings → Connections **Try Investigate** when a research-capable agent is connected (sample symbol from the default watchlist).
  - One connected applicable agent → open chat and auto-**Run** the symbol (or portfolio-level Run); several → picker dialog; none → switch to Agents tab and open **Connect** for the preferred role ([`ShellNavigationController.goToAgents`](lib/core/shell_navigation.dart)).
  - [`AgentChatScreen`](lib/features/agents/agent_chat_screen.dart) accepts `initialSymbol` / `initialExchangeId` / `autoRun` (and optional side/qty) for these launches.

### Roadmap (more agent surfaces)

When adding UI that involves a symbol, P&L decision, or “what does this mean?”, prefer wiring an `AgentLaunchIntent` CTA rather than a dead-end copy-only tip. Shipped: Settings → Connections **Try Investigate**, Asset detail chart period explainers, post-trade → Trade check dialog, Portfolio Live / Settings Portfolios balance explainers, Practice **Allocation** / **Coach**. Candidates still open: crypto spot primer, markets literacy tutor.

## User config file

Single JSON document for secrets, favorites, and all customizations ([`UserConfigStore`](lib/data/settings/user_config_store.dart)):

- **Default path (native):** `{getApplicationSupportDirectory()}/omniscope.json` via `path_provider`.
- **Custom path:** desktop only (Linux / Windows / macOS) — Settings → Data & privacy; override stored in prefs key `omniscope.config_path.v1`.
- **Web:** no filesystem path — full document in prefs blob `omniscope.config.v1`; Import / Export in Settings → Data & privacy.
- **Slices:** `theme`, `display`, `dataSources`, `secrets`, `agents`, `agentChats`, `tradeProposals`, `agentActivity`, `notifications`, `paperPortfolio`, `favorites`.
- **Legacy migration:** first load absorbs old per-feature prefs keys then removes them.
- **`.env` dual-write:** secrets still upsert into the project `.env` when writable (desktop checkout). On startup, non-empty `.env` / asset keys that are missing or empty in the config are **promoted** into `omniscope.json` so checkout edits persist for Flutter.
- Treat the file as secrets — it may contain API keys.

Favorites ([`FavoritesRepository`](lib/data/settings/favorites_repository.dart)): one ordered `symbols` list for equities and spot crypto; Markets sidebar has a single **Favorites** subgroup. Legacy `{ markets, crypto }` config slices migrate on load.

## Settings

Shell tab **Settings** (and Markets) use [`MasterDetailShell`](lib/widgets/master_detail_shell.dart): wide (≥720) = persistent sidebar + content pane; narrow = list → detail with Back. Switching sections unloads the previous body ([`settings_screen.dart`](lib/features/settings/settings_screen.dart)).

- **About** — tagline ([`AppCopy`](lib/core/app_copy.dart)), version ([`AppInfo`](lib/core/app_info.dart)), educational disclaimer.
- **Appearance** — brightness + color set ([`ThemeSettings`](lib/data/settings/theme_settings.dart) / [`BrandPalette`](lib/core/brand_colors.dart)), list density / price format / default chart range ([`DisplaySettings`](lib/data/settings/display_settings.dart)).
- **Data sources** — equities / crypto enable toggles + Crypto.com credentials (existing).
- **Portfolios** — practice starting cash / reset, plus status of live exchange portfolios (credentials under Data sources).
- **Connections** — LLM provider keys (red = missing, green = saved; Add/Edit via dialog; on-device only via [`EnvSecretsRepository.setLlmApiKey`](lib/data/settings/env_secrets_repository.dart)) plus a summary of exchange credentials and connected agents.
- **Data & privacy** — config path, desktop custom path, Import / Export JSON, plus clear favorites / chats / disconnect agents / reset paper / clear exchange credentials.

## Portfolio

- **Unified list** — [`PortfolioCatalog`](lib/data/portfolio/portfolio_catalog.dart) lists Practice plus each live exchange portfolio for Settings and the Portfolio tab.
- **Practice (paper)** — `paperPortfolio` slice in the unified config file. Manual trades on asset detail; agents may also Confirm / Autopilot into Practice when selected as the target portfolio.
  - Default starting cash: **$10,000** (`PortfolioState.defaultStartingCash`); configurable via Settings → Portfolios / `PortfolioRepository.startingCash` (stored in the same JSON blob).
  - Holdings: `{ symbol, shares, avgCost }`; buy averages cost; sell removes the row at zero shares.
  - Mark-to-market using `MarketDataClient.getQuotes` — never hard-code prices in the repository.
  - Reset restores configured starting cash and clears holdings (confirm in UI; does not touch live balances).
  - UI: secondary / muted chrome + **Paper** badge.
- **Live (exchange)** — when a registered `CryptoExchangeClient` has `canFetchPortfolio` (e.g. Crypto.com key+secret) and the venue is enabled in Settings, Portfolio’s master–detail sidebar adds another destination (`supportsLivePortfolio` marks venues that can unlock Live once credentials are set).
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

Canonical tokens live in [`lib/core/brand_colors.dart`](lib/core/brand_colors.dart) as selectable [`BrandPalette`](lib/core/brand_colors.dart)s (Teal default, Ocean, Forest, Slate, Amber), each with light **and** dark variants. [`ThemeSettings`](lib/data/settings/theme_settings.dart) stores palette id separately from ThemeMode. Wired into `ShadThemeData` in [`lib/app.dart`](lib/app.dart). **Every** new icon, image tint, border, shadow, fill, focus ring, and chart accent must use the active scheme — no one-off hex colors.

| Token | Use |
|-------|-----|
| **Primary / secondary / border** | Active palette via `colorScheme` (Settings → Appearance → Color set) |
| **Gain** | `#15803D` / `#4ADE80` — positive numbers only (fixed across palettes) |
| **Loss** | `#DC2626` / `#F87171` — negative numbers / `destructive` (fixed) |

- Prefer `theme.colorScheme.primary` / `.secondary` / `.border` / `.destructive`, or `BrandColors.gainOf` / `lossOf` / `shadowOf`.
- Do **not** use primary for P&L up/down — keep gain/loss distinct so numbers stay easy to read.
- Do not invent new accent hex in widgets — add a palette in `BrandColors` if a new set is needed.
- See also `.cursor/rules/brand-colors.mdc`.

### Product UX

- One clear job per screen (Markets master–detail with equity kinds + spot venues, Asset detail, Portfolio summary, Agents connect).
- Asset detail: curated overviews for default symbols ([`asset_overviews.dart`](lib/data/market/asset_overviews.dart)); external research links ([`market_data_links.dart`](lib/data/market/market_data_links.dart)): provider attribution plus Wikipedia (when mapped), Google Finance / TradingView; open via `url_launcher` in the system browser (educational only).
- Settings → About: tagline from [`app_copy.dart`](lib/core/app_copy.dart) plus educational disclaimer.
- Loading: `ShadProgress`. Errors: short message + retry.
- Trade feedback: `ShadToaster` + `ShadToast` (use `.destructive` for failures).
- Theme: slate neutrals + brand primary/secondary via `BrandColors` in `app.dart`.
- Keep copy plain — this product is for people who find finance intimidating.
- Shared brand mark: [`lib/widgets/app_placeholder_icon.dart`](lib/widgets/app_placeholder_icon.dart) in a compact shell header (uses [`assets/brand/app_icon.png`](assets/brand/app_icon.png)).
- Launcher / favicon / splash pipeline: edit masters under `assets/brand/`, then run `make icons` (or [`tool/regen_icons.sh`](tool/regen_icons.sh)) — Android / iOS / macOS / Web / Windows via `flutter_launcher_icons`, Linux `linux/runner/resources/`, plus Android / iOS / Web splash via `flutter_native_splash` (Teal `#CCFBF1` / `#134E4A`; desktop has no native splash).

## Commands

Root [`Makefile`](Makefile) is the developer catalog (`make help`). On Windows hosts, use Git Bash or WSL. Hooks still call `tool/*.sh` directly.

```bash
export PATH="$HOME/flutter/bin:$PATH"
make get
make check              # analyze + test (same as pre-push; excludes live_canary)
make venue-canary       # live Yahoo / Crypto.com / Alpaca probes (optional)
make run                # DEVICE=linux by default
make run DEVICE=windows # needs Windows desktop toolchain
make run DEVICE=android # needs Android SDK / device
make run DEVICE=ios     # needs Xcode / Apple toolchain (macOS host)
make run DEVICE=macos   # needs Xcode / macOS desktop toolchain
make run DEVICE=chrome  # Web (or edge / web-server)
make build              # host-capable release builds (skips other OS targets)
make build-linux        # or: build-windows / build-macos / build-ios / build-apk / build-appbundle / build-web
make icons
make agent-skills       # refresh Flutter/Dart/Genkit skills into .agents/skills/
make bump-patch         # local patch bump (pubspec + AppInfo); CI also runs this on main
make container-build    # podman: slim Linux runtime image (omniscope:runtime)
make container-run      # podman run (needs host DISPLAY)
# equivalents: flutter pub get | flutter analyze | flutter test
#              tool/flutter_checks.sh all | tool/regen_icons.sh
```

Release builds need the matching host toolchain (Linux/Windows/macOS desktop and iOS are not cross-compiled). See README **Release builds**.

### Podman (Linux runtime image)

[`Containerfile`](Containerfile) is a multi-stage build: Flutter + Linux **build** deps live only in a throwaway builder; the published tag is **`omniscope:runtime`** (GTK/EGL runtime libs + `build/linux/x64/release/bundle/`). Secrets are not baked in (builder uses `.env.example`).

```bash
make container-build    # podman build -t omniscope:runtime
make container-run      # needs DISPLAY + /tmp/.X11-unix
# CI also pushes ghcr.io/<owner>/omniscope on v* tags (see container.yml)
```

**Keep the Containerfile in sync:** whenever Linux OS packages (builder or runtime), Flutter install channel/flags used in the Containerfile, or the Linux bundle packaging path change, update [`Containerfile`](Containerfile) in the **same** change. Keep the README Fedora build list and CI `apt-get` Linux deps consistent with the builder stage. Do not leave the image definition stale.

### CI (GitHub Actions)

- **PR / `main`:** [`.github/workflows/ci.yml`](.github/workflows/ci.yml) — gitleaks + `tool/flutter_checks.sh all` (same gate as pre-push / `make check`), plus web and Linux desktop compile smoke on `ubuntu-latest`. Offline only — excludes `live_canary`.
- **Venue canary (scheduled):** [`.github/workflows/venue-canary.yml`](.github/workflows/venue-canary.yml) — daily + `workflow_dispatch`; live probes via Dart adapters; job may go red on outages without blocking merges. Optional repo secrets unlock portfolio probes.
- **Tags `v*` only:** [`.github/workflows/release.yml`](.github/workflows/release.yml) — build web / Linux / APK and publish a GitHub Release (not on every main merge).
- **Container (GHCR):** [`.github/workflows/container.yml`](.github/workflows/container.yml) — on `v*` tags (and `workflow_dispatch`), build [`Containerfile`](Containerfile) and push `ghcr.io/<owner>/<repo>` with `GITHUB_TOKEN` (`packages: write`). OCI `org.opencontainers.image.source` links the package to the repo.
- **Patch bump on `main`:** [`.github/workflows/bump-patch-version.yml`](.github/workflows/bump-patch-version.yml) — does not create tags. See README **CI** for the tag-and-release steps.

### Versioning

- [`pubspec.yaml`](pubspec.yaml): `MAJOR.MINOR.PATCH+BUILD` — **BUILD is always numeric** (Android `versionCode` / iOS build).
- [`AppInfo.version`](lib/core/app_info.dart) (Settings → About): `MAJOR.MINOR.PATCH+SHORTSHA` — same `X.Y.Z`, plus a 7-char commit suffix from `git rev-parse` (or `OMNISCOPE_VERSION_SHA` in CI).
- **Patch**: `make bump-patch` / [`tool/bump_patch_version.sh`](tool/bump_patch_version.sh) increments patch (+ numeric build) and rewrites AppInfo with the short SHA. CI runs this on every push to `main` ([`.github/workflows/bump-patch-version.yml`](.github/workflows/bump-patch-version.yml)), skipped when that push already edited the pubspec `version:` line.
- **Verify alignment**: `tool/bump_patch_version.sh --verify` (compares `X.Y.Z` only).
- **Major / minor**: edit `pubspec.yaml`, then run the bump script (or let CI bump) so AppInfo stays aligned — do not hand-edit AppInfo alone.

### Git hooks (pre-commit)

Install once: `make hooks` (or `pre-commit install --hook-type pre-commit --hook-type pre-push`)

- **pre-commit**: secret scan (gitleaks + private-key detect), merge-conflict / large-file checks
- **pre-push**: gitleaks + `flutter analyze` + `flutter test --exclude-tags live_canary` (via `tool/flutter_checks.sh`)

Do not commit `.env`, API keys, or credential JSON. Config: [`.pre-commit-config.yaml`](.pre-commit-config.yaml), [`.gitleaks.toml`](.gitleaks.toml).

Linux deps (Fedora): `clang`, `cmake`, `ninja-build`, `gtk3-devel`, `pkgconf-pkg-config`, etc. See README. The same build packages (and runtime GTK/EGL packages) must stay mirrored in [`Containerfile`](Containerfile) — see **Podman** above.

## When changing behavior

- Prefer extending `MarketDataClient` / `CryptoExchangeClient` over leaking provider details upward.
- Prefer new feature folders over dumping widgets into `main.dart`.
- Ship UX mobile-first and responsive (see **UI / UX norms** and `.cursor/rules/ux-mobile-first.mdc`).
- Keep **all** targets working: Linux, Windows, Android, iOS, macOS, Web (see `.cursor/rules/cross-platform.mdc`).
- Adhere to **Brand colors** (and `.cursor/rules/brand-colors.mdc`) for every visual token.
- Update README + this file when architecture or dependency rules change.
- If Linux build/runtime packages, Flutter channel/flags in the image, or the Linux bundle path change, update [`Containerfile`](Containerfile) in the same change (and keep README / CI package lists aligned).
