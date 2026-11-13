"""CrewAI Analyst Team: Technical, Sentiment & News, Fundamental.

Investigation-stage agents — always CrewAI. Live tool packets are injected
into task descriptions (fetched before kickoff).
"""

from __future__ import annotations

from typing import Any

from crewai import Agent, Crew, Process, Task

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

_DISCLAIMER = "Not financial advice — educational paper trading only."


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
        role="Technical Analyst",
        goal=(
            "Interpret live price action and indicators (MACD, RSI, MAs) "
            "to outline possible entry/exit zones for learners."
        ),
        backstory=(
            "You look only at price and indicators from the provided live packet. "
            "You never invent RSI/MACD values. You never give personalized advice."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    sentiment = Agent(
        role="Sentiment & News Analyst",
        goal=(
            "Gauge market mood from public headlines and flag sudden macro "
            "or company news that could move the stock."
        ),
        backstory=(
            "You read only the provided public news packet (Yahoo + RSS). "
            "You do not claim access to X/Twitter, Bloomberg, or Reuters terminals. "
            "You never invent headlines."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    fundamental = Agent(
        role="Fundamental Analyst",
        goal=(
            "Use SEC filings and financial highlights to judge whether the "
            "company looks relatively rich or cheap — in plain language."
        ),
        backstory=(
            "You rely on the EDGAR packet only. If filings are missing, say so. "
            "You never invent 10-K facts. Educational tone only."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )

    technical_task = Task(
        description=(
            "Using ONLY this live technical packet for '{symbol}':\n\n"
            "{technical_packet}\n\n"
            "Write a short Technical Analyst note (under 220 words): "
            "trend, key indicators, possible entry/exit ideas for paper trading. "
            f"End with: '{_DISCLAIMER}'"
        ),
        expected_output="Plain-language technical analysis note.",
        agent=technical,
    )
    sentiment_task = Task(
        description=(
            "Using ONLY this live news/sentiment packet for '{symbol}':\n\n"
            "{sentiment_packet}\n\n"
            "Write a short Sentiment & News note (under 220 words): mood, "
            "notable headlines, sudden events to watch. "
            f"End with: '{_DISCLAIMER}'"
        ),
        expected_output="Plain-language sentiment and news note.",
        agent=sentiment,
    )
    fundamental_task = Task(
        description=(
            "Using ONLY this live fundamentals packet for '{symbol}':\n\n"
            "{fundamental_packet}\n\n"
            "Write a short Fundamental Analyst note (under 220 words): "
            "business snapshot, valuation lean (rich/fair/cheap if supported), "
            "filing risks. "
            f"End with: '{_DISCLAIMER}'"
        ),
        expected_output="Plain-language fundamentals note.",
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
        role = "Technical Analyst"
        packet = packets["technical"]
        goal = "Interpret live indicators for entry/exit ideas."
    elif stage == "sentiment":
        role = "Sentiment & News Analyst"
        packet = packets["sentiment"]
        goal = "Gauge mood from public headlines."
    elif stage == "fundamental":
        role = "Fundamental Analyst"
        packet = packets["fundamental"]
        goal = "Evaluate EDGAR filings for valuation lean."
    else:
        raise ValueError(f"Unknown analyst stage: {stage}")

    agent = Agent(
        role=role,
        goal=goal,
        backstory=(
            "Educational Omniscope analyst. Use only the live packet. "
            "Never invent data."
        ),
        llm=llm,
        verbose=False,
        allow_delegation=False,
    )
    task = Task(
        description=(
            f"Using ONLY this live packet for '{symbol}':\n\n{packet}\n\n"
            f"Write a short {role} note under 220 words. "
            f"End with: '{_DISCLAIMER}'"
        ),
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
