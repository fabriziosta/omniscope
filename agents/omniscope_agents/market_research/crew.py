"""CrewAI crew for Market Research & Analysis.

This role always uses CrewAI — do not swap frameworks.
"""

from __future__ import annotations

from typing import Any

from crewai import Agent, Crew, Process, Task

from omniscope_agents.llm import Provider, build_crewai_llm
from omniscope_agents.market_research import prompts as P


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
        role=P.MACRO_ROLE,
        goal=P.MACRO_GOAL,
        backstory=P.MACRO_BACKSTORY,
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    fundamentals = Agent(
        role=P.FUNDAMENTALS_ROLE,
        goal=P.FUNDAMENTALS_GOAL,
        backstory=P.FUNDAMENTALS_BACKSTORY,
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    risk = Agent(
        role=P.RISK_ROLE,
        goal=P.RISK_GOAL,
        backstory=P.RISK_BACKSTORY,
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )

    macro_task = Task(
        description=P.MACRO_TASK,
        expected_output=P.MACRO_EXPECTED,
        agent=macro,
    )
    fundamentals_task = Task(
        description=P.FUNDAMENTALS_TASK,
        expected_output=P.FUNDAMENTALS_EXPECTED,
        agent=fundamentals,
        context=[macro_task],
    )
    risk_task = Task(
        description=P.RISK_TASK,
        expected_output=P.RISK_EXPECTED,
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
