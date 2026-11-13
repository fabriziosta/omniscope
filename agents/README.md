# Omniscope agents (Python)

Educational CLI agents for Omniscope. Frameworks are fixed by role.

Available roles (and model presets) live in [`omniscope_agents/manifest.json`](omniscope_agents/manifest.json). Flutter’s Agents tab loads that file as an asset — **add a new package under `omniscope_agents/` and register it in the manifest** so it appears in the app.

| Role | Framework | Workload | Suggested models |
|------|-----------|----------|------------------|
| Market Research & Analysis | **CrewAI** | Investigation | Lighter (e.g. `gpt-6-luna`, `deepseek-flash`) |
| Live Balance Explainer | **CrewAI** | Investigation | Lighter (e.g. `gpt-6-luna`, `deepseek-flash`) |
| Portfolio & Allocation Guide | **CrewAI** | Investigation | Lighter (e.g. `gpt-6-luna`, `deepseek-flash`) |
| Practice Portfolio Coach | **CrewAI** | Investigation | Lighter (e.g. `gpt-6-luna`, `deepseek-flash`) |
| Intraday Execution & Risk Control | **LangGraph** | Trading | Heavier (e.g. `gpt-6-astra`, `grok-4.7`) |
| Hedge Fund Desk | **LangGraph** (CrewAI for analyst/debate stages) | Trading | Heavier (e.g. `gpt-6-astra`, `grok-4.7`) |

Flutter stores API keys and model choices locally; this package runs the agents from the command line today.

### Prompt source of truth

Do **not** put Flutter + CLI prompts in one mega JSON. Layers:

| Layer | Location | Notes |
|-------|----------|-------|
| Role catalog | [`omniscope_agents/manifest.json`](omniscope_agents/manifest.json) | Metadata only |
| In-app chat | Flutter `lib/data/agents/agent_role_prompts.dart` | Live exchange; not used here |
| CLI harness | Per-package `prompts.py` (+ shared [`disclaimer.py`](omniscope_agents/disclaimer.py)) | Paper / educational |
| Trade JSON keys | [`trade_schema.py`](omniscope_agents/trade_schema.py) | Shared field names only (`ticker`, `action`, `quantity`, `rationale`, `risk_approved`) |

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

## Live balance explainer (CrewAI)

Prefer in-app chat (Portfolio Live / Settings → Portfolios injects live balances). CLI accepts a pasted snapshot:

```bash
python -m omniscope_agents.live_balance.run \
  --snapshot $'Live exchange context...\n- Total value: $1000\n- BTC: qty 0.1' \
  --provider openai \
  --model gpt-6-luna
```

## Portfolio & allocation guide (CrewAI)

Prefer in-app chat (Practice / Live **Allocation** CTAs). CLI:

```bash
python -m omniscope_agents.portfolio_guide.run \
  --snapshot $'Practice portfolio...\n- Cash: $5000\n- AAPL: qty 10' \
  --provider openai \
  --model gpt-6-luna
```

## Practice portfolio coach (CrewAI)

Prefer in-app chat (Practice **Coach** CTA). CLI:

```bash
python -m omniscope_agents.paper_portfolio.run \
  --snapshot $'Practice portfolio...\n- Cash: $5000\n- AAPL: qty 10' \
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
