"""OHLCV and quote helpers via yfinance (Yahoo Finance public data)."""

from __future__ import annotations

import os
import tempfile
from typing import Any


def _ensure_yfinance_cache() -> None:
    """Point yfinance at a writable cache (avoids readonly system dirs)."""
    cache = os.environ.get("OMNISCOPE_YFINANCE_CACHE") or os.path.join(
        tempfile.gettempdir(),
        "omniscope_yfinance",
    )
    try:
        os.makedirs(cache, exist_ok=True)
        os.environ.setdefault("YFINANCE_CACHE_DIR", cache)
        # Newer yfinance uses XDG-style paths; force when possible.
        try:
            import yfinance as yf

            set_tz = getattr(yf, "set_tz_cache_location", None)
            if callable(set_tz):
                set_tz(cache)
        except Exception:  # noqa: BLE001
            pass
    except OSError:
        pass


def fetch_ohlcv(
    symbol: str,
    *,
    period: str = "6mo",
    interval: str = "1d",
) -> dict[str, Any]:
    """Fetch historical bars. Never invents prices on failure."""
    symbol = symbol.strip().upper()
    _ensure_yfinance_cache()
    try:
        import yfinance as yf

        ticker = yf.Ticker(symbol)
        hist = ticker.history(period=period, interval=interval, auto_adjust=True)
        if hist is None or hist.empty:
            return {
                "ok": False,
                "symbol": symbol,
                "error": f"No OHLCV returned for {symbol} ({period}/{interval}).",
                "bars": [],
            }

        bars: list[dict[str, Any]] = []
        for idx, row in hist.iterrows():
            if hasattr(idx, "date"):
                date_str = str(idx.date())
            else:
                date_str = str(idx)
            bars.append(
                {
                    "date": date_str,
                    "open": float(row["Open"]),
                    "high": float(row["High"]),
                    "low": float(row["Low"]),
                    "close": float(row["Close"]),
                    "volume": float(row.get("Volume") or 0),
                }
            )
        return {
            "ok": True,
            "symbol": symbol,
            "period": period,
            "interval": interval,
            "bars": bars,
            "last_close": bars[-1]["close"] if bars else None,
            "bar_count": len(bars),
        }
    except Exception as exc:  # noqa: BLE001 — surface tool failure to agents
        return {
            "ok": False,
            "symbol": symbol,
            "error": f"OHLCV fetch failed: {exc}",
            "bars": [],
        }


def fetch_quote(symbol: str) -> dict[str, Any]:
    """Best-effort last price and day change from yfinance."""
    symbol = symbol.strip().upper()
    _ensure_yfinance_cache()
    try:
        import yfinance as yf

        ticker = yf.Ticker(symbol)
        info = getattr(ticker, "fast_info", None)
        price: float | None = None
        prev_close: float | None = None
        if info is not None:
            price = _as_float(getattr(info, "last_price", None))
            prev_close = _as_float(getattr(info, "previous_close", None))

        if price is None:
            hist = ticker.history(period="5d", interval="1d", auto_adjust=True)
            if hist is not None and not hist.empty:
                price = float(hist["Close"].iloc[-1])
                if len(hist) >= 2:
                    prev_close = float(hist["Close"].iloc[-2])

        if price is None:
            return {
                "ok": False,
                "symbol": symbol,
                "error": f"No live quote for {symbol}.",
            }

        change_pct: float | None = None
        if prev_close and prev_close > 0:
            change_pct = ((price - prev_close) / prev_close) * 100.0

        return {
            "ok": True,
            "symbol": symbol,
            "price": price,
            "previous_close": prev_close,
            "change_pct": change_pct,
        }
    except Exception as exc:  # noqa: BLE001
        return {
            "ok": False,
            "symbol": symbol,
            "error": f"Quote fetch failed: {exc}",
        }


def _as_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
