"""CrewAI crew for Live Balance Explainer.

This role always uses CrewAI — do not swap frameworks.
In-app chat uses Flutter HTTPS prompts; this CLI is for offline snapshots.
"""

from __future__ import annotations

from typing import Any

from crewai import Agent, Crew, Process, Task

from omniscope_agents.disclaimer import EDUCATIONAL_DISCLAIMER
from omniscope_agents.llm import Provider, build_crewai_llm


def run_live_balance_explainer(
    snapshot_text: str,
    *,
    provider: Provider,
    model: str,
    asset_hint: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> str:
    """Explain a pasted live exchange snapshot in plain language."""
    llm = build_crewai_llm(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    focus = (
        f" Prefer focusing on asset {asset_hint.strip().upper()} when present."
        if asset_hint and asset_hint.strip()
        else ""
    )
    agent = Agent(
        role="Live Balance Explainer",
        goal=(
            "Explain live exchange balances so a beginner understands "
            "totals, available cash, and each asset — without placing orders."
        ),
        backstory=(
            "You are an educational helper inside Omniscope. "
            "Balances are read-only on the Portfolio tab; Confirm / Autopilot "
            "on trading agents can place live orders when the user opts in. "
            f"{EDUCATIONAL_DISCLAIMER}"
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    task = Task(
        description=(
            "Using only the snapshot below, write a plain-language explanation "
            "of total vs available, assets vs cash, and what is read-only versus "
            f"what Confirm or Autopilot would touch.{focus}\n\n"
            f"Snapshot:\n{snapshot_text.strip()}\n\n"
            "Do not invent balances. Do not emit trade JSON."
        ),
        expected_output=(
            "A short educational explanation with clear sections. "
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
