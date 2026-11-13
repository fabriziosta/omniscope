"""CLI: Portfolio & Allocation Guide (CrewAI). Prefer in-app chat."""

from __future__ import annotations

import argparse
import sys

from omniscope_agents.llm import add_llm_args
from omniscope_agents.portfolio_guide.crew import run_portfolio_guide


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Omniscope Portfolio & Allocation Guide (CrewAI). "
            "Pass a portfolio snapshot via --snapshot or stdin."
        ),
    )
    parser.add_argument(
        "--snapshot",
        help="Plain-text portfolio snapshot (or pass on stdin)",
    )
    parser.add_argument(
        "--symbol",
        help="Optional symbol to focus on",
    )
    add_llm_args(parser)
    args = parser.parse_args()

    snapshot = (args.snapshot or "").strip()
    if not snapshot and not sys.stdin.isatty():
        snapshot = sys.stdin.read().strip()
    if not snapshot:
        parser.error(
            "Provide --snapshot or pipe a portfolio snapshot on stdin "
            "(in-app chat injects Practice / Live context automatically).",
        )

    brief = run_portfolio_guide(
        snapshot,
        provider=args.provider,
        model=args.model,
        symbol_hint=args.symbol,
        api_key=args.api_key,
        base_url=args.base_url,
    )
    print(brief)


if __name__ == "__main__":
    main()
