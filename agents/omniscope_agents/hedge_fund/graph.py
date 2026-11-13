"""LangGraph Hedge Fund Desk: orchestrates analysts → debate → risk → trader.

Public role framework is LangGraph (trading workload). Stages 1–2 invoke
CrewAI crews. Paper-trading / educational only — no live brokerage.
"""

from __future__ import annotations

import json
import math
import re
from typing import Any, Literal, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage
from langgraph.graph import END, StateGraph

from omniscope_agents.hedge_fund.analysts.crew import run_analyst_team
from omniscope_agents.hedge_fund.research.crew import run_research_debate
from omniscope_agents.hedge_fund.tools.risk_metrics import (
    MAX_POSITION_PCT,
    MAX_SHARES,
    compute_risk_metrics,
    evaluate_risk_gates,
)
from omniscope_agents.llm import Provider, build_chat_model

_DISCLAIMER = "Not financial advice — educational paper trading only."


class DeskState(TypedDict, total=False):
    symbol: str
    cash: float
    held_shares: float
    analyst_report: str
    technical_report: str
    sentiment_report: str
    fundamental_report: str
    bull_report: str
    bear_report: str
    debate_report: str
    price: float
    proposed_side: str
    proposed_qty: float
    realized_vol_annual: float
    risk_ok: bool
    risk_notes: str
    risk_narrative: str
    decision: str
    trade: dict[str, Any]
    summary: str
    # LLM wiring threaded through nodes
    _provider: str
    _model: str
    _api_key: str
    _base_url: str


def _llm_kwargs(state: DeskState) -> dict[str, Any]:
    return {
        "provider": state["_provider"],  # type: ignore[arg-type]
        "model": state["_model"],
        "api_key": state.get("_api_key") or None,
        "base_url": state.get("_base_url") or None,
    }


def _analysts_node(state: DeskState) -> DeskState:
    result = run_analyst_team(state["symbol"], **_llm_kwargs(state))
    return {
        **state,
        "technical_report": result["technical_report"],
        "sentiment_report": result["sentiment_report"],
        "fundamental_report": result["fundamental_report"],
        "analyst_report": result["combined_report"],
    }


def _debate_node(state: DeskState) -> DeskState:
    result = run_research_debate(
        state["symbol"],
        state.get("analyst_report") or "",
        **_llm_kwargs(state),
    )
    return {
        **state,
        "bull_report": result["bull_report"],
        "bear_report": result["bear_report"],
        "debate_report": result["debate_report"],
    }


def _risk_manager_node(state: DeskState) -> DeskState:
    """Deterministic gates first; LLM narrative; absolute veto on failure."""
    metrics = compute_risk_metrics(
        state["symbol"],
        cash=float(state.get("cash") or 0),
        held_shares=float(state.get("held_shares") or 0),
        proposed_side="buy",
        proposed_qty=None,
    )
    price = float(metrics.get("price") or 0)
    proposed_qty = float(metrics.get("proposed_qty") or 0)
    proposed_side = str(metrics.get("proposed_side") or "buy")

    # Let the debate lean nudge side: if bear is much longer / stronger signals,
    # keep buy sizing but allow hold (qty 0) when risk metrics already failed.
    gates = evaluate_risk_gates(
        side=proposed_side,
        qty=proposed_qty,
        price=price,
        cash=float(state.get("cash") or 0),
        held_shares=float(state.get("held_shares") or 0),
        realized_vol=metrics.get("realized_vol_annual"),
    )

    # If data missing, veto.
    if not metrics.get("ok") or price <= 0:
        gates = {
            "risk_ok": False,
            "risk_notes": (
                metrics.get("error")
                or gates["risk_notes"]
                or "Live price unavailable — Risk Manager veto."
            ),
        }

    llm = build_chat_model(**_llm_kwargs(state))
    prompt = (
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
        f"End with: '{_DISCLAIMER}'"
    )
    response = llm.invoke(
        [
            SystemMessage(
                content=(
                    "Omniscope educational Risk Manager. Hard constraints win. "
                    "Plain language for learners."
                )
            ),
            HumanMessage(content=prompt),
        ]
    )
    narrative = _content_to_str(response)

    risk_ok = bool(gates["risk_ok"]) and proposed_qty > 0
    if proposed_qty <= 0 and gates["risk_ok"]:
        risk_ok = False
        gates = {
            "risk_ok": False,
            "risk_notes": (
                gates["risk_notes"]
                + " Proposed quantity is zero — nothing to execute."
            ),
        }

    return {
        **state,
        "price": price,
        "proposed_side": proposed_side,
        "proposed_qty": proposed_qty,
        "realized_vol_annual": float(metrics.get("realized_vol_annual") or 0),
        "risk_ok": risk_ok,
        "risk_notes": gates["risk_notes"],
        "risk_narrative": narrative,
        "decision": "approve" if risk_ok else "reject",
    }


def _reject_node(state: DeskState) -> DeskState:
    trade = {
        "ticker": state.get("symbol"),
        "action": "hold",
        "quantity": 0,
        "rationale": state.get("risk_notes") or "Risk Manager veto.",
        "risk_approved": False,
        "disclaimer": _DISCLAIMER,
    }
    summary = (
        f"Risk Manager VETO for {state.get('symbol')}.\n"
        f"{state.get('risk_narrative') or ''}\n"
        f"Notes: {state.get('risk_notes')}\n"
        f"{_DISCLAIMER}"
    )
    return {
        **state,
        "decision": "reject",
        "trade": trade,
        "summary": summary,
    }


