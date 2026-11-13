"""Harness prompts for Hedge Fund Desk LangGraph risk + head trader.

CLI / paper-educational only — not used by Flutter in-app chat.
Head Trader JSON shape must stay aligned with
`omniscope_agents.trade_schema` and Dart `TradeProposal.canonicalLlmKeys`.
"""

from __future__ import annotations

from typing import Mapping

from omniscope_agents.disclaimer import EDUCATIONAL_DISCLAIMER
from omniscope_agents.trade_schema import TRADE_JSON_EXAMPLE

RISK_MANAGER_SYSTEM = (
    "Omniscope educational Risk Manager. Hard constraints win. "
    "Plain language for learners."
)

HEAD_TRADER_SYSTEM = (
    "Omniscope Head Trader. Output valid JSON only. "
    "No broker routing — paper trade proposal only."
)


def risk_manager_human_prompt(state: Mapping[str, object], *, gates: Mapping[str, object], metrics: Mapping[str, object], price: float, proposed_side: str, proposed_qty: float) -> str:
    return (
        f"Symbol: {state.get('symbol')}\n"
        f"Live price: {price}\n"
        f"Proposed paper trade: {proposed_side} {proposed_qty}\n"
        f"Cash: {state.get('cash')} | Held: {state.get('held_shares')}\n"
        f"Realized vol: {metrics.get('realized_vol_annual')}\n"
        f"Hard gate result: risk_ok={gates['risk_ok']}\n"
        f"Gate notes: {gates['risk_notes']}\n\n"
        f"Debate packet:\n{state.get('debate_report') or ''}\n\n"
        "You are the Risk Manager with absolute veto power. "
        "In under 150 words, explain whether the hard gates allow a paper trade. "
        "Do not override a failed hard gate. "
        f"End with: '{EDUCATIONAL_DISCLAIMER}'"
    )


def head_trader_human_prompt(
    state: Mapping[str, object],
    *,
    price: float,
    cash: float,
    cap: float,
) -> str:
    return (
        f"Symbol: {state.get('symbol')}\n"
        f"Live price: {price}\n"
        f"Paper cash: {cash} | held shares: {state.get('held_shares')}\n"
        f"Risk Manager APPROVED. Max educational shares: {cap:g}\n"
        f"Risk notes: {state.get('risk_notes')}\n\n"
        f"Analyst packet:\n{state.get('analyst_report') or ''}\n\n"
        f"Debate:\n{state.get('debate_report') or ''}\n\n"
        "You are the Head Trader / Portfolio Manager for educational paper trading. "
        "Choose action buy, sell, or hold. Quantity must be an integer ≤ "
        f"{cap:g} for buys, and ≤ held shares for sells. "
        "Prefer smaller size when the bear case is strong. "
        "Respond with ONLY a JSON object:\n"
        f"{TRADE_JSON_EXAMPLE}\n"
        f"Rationale under 120 words. Mention {EDUCATIONAL_DISCLAIMER}."
    )


def reject_summary(state: Mapping[str, object]) -> str:
    return (
        f"Risk Manager VETO for {state.get('symbol')}.\n"
        f"{state.get('risk_narrative') or ''}\n"
        f"Notes: {state.get('risk_notes')}\n"
        f"{EDUCATIONAL_DISCLAIMER}"
    )


def head_trader_summary(trade: Mapping[str, object]) -> str:
    return (
        f"Head Trader paper proposal for {trade['ticker']}: "
        f"{trade['action']} {trade['quantity']}.\n"
        f"{trade.get('rationale')}\n{EDUCATIONAL_DISCLAIMER}"
    )
