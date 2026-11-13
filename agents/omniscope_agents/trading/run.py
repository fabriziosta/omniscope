"""CLI: Intraday Execution & Risk Control (LangGraph)."""

from __future__ import annotations

import argparse
import json

from omniscope_agents.llm import add_llm_args
from omniscope_agents.trading.graph import run_trading_check


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Omniscope Intraday Execution & Risk Control (LangGraph)",
    )
    parser.add_argument("--symbol", required=True)
    parser.add_argument("--side", choices=["buy", "sell"], required=True)
    parser.add_argument("--qty", type=float, required=True)
    parser.add_argument("--price", type=float, required=True)
    parser.add_argument("--cash", type=float, default=10000.0)
    parser.add_argument("--held-shares", type=float, default=0.0)
    add_llm_args(parser)
    args = parser.parse_args()

    result = run_trading_check(
        symbol=args.symbol,
        side=args.side,
        qty=args.qty,
        price=args.price,
        cash=args.cash,
        held_shares=args.held_shares,
        provider=args.provider,
        model=args.model,
        api_key=args.api_key,
        base_url=args.base_url,
    )
    print(result.get("summary") or "")
    print("---")
    print(
        json.dumps(
            {
                "decision": result.get("decision"),
                "risk_ok": result.get("risk_ok"),
                "risk_notes": result.get("risk_notes"),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
