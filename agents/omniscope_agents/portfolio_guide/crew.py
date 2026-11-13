"""CrewAI crew for Portfolio & Allocation Guide.

This role always uses CrewAI — do not swap frameworks.
In-app chat uses Flutter HTTPS prompts; this CLI is for offline snapshots.
"""

from __future__ import annotations

from typing import Any

from crewai import Agent, Crew, Process, Task

from omniscope_agents.disclaimer import EDUCATIONAL_DISCLAIMER
from omniscope_agents.llm import Provider, build_crewai_llm


def run_portfolio_guide(
    snapshot_text: str,
    *,
    provider: Provider,
    model: str,
    symbol_hint: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> str:
    """Explain allocation / concentration from a pasted portfolio snapshot."""
    llm = build_crewai_llm(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    focus = (
        f" Prefer commenting on {symbol_hint.strip().upper()} when present."
        if symbol_hint and symbol_hint.strip()
        else ""
    )
    agent = Agent(
        role="Portfolio & Allocation Guide",
        goal=(
            "Explain diversification, concentration, and cash drag in plain "
            "language without placing orders."
        ),
        backstory=(
            "You are an educational helper inside Omniscope. "
            f"{EDUCATIONAL_DISCLAIMER}"
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    task = Task(
        description=(
            "Using only the snapshot below, review allocation: cash vs "
            "holdings, concentration risk, and simple diversification ideas."
            f"{focus}\n\n"
            f"Snapshot:\n{snapshot_text.strip()}\n\n"
            "Do not invent positions. Do not emit trade JSON."
        ),
        expected_output=(
            "A short educational allocation note with clear sections. "
            "No JSON trade block."
        ),
        agent=agent,
    )
    crew = Crew(
        agents=[agent],
        tasks=[task],
        process=Process.sequential,
        verbose=False,
    )
    result: Any = crew.kickoff()
    return str(result).strip()
