# Omniscope agents (Python)

Educational CLI agents for Omniscope. Frameworks are fixed by role.

Available roles (and model presets) live in [`omniscope_agents/manifest.json`](omniscope_agents/manifest.json). Flutter’s Agents tab loads that file as an asset — **add a new package under `omniscope_agents/` and register it in the manifest** so it appears in the app.

| Role | Framework | Workload | Suggested models |
|------|-----------|----------|------------------|
| Market Research & Analysis | **CrewAI** | Investigation | Lighter (e.g. `gpt-6-luna`, `deepseek-flash`) |
| Intraday Execution & Risk Control | **LangGraph** | Trading | Heavier (e.g. `gpt-6-astra`, `grok-4.7`) |
| Hedge Fund Desk | **LangGraph** (CrewAI for analyst/debate stages) | Trading | Heavier (e.g. `gpt-6-astra`, `grok-4.7`) |

Flutter stores API keys and model choices locally; this package runs the agents from the command line today.

## Setup

```bash
cd agents
python -m venv .venv
source .venv/bin/activate
pip install -e .
```

Set a key (or pass `--api-key`). Prefer a provider-specific var from the repo-root
[`.env.example`](../.env.example) (copy to `.env` and `set -a; source .env; set +a`):

```bash
export OMNISCOPE_OPENAI_API_KEY='...'   # or GEMINI / ANTHROPIC / DEEPSEEK / GROK / CUSTOM
# fallback for any provider:
export OMNISCOPE_API_KEY='...'
```

## Market research (CrewAI)

```bash
python -m omniscope_agents.market_research.run \
  --symbol AAPL \
  --provider openai \
  --model gpt-6-luna
```

## Intraday trader (LangGraph)

```bash
python -m omniscope_agents.trading.run \
  --symbol AAPL \
  --side buy \
  --qty 10 \
  --price 190 \
  --cash 10000 \
  --provider openai \
  --model gpt-6-luna
```

## Hedge Fund Desk (LangGraph + CrewAI)

Seven-role paper pipeline on **live public data** (yfinance, pandas-ta, EDGAR via edgartools, public RSS). No X/Twitter, Bloomberg, or Reuters terminals. Output is educational JSON — not a broker order.

```bash
# Full desk: analysts → bull/bear debate → risk veto → head trader
python -m omniscope_agents.hedge_fund.run \
  --symbol AAPL \
  --cash 10000 \
  --provider openai \
  --model gpt-6-astra

# Single stage (debug)
python -m omniscope_agents.hedge_fund.run --symbol AAPL --stage technical \
  --provider openai --model gpt-6-astra
python -m omniscope_agents.hedge_fund.run --symbol AAPL --stage risk \
  --cash 10000 --provider openai --model gpt-6-astra
```

`--stage` values: `all`, `technical`, `sentiment`, `fundamental`, `analysts`, `bull`, `bear`, `debate`, `risk`, `trader`.

Providers: `gemini`, `openai`, `anthropic`, `deepseek`, `grok`, `custom` (requires `--base-url`).

Examples:

```bash
# DeepSeek
python -m omniscope_agents.market_research.run \
  --symbol AAPL --provider deepseek --model deepseek-flash --api-key "$DEEPSEEK_API_KEY"

# Grok (xAI)
python -m omniscope_agents.trading.run \
  --symbol AAPL --side buy --qty 5 --price 190 \
  --provider grok --model grok-4.7 --api-key "$XAI_API_KEY"
```

Model IDs should match [`../assets/agents/llm_models.json`](../assets/agents/llm_models.json) for catalog providers.
