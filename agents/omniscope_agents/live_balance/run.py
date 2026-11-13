"""CLI: Live Balance Explainer (CrewAI). Prefer in-app chat for live snapshots."""

from __future__ import annotations

import argparse
import sys

from omniscope_agents.live_balance.crew import run_live_balance_explainer
from omniscope_agents.llm import add_llm_args


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Omniscope Live Balance Explainer (CrewAI). "
            "Pass a balance snapshot via --snapshot or stdin."
        ),
    )
    parser.add_argument(
        "--snapshot",
        help="Plain-text live balance snapshot (or pass on stdin)",
    )
    parser.add_argument(
        "--asset",
        help="Optional asset to focus on (e.g. BTC, USD)",
    )
    add_llm_args(parser)
    args = parser.parse_args()

    snapshot = (args.snapshot or "").strip()
    if not snapshot and not sys.stdin.isatty():
        snapshot = sys.stdin.read().strip()
    if not snapshot:
        parser.error(
            "Provide --snapshot or pipe a balance snapshot on stdin "
            "(in-app chat injects live balances automatically).",
        )

    brief = run_live_balance_explainer(
        snapshot,
        provider=args.provider,
        model=args.model,
        asset_hint=args.asset,
        api_key=args.api_key,
        base_url=args.base_url,
    )
    print(brief)


if __name__ == "__main__":
    main()
