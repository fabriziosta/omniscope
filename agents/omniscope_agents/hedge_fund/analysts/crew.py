"""CrewAI Analyst Team: Technical, Sentiment & News, Fundamental.

Investigation-stage agents — always CrewAI. Live tool packets are injected
into task descriptions (fetched before kickoff).
"""

from __future__ import annotations

from typing import Any

from crewai import Agent, Crew, Process, Task

from omniscope_agents.hedge_fund.analysts import prompts as P
from omniscope_agents.hedge_fund.tools.fundamentals import (
    fetch_fundamentals_snapshot,
    format_fundamentals_report,
)
from omniscope_agents.hedge_fund.tools.news_sentiment import (
    fetch_news_sentiment,
    format_news_report,
)
from omniscope_agents.hedge_fund.tools.technicals import (
    compute_technicals,
    format_technicals_report,
)
from omniscope_agents.llm import Provider, build_crewai_llm


def gather_analyst_packets(symbol: str) -> dict[str, str]:
    """Fetch live data once and format plain-text packets for prompts."""
    symbol = symbol.strip().upper()
    tech = compute_technicals(symbol)
    news = fetch_news_sentiment(symbol)
    fund = fetch_fundamentals_snapshot(symbol)
    return {
        "technical": format_technicals_report(tech),
        "sentiment": format_news_report(news),
        "fundamental": format_fundamentals_report(fund),
        "technical_ok": str(bool(tech.get("ok"))),
        "sentiment_ok": str(bool(news.get("ok"))),
        "fundamental_ok": str(bool(fund.get("ok"))),
    }


def build_analyst_crew(
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

    technical = Agent(
        role=P.TECHNICAL_ROLE,
        goal=P.TECHNICAL_GOAL,
        backstory=P.TECHNICAL_BACKSTORY,
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    sentiment = Agent(
        role=P.SENTIMENT_ROLE,
        goal=P.SENTIMENT_GOAL,
        backstory=P.SENTIMENT_BACKSTORY,
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    fundamental = Agent(
        role=P.FUNDAMENTAL_ROLE,
        goal=P.FUNDAMENTAL_GOAL,
        backstory=P.FUNDAMENTAL_BACKSTORY,
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )

    technical_task = Task(
        description=P.TECHNICAL_TASK,
        expected_output=P.TECHNICAL_EXPECTED,
        agent=technical,
    )
    sentiment_task = Task(
        description=P.SENTIMENT_TASK,
        expected_output=P.SENTIMENT_EXPECTED,
        agent=sentiment,
    )
    fundamental_task = Task(
        description=P.FUNDAMENTAL_TASK,
        expected_output=P.FUNDAMENTAL_EXPECTED,
        agent=fundamental,
    )

    return Crew(
        agents=[technical, sentiment, fundamental],
        tasks=[technical_task, sentiment_task, fundamental_task],
        process=Process.sequential,
        verbose=False,
    )


def run_analyst_team(
    symbol: str,
    *,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
    packets: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Run the three analysts; return individual reports + combined packet."""
    symbol = symbol.strip().upper()
    packets = packets or gather_analyst_packets(symbol)
    crew = build_analyst_crew(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    result: Any = crew.kickoff(
        inputs={
            "symbol": symbol,
            "technical_packet": packets["technical"],
            "sentiment_packet": packets["sentiment"],
            "fundamental_packet": packets["fundamental"],
        }
    )

    task_outputs = _extract_task_outputs(result)
    technical_report = task_outputs[0] if len(task_outputs) > 0 else str(result)
    sentiment_report = task_outputs[1] if len(task_outputs) > 1 else ""
    fundamental_report = task_outputs[2] if len(task_outputs) > 2 else ""

    combined = (
        f"## Technical Analyst\n{technical_report}\n\n"
        f"## Sentiment & News Analyst\n{sentiment_report}\n\n"
        f"## Fundamental Analyst\n{fundamental_report}\n"
    )
    return {
        "symbol": symbol,
        "packets": packets,
        "technical_report": technical_report,
        "sentiment_report": sentiment_report,
        "fundamental_report": fundamental_report,
        "combined_report": combined,
        "raw": str(result),
    }


def run_single_analyst(
    stage: str,
    symbol: str,
    *,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
) -> str:
    """CLI helper: run one analyst stage with live data only."""
    symbol = symbol.strip().upper()
    packets = gather_analyst_packets(symbol)
    llm = build_crewai_llm(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )

    if stage == "technical":
        role = P.TECHNICAL_ROLE
        packet = packets["technical"]
        goal = P.TECHNICAL_SINGLE_GOAL
    elif stage == "sentiment":
        role = P.SENTIMENT_ROLE
        packet = packets["sentiment"]
        goal = P.SENTIMENT_SINGLE_GOAL
    elif stage == "fundamental":
        role = P.FUNDAMENTAL_ROLE
        packet = packets["fundamental"]
        goal = P.FUNDAMENTAL_SINGLE_GOAL
    else:
        raise ValueError(f"Unknown analyst stage: {stage}")

    agent = Agent(
        role=role,
        goal=goal,
        backstory=P.SINGLE_ANALYST_BACKSTORY,
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    task = Task(
        description=P.single_analyst_task(role=role, symbol=symbol, packet=packet),
        expected_output=f"Plain-language {role} note.",
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
