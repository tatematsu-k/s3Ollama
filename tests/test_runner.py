import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from job import runner


def test_required_env(monkeypatch):
    monkeypatch.delenv("MISSING_ENV", raising=False)
    with pytest.raises(RuntimeError):
        runner._required_env("MISSING_ENV")

    monkeypatch.setenv("MISSING_ENV", "value")
    assert runner._required_env("MISSING_ENV") == "value"


def test_build_prompt_injects_context(tmp_path: Path):
    prompt = "Answer based on:\n{{context}}"
    ctx1 = tmp_path / "ctx1.txt"
    ctx1.write_text("alpha", encoding="utf-8")
    ctx2 = tmp_path / "ctx2.txt"
    ctx2.write_text("beta", encoding="utf-8")

    result = runner._build_prompt(prompt, [ctx1, ctx2])

    assert "alpha" in result and "beta" in result
    assert "{{context}}" not in result


def test_build_prompt_appends_context_when_placeholder_missing(tmp_path: Path):
    prompt = "Summarise the following information."
    ctx = tmp_path / "ctx.txt"
    ctx.write_text("important context", encoding="utf-8")

    result = runner._build_prompt(prompt, [ctx])

    assert result.endswith("important context")
