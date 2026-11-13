"""Risk helpers: live price, realized vol, educational exposure gates."""

from __future__ import annotations

import math
from typing import Any

from omniscope_agents.hedge_fund.tools.market_data import fetch_ohlcv, fetch_quote

# Align with omniscope_agents.trading.graph educational defaults.
MAX_POSITION_PCT = 0.25
MAX_SHARES = 500.0
MIN_PRICE = 0.01
# Annualized realized-vol above this flags a volatility veto for paper buys.
MAX_REALIZED_VOL = 0.85


def compute_risk_metrics(
    symbol: str,
    *,
    cash: float,
    held_shares: float,
    proposed_side: str = "buy",
    proposed_qty: float | None = None,
) -> dict[str, Any]:
    """Build a risk packet from live data + paper portfolio constraints."""
    symbol = symbol.strip().upper()
    quote = fetch_quote(symbol)
    ohlcv = fetch_ohlcv(symbol, period="3mo", interval="1d")

    price = quote.get("price") if quote.get("ok") else None
    if price is None and ohlcv.get("ok") and ohlcv.get("last_close") is not None:
        price = float(ohlcv["last_close"])

    realized_vol = None
    vol_error = None
    if ohlcv.get("ok"):
        realized_vol = _realized_vol(ohlcv.get("bars") or [])
    else:
        vol_error = ohlcv.get("error")

    max_buy_notional = max(0.0, float(cash) * MAX_POSITION_PCT)
    max_buy_shares = 0.0
    if price is not None and price >= MIN_PRICE:
        max_buy_shares = min(MAX_SHARES, max_buy_notional / float(price))

    # Default proposal: size within educational budget (not all-in).
    if proposed_qty is None:
        proposed_qty = math.floor(max_buy_shares) if proposed_side == "buy" else 0.0
        if proposed_side == "buy" and proposed_qty < 1 and max_buy_shares >= 1:
            proposed_qty = 1.0

    gates = evaluate_risk_gates(
        side=proposed_side,
        qty=float(proposed_qty or 0),
        price=float(price) if price is not None else 0.0,
        cash=float(cash),
        held_shares=float(held_shares),
        realized_vol=realized_vol,
    )

    return {
        "ok": price is not None,
        "symbol": symbol,
        "price": price,
        "quote": quote,
        "realized_vol_annual": realized_vol,
        "vol_error": vol_error,
        "cash": float(cash),
        "held_shares": float(held_shares),
        "max_position_pct": MAX_POSITION_PCT,
        "max_shares": MAX_SHARES,
        "max_buy_notional": max_buy_notional,
        "max_buy_shares": max_buy_shares,
        "proposed_side": proposed_side,
        "proposed_qty": float(proposed_qty or 0),
        "risk_ok": gates["risk_ok"],
        "risk_notes": gates["risk_notes"],
        "error": None if price is not None else (
            quote.get("error") or "Live price unavailable for risk gates."
        ),
    }


def evaluate_risk_gates(
    *,
    side: str,
    qty: float,
    price: float,
    cash: float,
    held_shares: float,
    realized_vol: float | None,
) -> dict[str, Any]:
    notes: list[str] = []
    ok = True

    if qty <= 0:
        ok = False
        notes.append("Quantity must be positive.")
    if price < MIN_PRICE:
        ok = False
        notes.append("Price must be positive / available.")
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
        if realized_vol is not None and realized_vol > MAX_REALIZED_VOL:
            ok = False
            notes.append(
                f"Realized vol {realized_vol:.0%} exceeds educational "
                f"cap of {MAX_REALIZED_VOL:.0%} — veto."
            )
    elif side == "sell":
        if qty > held_shares + 1e-9:
            ok = False
            notes.append("Not enough held shares to sell.")
    else:
        ok = False
        notes.append("Side must be buy or sell.")

    if ok:
        notes.append("Passed hard risk gates.")

    return {"risk_ok": ok, "risk_notes": " ".join(notes)}


def format_risk_report(data: dict[str, Any]) -> str:
    lines = [
        f"Risk packet for {data.get('symbol')}",
        f"Live price: {data.get('price')}",
        f"Paper cash: {data.get('cash')} | held shares: {data.get('held_shares')}",
        f"Realized vol (ann.): {data.get('realized_vol_annual')}",
        f"Max position %: {data.get('max_position_pct')} | "
        f"max shares: {data.get('max_shares')}",
        f"Proposed: {data.get('proposed_side')} {data.get('proposed_qty')}",
        f"risk_ok={data.get('risk_ok')} — {data.get('risk_notes')}",
    ]
    if data.get("error"):
        lines.append(f"Data issue: {data['error']}")
    if data.get("vol_error"):
        lines.append(f"Vol data issue: {data['vol_error']}")
    return "\n".join(lines)


def _realized_vol(bars: list[dict[str, Any]]) -> float | None:
    if len(bars) < 10:
        return None
    closes = [float(b["close"]) for b in bars if b.get("close") is not None]
    if len(closes) < 10:
        return None
    rets: list[float] = []
    for i in range(1, len(closes)):
        prev = closes[i - 1]
        if prev <= 0:
            continue
        rets.append(math.log(closes[i] / prev))
    if len(rets) < 5:
        return None
    mean = sum(rets) / len(rets)
    var = sum((r - mean) ** 2 for r in rets) / max(1, len(rets) - 1)
    daily = math.sqrt(var)
    return daily * math.sqrt(252.0)
