"""Map provider + model + api_key to LangChain chat models."""

from __future__ import annotations

import os
from typing import Any, Literal

from langchain_core.language_models.chat_models import BaseChatModel

Provider = Literal["gemini", "openai", "anthropic", "deepseek", "grok", "custom"]

# OpenAI-compatible base URLs for first-party providers that use that protocol.
DEEPSEEK_BASE_URL = "https://api.deepseek.com"
GROK_BASE_URL = "https://api.x.ai/v1"


_PROVIDER_ENV = {
    "gemini": "OMNISCOPE_GEMINI_API_KEY",
    "openai": "OMNISCOPE_OPENAI_API_KEY",
    "anthropic": "OMNISCOPE_ANTHROPIC_API_KEY",
    "deepseek": "OMNISCOPE_DEEPSEEK_API_KEY",
    "grok": "OMNISCOPE_GROK_API_KEY",
    "custom": "OMNISCOPE_CUSTOM_API_KEY",
}


def resolve_api_key(
    explicit: str | None = None,
    *,
    provider: Provider | None = None,
) -> str:
    """Resolve an API key from CLI, provider-specific env, or OMNISCOPE_API_KEY."""
    if explicit and explicit.strip():
        return explicit.strip()
    if provider is not None:
        named = (os.environ.get(_PROVIDER_ENV[provider]) or "").strip()
        if named:
            return named
    key = (os.environ.get("OMNISCOPE_API_KEY") or "").strip()
    if not key:
        if provider is not None:
            raise SystemExit(
                "Missing API key. Pass --api-key or set "
                f"{_PROVIDER_ENV[provider]} or OMNISCOPE_API_KEY."
            )
        raise SystemExit(
            "Missing API key. Pass --api-key or set "
            "OMNISCOPE_<PROVIDER>_API_KEY or OMNISCOPE_API_KEY."
        )
    return key


def build_chat_model(
    *,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
    temperature: float = 0.2,
) -> BaseChatModel:
    """Build a LangChain chat model for CrewAI / LangGraph agents."""
    key = resolve_api_key(api_key, provider=provider)
    model = model.strip()
    if not model:
        raise SystemExit("Model id is required.")

    if provider == "openai":
        from langchain_openai import ChatOpenAI

        return ChatOpenAI(
            model=model,
            api_key=key,
            temperature=temperature,
        )

    if provider == "anthropic":
        from langchain_anthropic import ChatAnthropic

        return ChatAnthropic(
            model=model,
            api_key=key,
            temperature=temperature,
        )

    if provider == "gemini":
        from langchain_google_genai import ChatGoogleGenerativeAI

        return ChatGoogleGenerativeAI(
            model=model,
            google_api_key=key,
            temperature=temperature,
        )

    if provider == "deepseek":
        from langchain_openai import ChatOpenAI

        return ChatOpenAI(
            model=model,
            api_key=key,
            base_url=DEEPSEEK_BASE_URL,
            temperature=temperature,
        )

    if provider == "grok":
        from langchain_openai import ChatOpenAI

        return ChatOpenAI(
            model=model,
            api_key=key,
            base_url=GROK_BASE_URL,
            temperature=temperature,
        )

    if provider == "custom":
        from langchain_openai import ChatOpenAI

        url = (base_url or "").strip()
        if not url:
            raise SystemExit("--base-url is required for custom provider.")
        return ChatOpenAI(
            model=model,
            api_key=key,
            base_url=url,
            temperature=temperature,
        )

    raise SystemExit(f"Unknown provider: {provider}")


def build_crewai_llm(
    *,
    provider: Provider,
    model: str,
    api_key: str | None = None,
    base_url: str | None = None,
    temperature: float = 0.2,
) -> Any:
    """CrewAI LLM wrapper using the same provider mapping."""
    from crewai import LLM

    key = resolve_api_key(api_key, provider=provider)
    model = model.strip()
    if not model:
        raise SystemExit("Model id is required.")

    if provider == "openai":
        return LLM(
            model=f"openai/{model}",
            api_key=key,
            temperature=temperature,
        )
    if provider == "anthropic":
        return LLM(
            model=f"anthropic/{model}",
            api_key=key,
            temperature=temperature,
        )
    if provider == "gemini":
        return LLM(
            model=f"gemini/{model}",
            api_key=key,
            temperature=temperature,
        )
    if provider == "deepseek":
        return LLM(
            model=f"openai/{model}",
            api_key=key,
            base_url=DEEPSEEK_BASE_URL,
            temperature=temperature,
        )
    if provider == "grok":
        return LLM(
            model=f"openai/{model}",
            api_key=key,
            base_url=GROK_BASE_URL,
            temperature=temperature,
        )
    if provider == "custom":
        url = (base_url or "").strip()
        if not url:
            raise SystemExit("--base-url is required for custom provider.")
        return LLM(
            model=f"openai/{model}",
            api_key=key,
            base_url=url,
            temperature=temperature,
        )
    raise SystemExit(f"Unknown provider: {provider}")


def add_llm_args(parser: Any) -> None:
    parser.add_argument(
        "--provider",
        choices=["gemini", "openai", "anthropic", "deepseek", "grok", "custom"],
        default="openai",
        help="External LLM provider",
    )
    parser.add_argument("--model", required=True, help="Model id")
    parser.add_argument(
        "--api-key",
        default=None,
        help=(
            "API key (default: OMNISCOPE_<PROVIDER>_API_KEY, "
            "then OMNISCOPE_API_KEY)"
        ),
    )
    parser.add_argument(
        "--base-url",
        default=None,
        help="OpenAI-compatible base URL (custom provider)",
    )
