"""CrewAI crew for Market Research & Analysis.

This role always uses CrewAI — do not swap frameworks.
"""

from __future__ import annotations

from typing import Any

from crewai import Agent, Crew, Process, Task

from omniscope_agents.llm import Provider, build_crewai_llm


def build_research_crew(
    *,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
) -> Crew:
    llm = build_crewai_llm(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )

    macro = Agent(
        role="Macro scanner",
        goal="Summarize the broad market backdrop in plain language for learners.",
        backstory=(
            "You explain rates, risk appetite, and sector rotation without jargon. "
            "You never give personalized financial advice."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    fundamentals = Agent(
        role="Fundamentals summarizer",
        goal="Describe what the company or topic is known for at a high level.",
        backstory=(
            "You focus on business model, competitive position, and obvious risks. "
            "You use short sentences suitable for beginners."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    risk = Agent(
        role="Risk narrator",
        goal="List key uncertainties and what a cautious learner should watch.",
        backstory=(
            "You highlight downside scenarios and remind readers this is educational, "
            "not a buy/sell recommendation."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )

    macro_task = Task(
        description=(
            "Write a short macro backdrop for researching '{symbol}'. "
            "Cover mood, rates/inflation themes if relevant, and sector context. "
            "Keep it under 180 words."
        ),
        expected_output="A plain-language macro paragraph.",
        agent=macro,
    )
    fundamentals_task = Task(
        description=(
            "Summarize '{symbol}' for a beginner: what it does, why people follow it, "
            "and one or two obvious risks. Keep it under 180 words. "
            "Use the prior macro notes as context."
        ),
        expected_output="A plain-language fundamentals paragraph.",
        agent=fundamentals,
        context=[macro_task],
    )
    risk_task = Task(
        description=(
            "Combine the prior notes into a final research brief for '{symbol}'. "
            "Include: Snapshot, What matters, Risks to watch, Learning tip. "
            "End with: 'Not financial advice — educational paper trading only.'"
        ),
        expected_output="A structured markdown research brief.",
        agent=risk,
        context=[macro_task, fundamentals_task],
    )

    return Crew(
        agents=[macro, fundamentals, risk],
        tasks=[macro_task, fundamentals_task, risk_task],
        process=Process.sequential,
        verbose=False,
    )


def run_market_research(
    symbol: str,
    *,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
) -> str:
    crew = build_research_crew(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    result: Any = crew.kickoff(inputs={"symbol": symbol.strip().upper()})
    return str(result)
