"""CrewAI Research Team: Bullish vs Bearish dialectical debate."""

from __future__ import annotations

from typing import Any

from crewai import Agent, Crew, Process, Task

from omniscope_agents.llm import Provider, build_crewai_llm

_DISCLAIMER = "Not financial advice — educational paper trading only."


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
        role="Bullish Researcher",
        goal=(
            "Build the strongest evidence-based case for buying the asset "
            "from the analyst packet — without inventing facts."
        ),
        backstory=(
            "You are an optimistic but honest paper-trading researcher. "
            "You steelman the long case using only analyst evidence. "
            "You never fabricate data or give personalized advice."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    bear = Agent(
        role="Bearish Researcher",
        goal=(
            "Act as a skeptic: identify every material risk, trap, or "
            "negative signal that argues for avoiding or shorting."
        ),
        backstory=(
            "You are a cautious devil's advocate for learners. "
            "You challenge the bull case using only analyst evidence. "
            "You never invent risks that the packet does not support."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )

    bull_task = Task(
        description=(
            "Symbol: '{symbol}'.\n\n"
            "Analyst packet:\n{analyst_packet}\n\n"
            "Write the strongest BUY case (under 250 words) citing technical, "
            "sentiment, and fundamental points from the packet. "
            "Acknowledge one residual risk briefly. "
            f"End with: '{_DISCLAIMER}'"
        ),
        expected_output="Bullish research memo.",
        agent=bull,
    )
    bear_task = Task(
        description=(
            "Symbol: '{symbol}'.\n\n"
            "Analyst packet:\n{analyst_packet}\n\n"
            "Using the Bullish Researcher's memo from prior context, "
            "write the strongest AVOID/SHORT case (under 250 words). "
            "Rebut the bull memo where the evidence is weak. "
            f"End with: '{_DISCLAIMER}'"
        ),
        expected_output="Bearish research memo.",
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
        role = "Bullish Researcher"
        instruction = (
            "Build the strongest BUY case from the analyst packet (under 250 words)."
        )
    elif stage == "bear":
        role = "Bearish Researcher"
        instruction = (
            "Build the strongest AVOID/SHORT case from the analyst packet "
            "(under 250 words)."
        )
    else:
        raise ValueError(f"Unknown researcher stage: {stage}")

    agent = Agent(
        role=role,
        goal=instruction,
        backstory="Educational Omniscope researcher. Use only provided evidence.",
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    task = Task(
        description=(
            f"Symbol: '{symbol}'.\n\nAnalyst packet:\n{analyst_packet}\n\n"
            f"{instruction} End with: '{_DISCLAIMER}'"
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
