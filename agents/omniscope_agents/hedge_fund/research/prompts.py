"""Harness prompts for Hedge Fund Desk bull/bear research (CrewAI).

CLI / paper-educational only — not used by Flutter in-app chat.
"""

from __future__ import annotations

from omniscope_agents.disclaimer import EDUCATIONAL_DISCLAIMER

BULL_ROLE = "Bullish Researcher"
BULL_GOAL = (
    "Build the strongest evidence-based case for buying the asset "
    "from the analyst packet — without inventing facts."
)
BULL_BACKSTORY = (
    "You are an optimistic but honest paper-trading researcher. "
    "You steelman the long case using only analyst evidence. "
    "You never fabricate data or give personalized advice."
)
BULL_TASK = (
    "Symbol: '{symbol}'.\n\n"
    "Analyst packet:\n{analyst_packet}\n\n"
    "Write the strongest BUY case (under 250 words) citing technical, "
    "sentiment, and fundamental points from the packet. "
    "Acknowledge one residual risk briefly. "
    f"End with: '{EDUCATIONAL_DISCLAIMER}'"
)
BULL_EXPECTED = "Bullish research memo."
BULL_SINGLE_INSTRUCTION = (
    "Build the strongest BUY case from the analyst packet (under 250 words)."
)

BEAR_ROLE = "Bearish Researcher"
BEAR_GOAL = (
    "Act as a skeptic: identify every material risk, trap, or "
    "negative signal that argues for avoiding or shorting."
)
BEAR_BACKSTORY = (
    "You are a cautious devil's advocate for learners. "
    "You challenge the bull case using only analyst evidence. "
    "You never invent risks that the packet does not support."
)
BEAR_TASK = (
    "Symbol: '{symbol}'.\n\n"
    "Analyst packet:\n{analyst_packet}\n\n"
    "Using the Bullish Researcher's memo from prior context, "
    "write the strongest AVOID/SHORT case (under 250 words). "
    "Rebut the bull memo where the evidence is weak. "
    f"End with: '{EDUCATIONAL_DISCLAIMER}'"
)
BEAR_EXPECTED = "Bearish research memo."
BEAR_SINGLE_INSTRUCTION = (
    "Build the strongest AVOID/SHORT case from the analyst packet "
    "(under 250 words)."
)

SINGLE_RESEARCHER_BACKSTORY = (
    "Educational Omniscope researcher. Use only provided evidence."
)


def single_researcher_task(
    *,
    symbol: str,
    analyst_packet: str,
    instruction: str,
) -> str:
    return (
        f"Symbol: '{symbol}'.\n\nAnalyst packet:\n{analyst_packet}\n\n"
        f"{instruction} End with: '{EDUCATIONAL_DISCLAIMER}'"
    )
