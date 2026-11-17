# Architecture

Agent handbook: [`AGENTS.md`](../AGENTS.md) (layout conventions, market data contracts, agents). Product overview: [`README.md`](../README.md).

## Layout

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
  data/agents/              # connections, chat threads, GenkitAgentRunner, catalog
  features/markets|crypto|asset_detail|portfolio|agents|shell/
  widgets/                  # chart + brand mark
assets/brand/               # master app icon (launchers + Android/iOS/Web splash)
assets/agents/              # manifest.json (roles) + llm_models.json
```

UI uses **[`shadcn_ui`](https://pub.dev/packages/shadcn_ui)** only (`ShadApp`). Charts are drawn with `CustomPaint` so no second UI kit is required.

Non-UI packages: `http`, `shared_preferences`, `intl`, `provider`.

## Market data (overview)

Equities / indices use **Yahoo Finance** chart endpoints (keyless, unofficial). Crypto uses a swappable [`CryptoExchangeClient`](../lib/data/crypto/crypto_exchange_client.dart) registry; **Crypto.com Exchange** public REST is registered first. Equity brokers (e.g. **Alpaca**) register via [`VenueCatalog`](../lib/data/venues/venue_catalog.dart) for Live portfolio + agent orders — not as Markets quote sources.

Optional venue API credentials: **Settings → Data sources → Credentials**. Market data is reached through [`RoutingMarketDataClient`](../lib/data/market/routing_market_data_client.dart). Secrets and other customizations share one **`omniscope.json`**.

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
- Linux window icons under [`linux/runner/resources/`](../linux/runner/resources/)
- [`flutter_native_splash`](https://pub.dev/packages/flutter_native_splash) — branded Teal splash for **Android, iOS, and Web** (including Android 12+). Desktop (Linux / Windows / macOS) has no native OS splash; window/launcher icons still come from the same masters.

[`lib/main.dart`](../lib/main.dart) keeps the native splash visible with `FlutterNativeSplash.preserve` until config/repos finish loading, then calls `remove` before `runApp`.

Selectable LLM models live in [`assets/agents/llm_models.json`](../assets/agents/llm_models.json); roles in [`assets/agents/manifest.json`](../assets/agents/manifest.json). In-app agents use Genkit Dart — see [`AGENTS.md`](../AGENTS.md).
