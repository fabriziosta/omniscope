"""Assert CLI trade JSON contract stays aligned with Head Trader prompts."""

from __future__ import annotations

from omniscope_agents.trade_schema import TRADE_JSON_EXAMPLE, TRADE_JSON_KEYS


def test_trade_json_keys_canonical() -> None:
    assert TRADE_JSON_KEYS == (
        "ticker",
        "action",
        "quantity",
        "rationale",
        "risk_approved",
    )


def test_trade_json_example_embeds_schema_keys() -> None:
    for key in TRADE_JSON_KEYS:
        assert f'"{key}"' in TRADE_JSON_EXAMPLE
