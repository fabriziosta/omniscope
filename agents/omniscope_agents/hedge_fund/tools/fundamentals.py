"""Company fundamentals via SEC EDGAR (edgartools) — public filings only."""

from __future__ import annotations

from typing import Any


def fetch_fundamentals_snapshot(symbol: str) -> dict[str, Any]:
    """Pull recent 10-K / 10-Q metadata and simple financial highlights."""
    symbol = symbol.strip().upper()
    try:
        from edgar import Company, set_identity

        # SEC fair-access: identify the educational client.
        set_identity("Omniscope educational agent contact@omniscope.local")

        company = Company(symbol)
        name = str(getattr(company, "name", None) or symbol)
        cik = str(getattr(company, "cik", None) or "")

        filings_summary: list[dict[str, str]] = []
        for form in ("10-K", "10-Q"):
            try:
                filings = company.get_filings(form=form)
                latest = filings.latest() if filings is not None else None
                if latest is None:
                    continue
                filings_summary.append(
                    {
                        "form": form,
                        "filing_date": str(
                            getattr(latest, "filing_date", None)
                            or getattr(latest, "date", "")
                            or ""
                        ),
                        "accession": str(
                            getattr(latest, "accession_number", None)
                            or getattr(latest, "accession_no", "")
                            or ""
                        ),
                        "report_date": str(
                            getattr(latest, "report_date", None) or ""
                        ),
                    }
                )
            except Exception as exc:  # noqa: BLE001
                filings_summary.append(
                    {
                        "form": form,
                        "error": f"Could not load {form}: {exc}",
                    }
                )

        financials = _safe_financials(company)

        if not filings_summary and not financials.get("ok"):
            return {
                "ok": False,
                "symbol": symbol,
                "error": (
                    f"No SEC filings or financials found for {symbol}. "
                    "Ticker may be ETF/crypto/foreign without EDGAR coverage."
                ),
                "company_name": name,
                "cik": cik,
            }

        return {
            "ok": True,
            "symbol": symbol,
            "company_name": name,
            "cik": cik,
            "filings": filings_summary,
            "financials": financials,
        }
    except Exception as exc:  # noqa: BLE001
        return {
            "ok": False,
            "symbol": symbol,
            "error": f"EDGAR fundamentals fetch failed: {exc}",
        }


def format_fundamentals_report(data: dict[str, Any]) -> str:
    if not data.get("ok"):
        return (
            f"FUNDAMENTALS DATA UNAVAILABLE for {data.get('symbol')}.\n"
            f"Error: {data.get('error')}\n"
            "Do not invent filing facts or balance-sheet numbers."
        )
    lines = [
        f"Fundamentals packet for {data['symbol']}",
        f"Company: {data.get('company_name')} | CIK: {data.get('cik')}",
        "Recent SEC filings:",
    ]
    for filing in data.get("filings") or []:
        if filing.get("error"):
            lines.append(f"- {filing.get('form')}: {filing['error']}")
        else:
            lines.append(
                f"- {filing.get('form')} filed {filing.get('filing_date')} "
                f"(report {filing.get('report_date')}) "
                f"accession={filing.get('accession')}"
            )
    fin = data.get("financials") or {}
    if fin.get("ok"):
        lines.append("Financial highlights (from EDGAR-linked data):")
        for key, value in (fin.get("metrics") or {}).items():
            lines.append(f"- {key}: {value}")
    elif fin.get("error"):
        lines.append(f"Financial metrics unavailable: {fin['error']}")
    return "\n".join(lines)


def _safe_financials(company: Any) -> dict[str, Any]:
    try:
        facts = None
        for attr in ("get_financials", "financials", "get_facts"):
            method = getattr(company, attr, None)
            if method is None:
                continue
            try:
                facts = method() if callable(method) else method
            except Exception:  # noqa: BLE001
                continue
            if facts is not None:
                break

        metrics: dict[str, Any] = {}
        # Best-effort extraction across edgartools versions.
        if facts is not None:
            for label, getters in (
                ("revenue", ("revenue", "Revenue", "Revenues")),
                ("net_income", ("net_income", "NetIncomeLoss", "net_income_loss")),
                ("assets", ("assets", "Assets", "total_assets")),
                ("liabilities", ("liabilities", "Liabilities", "total_liabilities")),
                (
                    "equity",
                    (
                        "stockholders_equity",
                        "StockholdersEquity",
                        "equity",
                    ),
                ),
            ):
                value = _dig_metric(facts, getters)
                if value is not None:
                    metrics[label] = value

        if not metrics:
            return {
                "ok": False,
                "error": "Company found but no numeric financial metrics exposed.",
            }
        return {"ok": True, "metrics": metrics}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": f"Financial metrics failed: {exc}"}


def _dig_metric(obj: Any, names: tuple[str, ...]) -> Any:
    for name in names:
        if isinstance(obj, dict) and name in obj:
            return _scalar(obj[name])
        if hasattr(obj, name):
            return _scalar(getattr(obj, name))
        get = getattr(obj, "get", None)
        if callable(get):
            try:
                value = get(name)
                if value is not None:
                    return _scalar(value)
            except Exception:  # noqa: BLE001
                pass
    text = str(obj)
    # Avoid dumping huge objects into the prompt.
    if len(text) < 200 and any(n.lower() in text.lower() for n in names):
        return text[:200]
    return None


def _scalar(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (int, float, str, bool)):
        return value
    # pandas Series / list — take last non-null-ish
    try:
        if hasattr(value, "iloc"):
            series = value.dropna() if hasattr(value, "dropna") else value
            return _scalar(series.iloc[-1])
    except Exception:  # noqa: BLE001
        pass
    if isinstance(value, (list, tuple)) and value:
        return _scalar(value[-1])
    text = str(value)
    return text if len(text) <= 120 else text[:117] + "..."
