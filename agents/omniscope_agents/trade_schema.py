"""Cross-surface trade proposal JSON field contract.

Flutter TradeProposal and the Hedge Fund Desk Head Trader both emit / parse
this shape. Prompt prose stays separate (live vs paper); only field names
are shared. Keep in sync with Dart TradeProposal.canonicalLlmKeys.
"""

from __future__ import annotations

TRADE_JSON_KEYS: tuple[str, ...] = (
    "ticker",
    "action",
    "quantity",
    "rationale",
    "risk_approved",
)

# Example object for Head Trader / docs (values are placeholders).
TRADE_JSON_EXAMPLE = (
    '{"ticker":"...","action":"buy|sell|hold","quantity":0,'
    '"rationale":"...","risk_approved":true}'
)
