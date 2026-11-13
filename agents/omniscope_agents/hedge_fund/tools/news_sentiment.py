"""News / mood snapshot from Yahoo Finance news + public RSS (no X/Bloomberg)."""

from __future__ import annotations

from typing import Any
from urllib.parse import quote_plus


def fetch_news_sentiment(symbol: str, *, max_items: int = 12) -> dict[str, Any]:
    """Aggregate public headlines for a symbol. Never invents articles."""
    symbol = symbol.strip().upper()
    headlines: list[dict[str, str]] = []
    errors: list[str] = []

    yahoo = _yahoo_news(symbol, max_items=max_items)
    if yahoo.get("ok"):
        headlines.extend(yahoo.get("items") or [])
    else:
        errors.append(str(yahoo.get("error") or "Yahoo news failed"))

    rss = _google_news_rss(symbol, max_items=max_items)
    if rss.get("ok"):
        headlines.extend(rss.get("items") or [])
    else:
        errors.append(str(rss.get("error") or "RSS news failed"))

    # Deduplicate by title (case-insensitive).
    seen: set[str] = set()
    unique: list[dict[str, str]] = []
    for item in headlines:
        key = (item.get("title") or "").strip().lower()
        if not key or key in seen:
            continue
        seen.add(key)
        unique.append(item)

    unique = unique[:max_items]
    if not unique:
        return {
            "ok": False,
            "symbol": symbol,
            "error": "; ".join(errors) or "No public headlines available.",
            "headlines": [],
            "mood_hint": "unknown",
        }

    mood = _heuristic_mood(unique)
    return {
        "ok": True,
        "symbol": symbol,
        "headlines": unique,
        "mood_hint": mood,
        "source_notes": (
            "Sources: Yahoo Finance news + Google News RSS. "
            "No X/Twitter, Bloomberg, or Reuters terminal access."
        ),
        "errors": errors,
    }


def format_news_report(data: dict[str, Any]) -> str:
    if not data.get("ok"):
        return (
            f"NEWS/SENTIMENT DATA UNAVAILABLE for {data.get('symbol')}.\n"
            f"Error: {data.get('error')}\n"
            "Do not invent headlines. State that live news fetch failed."
        )
    lines = [
        f"News & mood packet for {data['symbol']}",
        f"Heuristic mood hint: {data.get('mood_hint')}",
        data.get("source_notes") or "",
        "Headlines:",
    ]
    for item in data.get("headlines") or []:
        title = item.get("title") or "(no title)"
        source = item.get("source") or "unknown"
        published = item.get("published") or ""
        lines.append(f"- [{source}] {title} {published}".rstrip())
    if data.get("errors"):
        lines.append("Partial source errors:")
        for err in data["errors"]:
            lines.append(f"- {err}")
    return "\n".join(lines)


def _yahoo_news(symbol: str, *, max_items: int) -> dict[str, Any]:
    try:
        from omniscope_agents.hedge_fund.tools.market_data import (
            _ensure_yfinance_cache,
        )

        _ensure_yfinance_cache()
        import yfinance as yf

        ticker = yf.Ticker(symbol)
        raw = ticker.news or []
        items: list[dict[str, str]] = []
        for entry in raw[:max_items]:
            content = entry.get("content") if isinstance(entry, dict) else None
            if isinstance(content, dict):
                title = str(content.get("title") or "").strip()
                provider = content.get("provider") or {}
                source = ""
                if isinstance(provider, dict):
                    source = str(provider.get("displayName") or "Yahoo")
                published = str(content.get("pubDate") or "")
            else:
                title = str(entry.get("title") or "").strip()
                source = str(entry.get("publisher") or "Yahoo")
                published = str(entry.get("providerPublishTime") or "")
            if title:
                items.append(
                    {
                        "title": title,
                        "source": source or "Yahoo",
                        "published": published,
                    }
                )
        if not items:
            return {
                "ok": False,
                "error": f"Yahoo Finance returned no news for {symbol}.",
            }
        return {"ok": True, "items": items}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": f"Yahoo news failed: {exc}"}


def _google_news_rss(symbol: str, *, max_items: int) -> dict[str, Any]:
    try:
        import feedparser

        query = quote_plus(f"{symbol} stock")
        url = (
            "https://news.google.com/rss/search?"
            f"q={query}&hl=en-US&gl=US&ceid=US:en"
        )
        feed = feedparser.parse(url)
        entries = getattr(feed, "entries", None) or []
        items: list[dict[str, str]] = []
        for entry in entries[:max_items]:
            title = str(getattr(entry, "title", "") or "").strip()
            if not title:
                continue
            source_obj = getattr(entry, "source", None)
            if isinstance(source_obj, dict):
                source = str(source_obj.get("title") or "Google News")
            else:
                source = "Google News"
            items.append(
                {
                    "title": title,
                    "source": source,
                    "published": str(getattr(entry, "published", "") or ""),
                }
            )
        if not items:
            return {
                "ok": False,
                "error": f"Google News RSS returned no items for {symbol}.",
            }
        return {"ok": True, "items": items}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": f"Google News RSS failed: {exc}"}


def _heuristic_mood(headlines: list[dict[str, str]]) -> str:
    positive = (
        "beat",
        "surge",
        "rally",
        "upgrade",
        "growth",
        "record",
        "profit",
        "bullish",
        "soar",
        "gain",
    )
    negative = (
        "miss",
        "fall",
        "drop",
        "downgrade",
        "lawsuit",
        "probe",
        "loss",
        "bearish",
        "cut",
        "fraud",
        "recall",
        "bankrupt",
    )
    score = 0
    for item in headlines:
        text = (item.get("title") or "").lower()
        score += sum(1 for w in positive if w in text)
        score -= sum(1 for w in negative if w in text)
    if score >= 2:
        return "constructive"
    if score <= -2:
        return "cautious"
    return "mixed"
