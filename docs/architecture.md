# Architecture

Agent handbook: [`AGENTS.md`](../AGENTS.md) (layout conventions, market data contracts, agents). Product overview: [`README.md`](../README.md).

## Layout

```text
lib/
  main.dart                 # DI: market router + venues + portfolio + agents
  app.dart                  # ShadApp theme shell
  core/                     # formatting, brand colors, shell navigation
  data/market/              # MarketDataClient, Yahoo, caching, routing
  data/crypto/              # CryptoExchangeClient + Crypto.com adapter
  data/brokers/             # Alpaca (+ future equity brokers)
  data/venues/              # VenueCatalog, shared live portfolio models
  data/trading/             # TradeExecutor, proposal actions, broker registry
  data/portfolio/           # practice paper portfolio (omniscope.json slice)
  data/agents/              # chats, Genkit runner/tools, catalog, proposals
  data/settings/            # UserConfigStore + favorites / theme / secrets
  data/notifications/       # Activity → Alerts
  features/markets|crypto|asset_detail|portfolio|agents|activity|shell|settings|quotes/
  widgets/                  # chart, master–detail shell, shared chrome
assets/brand/               # master app icon (launchers + Android/iOS/Web splash)
assets/agents/              # manifest.json (roles) + llm_models.json
```

UI uses **[`shadcn_ui`](https://pub.dev/packages/shadcn_ui)** only (`ShadApp`). Charts are drawn with `CustomPaint` so no second UI kit is required.

Non-UI packages: `http`, `shared_preferences`, `path_provider`, `intl`, `provider`, Genkit stack.

## Market data (overview)

Equities / indices use **Yahoo Finance** chart endpoints (keyless, unofficial). Crypto uses a swappable [`CryptoExchangeClient`](../lib/data/crypto/crypto_exchange_client.dart) registry; **Crypto.com Exchange** public REST is registered first. Equity brokers (e.g. **Alpaca**) register via [`VenueCatalog`](../lib/data/venues/venue_catalog.dart) for Live portfolio + agent orders — not as Markets quote sources.

Optional venue API credentials: **Settings → Data sources → Credentials**. Market data is reached through [`RoutingMarketDataClient`](../lib/data/market/routing_market_data_client.dart). Secrets and other customizations share one **`omniscope.json`** via [`UserConfigStore`](../lib/data/settings/user_config_store.dart) (`path_provider` on native; prefs blob on Web). Practice portfolio holdings live in the same document’s `paperPortfolio` slice — not a separate SharedPreferences key.

- Data may be delayed; endpoints can change or rate-limit without notice.
- **Web:** Yahoo’s chart host omits CORS headers; equities on Web go through a public GET proxy inside [`YahooMarketDataClient`](../lib/data/market/yahoo_market_data_client.dart). Native targets call Yahoo directly. Private broker APIs may be blocked by CORS on Web.
- Educational / personal use in this POC; check provider terms before redistribution or commercial use.

To add providers or venues, follow the steps in [`AGENTS.md`](../AGENTS.md) (**Market data**, **Crypto exchanges**). Document user-facing keys, rate limits, and terms in [`README.md`](../README.md) **Market data**.

## App icon and splash

Master art lives in [`assets/brand/app_icon.png`](../assets/brand/app_icon.png) (adaptive foreground: [`app_icon_foreground.png`](../assets/brand/app_icon_foreground.png)). After editing the masters, regenerate launchers and splash:

```bash
make icons
# or: tool/regen_icons.sh
```

That runs:

- [`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons) — Android / iOS / macOS / Web / Windows icons (config in [`pubspec.yaml`](../pubspec.yaml))
- Linux window icons under [`linux/runner/resources/`](../linux/runner/resources/) (Python 3 + Pillow; see [`docs/development.md`](development.md))
- [`flutter_native_splash`](https://pub.dev/packages/flutter_native_splash) — branded Teal splash for **Android, iOS, and Web** (including Android 12+). Desktop (Linux / Windows / macOS) has no native OS splash; window/launcher icons still come from the same masters.

[`lib/main.dart`](../lib/main.dart) keeps the native splash visible with `FlutterNativeSplash.preserve` until config/repos finish loading, then calls `remove` before `runApp`.

## Home tab

Cold start opens the **Portfolio** bottom tab ([`ShellNavigationController.homeTabIndex`](../lib/core/shell_navigation.dart) / `goToHome()`), which hosts [`PortfolioScreen`](../lib/features/portfolio/portfolio_screen.dart) (practice + live balances). Tab order: Portfolio → Markets → Activity → Agents → Settings.

Selectable LLM models live in [`assets/agents/llm_models.json`](../assets/agents/llm_models.json); roles in [`assets/agents/manifest.json`](../assets/agents/manifest.json). In-app agents use Genkit Dart — see [`AGENTS.md`](../AGENTS.md).
