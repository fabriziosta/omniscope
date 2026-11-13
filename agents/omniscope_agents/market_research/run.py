"""CLI: Market Research & Analysis (CrewAI)."""

from __future__ import annotations

import argparse

from omniscope_agents.llm import add_llm_args
from omniscope_agents.market_research.crew import run_market_research


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Omniscope Market Research & Analysis (CrewAI)",
    )
    parser.add_argument("--symbol", required=True, help="Ticker or topic")
    add_llm_args(parser)
    args = parser.parse_args()

    brief = run_market_research(
        args.symbol,
        provider=args.provider,
        model=args.model,
        api_key=args.api_key,
        base_url=args.base_url,
    )
    print(brief)


if __name__ == "__main__":
    main()
