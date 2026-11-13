"""CrewAI crew for Practice Portfolio Coach.

This role always uses CrewAI — do not swap frameworks.
In-app chat uses Flutter HTTPS prompts; this CLI is for offline snapshots.
"""

from __future__ import annotations

from typing import Any

from crewai import Agent, Crew, Process, Task

from omniscope_agents.disclaimer import EDUCATIONAL_DISCLAIMER
from omniscope_agents.llm import Provider, build_crewai_llm


def run_paper_portfolio_coach(
    snapshot_text: str,
    *,
    provider: Provider,
    model: str,
    symbol_hint: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> str:
    """Coach on practice cash / size / avg cost from a pasted snapshot."""
    llm = build_crewai_llm(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    focus = (
        f" Prefer coaching around {symbol_hint.strip().upper()} when present."
        if symbol_hint and symbol_hint.strip()
        else ""
    )
    agent = Agent(
        role="Practice Portfolio Coach",
        goal=(
            "Help beginners understand practice cash, holdings, size, and "
            "avg cost — educational only, no live orders."
        ),
        backstory=(
            "You are an educational helper inside Omniscope. Practice money "
            "is fake. "
            f"{EDUCATIONAL_DISCLAIMER}"
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    task = Task(
        description=(
            "Using only the snapshot below, coach the user on practice cash, "
            "holdings, position size, and average cost in plain language."
            f"{focus}\n\n"
            f"Snapshot:\n{snapshot_text.strip()}\n\n"
            "Do not invent positions. Do not emit trade JSON."
        ),
        expected_output=(
            "A short educational coaching note with clear sections. "
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