def _head_trader_node(state: DeskState) -> DeskState:
    """Final decision-maker — only reached when Risk Manager approved."""
    llm = build_chat_model(**_llm_kwargs(state))
    max_qty = float(state.get("proposed_qty") or 0)
    price = float(state.get("price") or 0)
    cash = float(state.get("cash") or 0)
    # Cap again inside the prompt budget.
    budget_shares = 0.0
    if price > 0 and cash > 0:
        budget_shares = min(MAX_SHARES, (cash * MAX_POSITION_PCT) / price)
    cap = max(0.0, math.floor(min(max_qty, budget_shares)))

    prompt = (
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
        '{"ticker":"...","action":"buy|sell|hold","quantity":0,'
        '"rationale":"...","risk_approved":true}\n'
        f"Rationale under 120 words. Mention {_DISCLAIMER}."
    )
    response = llm.invoke(
        [
            SystemMessage(
                content=(
                    "Omniscope Head Trader. Output valid JSON only. "
                    "No broker routing — paper trade proposal only."
                )
            ),
            HumanMessage(content=prompt),
        ]
    )
    raw = _content_to_str(response)
    trade = _parse_trade_json(raw, fallback_symbol=str(state.get("symbol") or ""))
    trade["risk_approved"] = True
    trade["disclaimer"] = _DISCLAIMER

    # Enforce hard caps post-LLM.
    action = str(trade.get("action") or "hold").lower()
    qty = float(trade.get("quantity") or 0)
    if action == "buy":
        qty = max(0.0, min(qty, cap))
        if qty <= 0:
            action = "hold"
            qty = 0.0
    elif action == "sell":
        held = float(state.get("held_shares") or 0)
        qty = max(0.0, min(qty, held))
        if qty <= 0:
            action = "hold"
            qty = 0.0
    else:
        action = "hold"
        qty = 0.0

    trade["action"] = action
    trade["quantity"] = int(qty) if qty == int(qty) else qty
    trade["ticker"] = str(state.get("symbol") or trade.get("ticker") or "").upper()

    decision = "accept_paper"
    if action != "hold":
        gates = evaluate_risk_gates(
            side=action,
            qty=float(qty),
            price=price,
            cash=cash,
            held_shares=float(state.get("held_shares") or 0),
            realized_vol=state.get("realized_vol_annual"),
        )
        if not gates["risk_ok"]:
            trade = {
                "ticker": trade["ticker"],
                "action": "hold",
                "quantity": 0,
                "rationale": (
                    f"Post-check veto: {gates['risk_notes']} "
                    f"Original rationale: {trade.get('rationale')}"
                ),
                "risk_approved": False,
                "disclaimer": _DISCLAIMER,
            }
            decision = "reject"

    summary = (
        f"Head Trader paper proposal for {trade['ticker']}: "
        f"{trade['action']} {trade['quantity']}.\n"
        f"{trade.get('rationale')}\n{_DISCLAIMER}"
    )
    return {
        **state,
        "decision": decision,
        "trade": trade,
        "summary": summary,
        "risk_ok": trade.get("risk_approved", False),
        "risk_notes": state.get("risk_notes") or "",
    }


def _route_after_risk(state: DeskState) -> Literal["head_trader", "reject"]:
    if state.get("risk_ok"):
        return "head_trader"
    return "reject"


def build_desk_graph(
    *,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
):
    # provider/model are applied per-invoke via state; builders kept for API symmetry.
    _ = (provider, model, api_key, base_url)

    graph: StateGraph = StateGraph(DeskState)
    graph.add_node("analysts", _analysts_node)
    graph.add_node("debate", _debate_node)
    graph.add_node("risk_manager", _risk_manager_node)
    graph.add_node("head_trader", _head_trader_node)
    graph.add_node("reject", _reject_node)
    graph.set_entry_point("analysts")
    graph.add_edge("analysts", "debate")
    graph.add_edge("debate", "risk_manager")
    graph.add_conditional_edges(
        "risk_manager",
        _route_after_risk,
        {
            "head_trader": "head_trader",
            "reject": "reject",
        },
    )
    graph.add_edge("head_trader", END)
    graph.add_edge("reject", END)
    return graph.compile()


def run_hedge_fund_desk(
    *,
    symbol: str,
    cash: float = 10000.0,
    held_shares: float = 0.0,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
) -> DeskState:
    app = build_desk_graph(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    initial: DeskState = {
        "symbol": symbol.strip().upper(),
        "cash": float(cash),
        "held_shares": float(held_shares),
        "_provider": provider,
        "_model": model,
        "_api_key": api_key or "",
        "_base_url": base_url or "",
    }
    return app.invoke(initial)  # type: ignore[return-value]


def _content_to_str(response: Any) -> str:
    content = getattr(response, "content", str(response))
    if isinstance(content, list):
        content = " ".join(str(part) for part in content)
    return str(content)


def _parse_trade_json(raw: str, *, fallback_symbol: str) -> dict[str, Any]:
    text = raw.strip()
    # Strip markdown fences if present.
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if fence:
        text = fence.group(1)
    else:
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if match:
            text = match.group(0)
    try:
        data = json.loads(text)
        if isinstance(data, dict):
            return {
                "ticker": str(data.get("ticker") or fallback_symbol).upper(),
                "action": str(data.get("action") or "hold").lower(),
                "quantity": data.get("quantity") or 0,
                "rationale": str(data.get("rationale") or raw[:500]),
                "risk_approved": bool(data.get("risk_approved", True)),
            }
    except json.JSONDecodeError:
        pass
    return {
        "ticker": fallback_symbol.upper(),
        "action": "hold",
        "quantity": 0,
        "rationale": f"Could not parse trader JSON. Raw: {raw[:400]}",
        "risk_approved": False,
    }
