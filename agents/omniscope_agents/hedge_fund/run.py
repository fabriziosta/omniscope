"""CLI: Hedge Fund Desk (LangGraph orchestration + CrewAI stages)."""

from __future__ import annotations

import argparse
import json
from typing import Any

from omniscope_agents.hedge_fund.analysts.crew import (
    gather_analyst_packets,
    run_analyst_team,
    run_single_analyst,
)
from omniscope_agents.hedge_fund.graph import run_hedge_fund_desk
from omniscope_agents.hedge_fund.research.crew import (
    run_research_debate,
    run_single_researcher,
)
from omniscope_agents.hedge_fund.tools.fundamentals import (
    fetch_fundamentals_snapshot,
    format_fundamentals_report,
)
from omniscope_agents.hedge_fund.tools.news_sentiment import (
    fetch_news_sentiment,
    format_news_report,
)
from omniscope_agents.hedge_fund.tools.risk_metrics import (
    compute_risk_metrics,
    format_risk_report,
)
from omniscope_agents.hedge_fund.tools.technicals import (
    compute_technicals,
    format_technicals_report,
)
from omniscope_agents.llm import add_llm_args

_STAGES = (
    "all",
    "technical",
    "sentiment",
    "fundamental",
    "analysts",
    "bull",
    "bear",
    "debate",
    "risk",
    "trader",
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Omniscope Hedge Fund Desk — 7-role paper pipeline on live "
            "public data (LangGraph + CrewAI)."
        ),
    )
    parser.add_argument("--symbol", required=True, help="Equity ticker")
    parser.add_argument("--cash", type=float, default=10000.0)
    parser.add_argument("--held-shares", type=float, default=0.0)
    parser.add_argument(
        "--stage",
        choices=_STAGES,
        default="all",
        help="Run full desk (all) or a single stage",
    )
    add_llm_args(parser)
    args = parser.parse_args()

    symbol = args.symbol.strip().upper()
    llm_kwargs: dict[str, Any] = {
        "provider": args.provider,
        "model": args.model,
        "api_key": args.api_key,
        "base_url": args.base_url,
    }

    if args.stage == "all" or args.stage == "trader":
        result = run_hedge_fund_desk(
            symbol=symbol,
            cash=args.cash,
            held_shares=args.held_shares,
            **llm_kwargs,
        )
        print(result.get("summary") or "")
        print("---")
        print(
            json.dumps(
                {
                    "decision": result.get("decision"),
                    "risk_ok": result.get("risk_ok"),
                    "risk_notes": result.get("risk_notes"),
                    "trade": result.get("trade"),
                    "price": result.get("price"),
                },
                indent=2,
            )
        )
        return

    if args.stage in ("technical", "sentiment", "fundamental"):
        if args.stage == "technical":
            print(format_technicals_report(compute_technicals(symbol)))
            print("---")
        elif args.stage == "sentiment":
            print(format_news_report(fetch_news_sentiment(symbol)))
            print("---")
        else:
            print(format_fundamentals_report(fetch_fundamentals_snapshot(symbol)))
            print("---")
        print(run_single_analyst(args.stage, symbol, **llm_kwargs))
        return

    if args.stage == "analysts":
        out = run_analyst_team(symbol, **llm_kwargs)
        print(out["combined_report"])
        return

    if args.stage in ("bull", "bear", "debate"):
        packets = gather_analyst_packets(symbol)
        analyst_packet = (
            f"{packets['technical']}\n\n"
            f"{packets['sentiment']}\n\n"
            f"{packets['fundamental']}"
        )
        # For debate stages without full analyst LLM cost, use raw packets;
        # optional enrichment via --stage analysts first.
        if args.stage == "debate":
            # Light path: use data packets as the analyst input for debate.
            out = run_research_debate(symbol, analyst_packet, **llm_kwargs)
            print(out["debate_report"])
            return
        print(
            run_single_researcher(
                args.stage,
                symbol,
                analyst_packet,
                **llm_kwargs,
            )
        )
        return

    if args.stage == "risk":
        metrics = compute_risk_metrics(
            symbol,
            cash=args.cash,
            held_shares=args.held_shares,
        )
        print(format_risk_report(metrics))
        print("---")
        print(
            json.dumps(
                {
                    "risk_ok": metrics.get("risk_ok"),
                    "risk_notes": metrics.get("risk_notes"),
                    "price": metrics.get("price"),
                    "proposed_side": metrics.get("proposed_side"),
                    "proposed_qty": metrics.get("proposed_qty"),
                    "realized_vol_annual": metrics.get("realized_vol_annual"),
                },
                indent=2,
            )
        )
        return


if __name__ == "__main__":
    main()
