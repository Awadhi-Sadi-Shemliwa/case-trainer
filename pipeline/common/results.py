"""ResultStore: the only place numbers shown in the app may come from.

Spec §2: the pipeline writes expected_results.json per case; every number shown in the app must be
a key in it; a pytest asserts each value; the content build fails if a referenced key is missing.

Each entry: value, unit, description, display (formatted string), produced_by (module:function).
"""

from __future__ import annotations

import inspect
import json
import math
import re
from pathlib import Path
from typing import Any

RESULTS_FILE = "expected_results.json"
KEY_RE = re.compile(r"^[a-z][a-z0-9_]*$")


class ResultError(ValueError):
    pass


def format_value(value: Any, decimals: int | None, pct: bool = False) -> str:
    if isinstance(value, bool) or isinstance(value, str):
        return str(value)
    if pct:
        v = float(value) * 100.0
        return f"{v:.{decimals if decimals is not None else 1}f}%"
    if isinstance(value, int) and decimals is None:
        return f"{value:,}" if abs(value) >= 10000 else str(value)
    d = 2 if decimals is None else decimals
    return f"{float(value):.{d}f}"


class ResultStore:
    def __init__(self, case_dir: Path | str):
        self.case_dir = Path(case_dir)
        self.path = self.case_dir / RESULTS_FILE
        self.results: dict[str, dict[str, Any]] = {}

    def put(
        self,
        key: str,
        value: Any,
        unit: str,
        description: str,
        decimals: int | None = None,
        pct: bool = False,
        overwrite: bool = False,
    ) -> Any:
        """Store one result. `pct=True` means value is a fraction (0.25) displayed as '25.0%'."""
        if not KEY_RE.match(key):
            raise ResultError(f"bad key {key!r}: use lower_snake_case")
        if key in self.results and not overwrite:
            raise ResultError(f"duplicate key {key!r}")
        if not description.strip():
            raise ResultError(f"{key}: description required")
        # numpy scalars -> python
        if hasattr(value, "item") and not isinstance(value, (str, bytes)):
            value = value.item()
        if isinstance(value, float) and not math.isfinite(value):
            raise ResultError(f"{key}: non-finite value {value}")
        if not isinstance(value, (int, float, str, bool)):
            raise ResultError(f"{key}: unsupported type {type(value).__name__}")
        caller = inspect.stack()[1]
        module = inspect.getmodule(caller.frame)
        self.results[key] = {
            "value": value,
            "unit": unit,
            "description": description.strip(),
            "display": format_value(value, decimals, pct),
            "produced_by": f"{module.__name__ if module else '?'}:{caller.function}",
        }
        return value

    def get(self, key: str) -> Any:
        return self.results[key]["value"]

    def save(self) -> Path:
        self.path.write_text(
            json.dumps(dict(sorted(self.results.items())), indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        return self.path

    @staticmethod
    def load(case_dir: Path | str) -> dict[str, dict[str, Any]]:
        p = Path(case_dir) / RESULTS_FILE
        if not p.exists():
            return {}
        return json.loads(p.read_text(encoding="utf-8"))
