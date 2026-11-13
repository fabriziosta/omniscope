"""Harness prompts for Intraday Execution & Risk Control (LangGraph).

CLI / paper-educational only — not used by Flutter in-app chat.
"""

from __future__ import annotations

from typing import Mapping

RISK_NARRATOR_SYSTEM = (
    "You are Omniscope's educational risk narrator. Be concise and clear."
)


def summarize_human_prompt(state: Mapping[str, object]) -> str:
    """Build the learner-facing summary turn from gate state."""
    return (
        f"Symbol: {state.get('symbol')}\n"
        f"Side: {state.get('side')}\n"
        f"Qty: {state.get('qty')}\n"
        f"Price: {state.get('price')}\n"
        f"Cash: {state.get('cash')}\n"
        f"Held shares: {state.get('held_shares')}\n"
        f"Risk OK: {state.get('risk_ok')}\n"
        f"Risk notes: {state.get('risk_notes')}\n"
        f"Decision: {state.get('decision')}\n\n"
        "Write a short plain-language summary for a learner. "
        "If rejected, explain which gate failed. "
        "Remind them this is paper trading only, not financial advice."
    )
