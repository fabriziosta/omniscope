"""CrewAI Research Team: Bullish vs Bearish dialectical debate."""

from __future__ import annotations

from typing import Any

from crewai import Agent, Crew, Process, Task

from omniscope_agents.hedge_fund.research import prompts as P
from omniscope_agents.llm import Provider, build_crewai_llm


def build_research_debate_crew(
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

    bull = Agent(
        role=P.BULL_ROLE,
        goal=P.BULL_GOAL,
        backstory=P.BULL_BACKSTORY,
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    bear = Agent(
        role=P.BEAR_ROLE,
        goal=P.BEAR_GOAL,
        backstory=P.BEAR_BACKSTORY,
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )

    bull_task = Task(
        description=P.BULL_TASK,
        expected_output=P.BULL_EXPECTED,
        agent=bull,
    )
    bear_task = Task(
        description=P.BEAR_TASK,
        expected_output=P.BEAR_EXPECTED,
        agent=bear,
        context=[bull_task],
    )

    return Crew(
        agents=[bull, bear],
        tasks=[bull_task, bear_task],
        process=Process.sequential,
        verbose=False,
    )


def run_research_debate(
    symbol: str,
    analyst_packet: str,
    *,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
) -> dict[str, Any]:
    symbol = symbol.strip().upper()
    crew = build_research_debate_crew(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    result: Any = crew.kickoff(
        inputs={
            "symbol": symbol,
            "analyst_packet": analyst_packet,
        }
    )
    outputs = _extract_task_outputs(result)
    bull_report = outputs[0] if len(outputs) > 0 else str(result)
    bear_report = outputs[1] if len(outputs) > 1 else ""
    debate = (
        f"## Bullish Researcher\n{bull_report}\n\n"
        f"## Bearish Researcher\n{bear_report}\n"
    )
    return {
        "symbol": symbol,
        "bull_report": bull_report,
        "bear_report": bear_report,
        "debate_report": debate,
        "raw": str(result),
    }


def run_single_researcher(
    stage: str,
    symbol: str,
    analyst_packet: str,
    *,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
) -> str:
    """CLI helper for bull or bear alone."""
    symbol = symbol.strip().upper()
    llm = build_crewai_llm(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    if stage == "bull":
        role = P.BULL_ROLE
        instruction = P.BULL_SINGLE_INSTRUCTION
    elif stage == "bear":
        role = P.BEAR_ROLE
        instruction = P.BEAR_SINGLE_INSTRUCTION
    else:
        raise ValueError(f"Unknown researcher stage: {stage}")

    agent = Agent(
        role=role,
        goal=instruction,
        backstory=P.SINGLE_RESEARCHER_BACKSTORY,
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    task = Task(
        description=P.single_researcher_task(
            symbol=symbol,
            analyst_packet=analyst_packet,
            instruction=instruction,
        ),
        expected_output=f"{role} memo.",
        agent=agent,
    )
    crew = Crew(
        agents=[agent],
        tasks=[task],
        process=Process.sequential,
        verbose=False,
    )
    return str(crew.kickoff(inputs={"symbol": symbol}))


def _extract_task_outputs(result: Any) -> list[str]:
    outputs: list[str] = []
    tasks_output = getattr(result, "tasks_output", None)
    if tasks_output:
        for item in tasks_output:
            raw = getattr(item, "raw", None) or getattr(item, "output", None)
            outputs.append(str(raw if raw is not None else item))
        return outputs
    return [str(result)]
