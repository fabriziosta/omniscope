"""LangGraph trader for Intraday Execution & Risk Control.

This role always uses LangGraph — do not swap frameworks.
Paper-trading / educational only; no live brokerage.
"""

from __future__ import annotations

from typing import Any, Literal, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage
from langgraph.graph import END, StateGraph

from omniscope_agents.llm import Provider, build_chat_model
from omniscope_agents.trading.prompts import (
    RISK_NARRATOR_SYSTEM,
    summarize_human_prompt,
)

# Hard educational risk limits (paper portfolio defaults).
MAX_POSITION_PCT = 0.25
MAX_SHARES = 500.0
MIN_PRICE = 0.01


class TradeState(TypedDict, total=False):
    symbol: str
    side: Literal["buy", "sell"]
    qty: float
    price: float
    cash: float
    held_shares: float
    risk_ok: bool
    risk_notes: str
    decision: str
    summary: str


def _risk_check(state: TradeState) -> TradeState:
    qty = float(state.get("qty") or 0)
    price = float(state.get("price") or 0)
    cash = float(state.get("cash") or 0)
    held = float(state.get("held_shares") or 0)
    side = state.get("side") or "buy"
    notes: list[str] = []
    ok = True

    if qty <= 0:
        ok = False
        notes.append("Quantity must be positive.")
    if price < MIN_PRICE:
        ok = False
        notes.append("Price must be positive.")
    if qty > MAX_SHARES:
        ok = False
        notes.append(f"Quantity exceeds educational max of {MAX_SHARES:g} shares.")

    notional = qty * price
    if side == "buy":
        if notional > cash + 1e-9:
            ok = False
            notes.append("Not enough paper cash for this buy.")
        if cash > 0 and notional / cash > MAX_POSITION_PCT + 1e-9:
            ok = False
            notes.append(
                f"Buy exceeds {MAX_POSITION_PCT:.0%} of cash "
                "(educational position-size gate)."
            )
    elif side == "sell":
        if qty > held + 1e-9:
            ok = False
            notes.append("Not enough held shares to sell.")
    else:
        ok = False
        notes.append("Side must be buy or sell.")

    if ok:
        notes.append("Passed hard risk gates.")

    return {
        **state,
        "risk_ok": ok,
        "risk_notes": " ".join(notes),
    }


def _paper_decision(state: TradeState) -> TradeState:
    if not state.get("risk_ok"):
        return {
            **state,
            "decision": "reject",
        }
    return {
        **state,
        "decision": "accept_paper",
    }


def _make_summarize(llm: Any):
    def _summarize(state: TradeState) -> TradeState:
        response = llm.invoke(
            [
                SystemMessage(content=RISK_NARRATOR_SYSTEM),
                HumanMessage(content=summarize_human_prompt(state)),
            ]
        )
        content = getattr(response, "content", str(response))
        if isinstance(content, list):
            content = " ".join(str(part) for part in content)
        return {**state, "summary": str(content)}

    return _summarize


def build_trading_graph(
    *,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
):
    llm = build_chat_model(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )

    graph: StateGraph = StateGraph(TradeState)
    graph.add_node("risk_check", _risk_check)
    graph.add_node("paper_decision", _paper_decision)
    graph.add_node("summarize", _make_summarize(llm))
    graph.set_entry_point("risk_check")
    graph.add_edge("risk_check", "paper_decision")
    graph.add_edge("paper_decision", "summarize")
    graph.add_edge("summarize", END)
    return graph.compile()


def run_trading_check(
    *,
    symbol: str,
    side: Literal["buy", "sell"],
    qty: float,
    price: float,
    cash: float,
    held_shares: float = 0.0,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
) -> TradeState:
    app = build_trading_graph(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    initial: TradeState = {
        "symbol": symbol.strip().upper(),
        "side": side,
        "qty": qty,
        "price": price,
        "cash": cash,
        "held_shares": held_shares,
    }
    return app.invoke(initial)  # type: ignore[return-value]
