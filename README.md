# Omniscope

Omniscope helps you **learn investing and manage personal finance** — browse markets, watch prices, practice with a local paper portfolio, and chat with optional AI helpers. Runs on **Linux**, **Windows**, **Android**, **iOS**, **macOS**, and **Web**. No accounts.

![Omniscope Markets — Favorites, Indices, ETFs, and Stocks](docs/screenshots/markets.png)

## Features

- **Markets** — Favorites, Indices, ETFs, Stocks, and enabled crypto exchanges (Spot pairs); star symbols; search curated tickers by name and open asset detail
- **Asset detail** — price, day change, short overview (default symbols), 1M / 3M / 1Y chart, agent Trade check / Review (no manual Buy/Sell), plus research links in your browser
- **Portfolio** — practice paper trading (default $10,000 starting cash, configurable, local holdings, P&L, reset) plus **Live** balances when credentials are set (Crypto.com, Alpaca, …)
- **Agents** — connect AI helpers with your own API key and model; chat stays on device; trading roles can Confirm into Practice or a live exchange
- **Settings** — appearance, data sources & credentials, practice cash, Agents (LLM keys Save/Test; shared memory & Schedule; expired keys are flagged, never auto-deleted), data & privacy (path/backup), and About
- **No accounts** — everything stays on device in one `omniscope.json` config (Web: browser storage + import/export)

## Quick start

```bash
cd /path/to/omniscope
make get
make run                 # DEVICE=linux by default; also: chrome / windows / android / ios / macos
make check               # analyze + test + linux release
```

Setup and toolchains: [`docs/development.md`](docs/development.md).

## Market data

Equities / indices: **Yahoo Finance** (keyless, unofficial). Crypto quotes: **Crypto.com Exchange**. Brokers such as **Alpaca** power Live portfolio and agent orders, not Markets quotes. Optional credentials live under **Settings → Data sources → Credentials** (stored in `omniscope.json`).

Data may be delayed; endpoints can change or rate-limit. For **educational / personal** use — check Yahoo’s, Crypto.com’s, and Alpaca’s terms before redistribution or commercial use.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Please follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security reports: [SECURITY.md](SECURITY.md).

## License / disclaimer

Released under the [MIT License](LICENSE).

**Use at your own risk.** Omniscope is educational software, not a brokerage or financial-advice product. Nothing in the app is investment, legal, or tax advice. You are solely responsible for any decisions you make. Authors and contributors accept no liability for losses, damages, or data issues arising from use of this software, market data, or third-party APIs.

Not financial advice. Paper trading is simulated. Market data ownership remains with the originating exchanges and Yahoo Finance. API keys and secrets stay on your device — protect them accordingly.
