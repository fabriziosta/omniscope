"""Technical indicators via pandas-ta (pure Python, no TA-Lib)."""

from __future__ import annotations

from typing import Any

from omniscope_agents.hedge_fund.tools.market_data import fetch_ohlcv


def compute_technicals(symbol: str, *, period: str = "6mo") -> dict[str, Any]:
    """Compute RSI, MACD, and moving averages from live OHLCV."""
    symbol = symbol.strip().upper()
    ohlcv = fetch_ohlcv(symbol, period=period, interval="1d")
    if not ohlcv.get("ok"):
        return {
            "ok": False,
            "symbol": symbol,
            "error": ohlcv.get("error") or "OHLCV unavailable for technicals.",
        }

    bars = ohlcv.get("bars") or []
    if len(bars) < 35:
        return {
            "ok": False,
            "symbol": symbol,
            "error": (
                f"Need at least 35 daily bars for indicators; got {len(bars)}."
            ),
            "bar_count": len(bars),
        }

    try:
        import pandas as pd
        import pandas_ta as ta

        df = pd.DataFrame(bars)
        close = df["close"]

        rsi = ta.rsi(close, length=14)
        macd_df = ta.macd(close, fast=12, slow=26, signal=9)
        sma20 = ta.sma(close, length=20)
        sma50 = ta.sma(close, length=50)
        ema12 = ta.ema(close, length=12)

        last_rsi = _last(rsi)
        macd_line = _last(macd_df["MACD_12_26_9"]) if macd_df is not None else None
        macd_signal = (
            _last(macd_df["MACDs_12_26_9"]) if macd_df is not None else None
        )
        macd_hist = (
            _last(macd_df["MACDh_12_26_9"]) if macd_df is not None else None
        )

        last_close = float(close.iloc[-1])
        sma20_v = _last(sma20)
        sma50_v = _last(sma50)

        signals: list[str] = []
        if last_rsi is not None:
            if last_rsi >= 70:
                signals.append("RSI suggests overbought territory.")
            elif last_rsi <= 30:
                signals.append("RSI suggests oversold territory.")
            else:
                signals.append("RSI is in a mid range.")
        if macd_hist is not None:
            if macd_hist > 0:
                signals.append("MACD histogram is positive (bullish momentum).")
            else:
                signals.append("MACD histogram is negative (bearish momentum).")
        if sma20_v is not None and sma50_v is not None:
            if sma20_v > sma50_v:
                signals.append("SMA20 is above SMA50 (short-term uptrend bias).")
            else:
                signals.append("SMA20 is below SMA50 (short-term downtrend bias).")

        return {
            "ok": True,
            "symbol": symbol,
            "last_close": last_close,
            "rsi_14": last_rsi,
            "macd": macd_line,
            "macd_signal": macd_signal,
            "macd_histogram": macd_hist,
            "sma_20": sma20_v,
            "sma_50": sma50_v,
            "ema_12": _last(ema12),
            "signals": signals,
            "bar_count": len(bars),
            "as_of": bars[-1].get("date"),
        }
    except Exception as exc:  # noqa: BLE001
        return {
            "ok": False,
            "symbol": symbol,
            "error": f"Technical indicator compute failed: {exc}",
        }


def format_technicals_report(data: dict[str, Any]) -> str:
    """Plain-text packet for the Technical Analyst prompt."""
    if not data.get("ok"):
        return (
            f"TECHNICAL DATA UNAVAILABLE for {data.get('symbol')}.\n"
            f"Error: {data.get('error')}\n"
            "Do not invent indicator values. State that live data failed."
        )
    lines = [
        f"Technical snapshot for {data['symbol']} (as of {data.get('as_of')})",
        f"Last close: {data.get('last_close')}",
        f"RSI(14): {data.get('rsi_14')}",
        f"MACD: {data.get('macd')} | signal: {data.get('macd_signal')} | "
        f"hist: {data.get('macd_histogram')}",
        f"SMA20: {data.get('sma_20')} | SMA50: {data.get('sma_50')} | "
        f"EMA12: {data.get('ema_12')}",
        "Signals:",
    ]
    for s in data.get("signals") or []:
        lines.append(f"- {s}")
    return "\n".join(lines)


def _last(series: Any) -> float | None:
    if series is None:
        return None
    try:
        value = series.dropna().iloc[-1]
        return float(value)
    except Exception:  # noqa: BLE001
        return None
