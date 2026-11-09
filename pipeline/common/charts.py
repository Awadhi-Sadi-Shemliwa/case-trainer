"""Chart export: (a) JSON the Flutter app renders interactively, (b) PNG fallback for phones.

Schema (one JSON file per chart, validated with pydantic):

    {
      "schema_version": 1, "id": "p50_spread_recessions", "type": "line",
      "title": "...", "subtitle": "...",
      "x_axis": {"title": "Month", "unit": null, "kind": "date"},
      "y_axis": {"title": "10y minus 2y", "unit": "percentage points", "kind": "number"},
      "series": [{"name": "...", "x": ["1976-06-01", ...], "y": [..], "unit": "pp",
                  "role": "data", "original_points": 600}],
      "shaded_regions": [{"start": "2001-03-01", "end": "2001-11-01", "label": "NBER recession"}],
      "annotations": [{"x": ..., "y": ..., "text": "..."}],
      "reference_lines": [{"axis": "y", "value": 0, "label": "zero = inverted"}],
      "histogram": null | {"bin_edges": [...], "counts": {"series name": [...]}},
      "box": null | [{"category": "...", "whisker_low":..,"q1":..,"median":..,"q3":..,"whisker_high":..,"outliers":[..]}],
      "heatmap": null | {"x_categories": [...], "y_categories": [...], "values": [[...]], "value_unit": "..."},
      "source_note": "Data: FRED ...", "result_keys": ["..."]
    }

Types: line, scatter, histogram, box, bar, stacked_bar, heatmap.
Line series longer than MAX_POINTS are downsampled with LTTB; the full data stays in the pipeline.
"""

from __future__ import annotations

import json
import math
from datetime import date, datetime
from pathlib import Path
from typing import Any, Literal

import numpy as np
import pandas as pd
from pydantic import BaseModel, Field, field_validator, model_validator

MAX_POINTS = 2000
SCHEMA_VERSION = 1
ChartType = Literal["line", "scatter", "histogram", "box", "bar", "stacked_bar", "heatmap"]


# --------------------------------------------------------------------------- LTTB
def lttb(x: np.ndarray, y: np.ndarray, threshold: int) -> np.ndarray:
    """Largest-Triangle-Three-Buckets (Steinarsson 2013). Returns indices of kept points.

    Keeps first and last points; preserves visual peaks/troughs far better than every-nth sampling.
    """
    n = len(x)
    if threshold >= n or threshold < 3:
        return np.arange(n)
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    every = (n - 2) / (threshold - 2)
    keep = [0]
    a = 0
    for i in range(threshold - 2):
        start = int(math.floor((i + 1) * every)) + 1
        end = min(int(math.floor((i + 2) * every)) + 1, n)
        # average of next bucket
        nxt_start = end
        nxt_end = min(int(math.floor((i + 3) * every)) + 1, n)
        if nxt_start >= n:
            avg_x, avg_y = x[n - 1], y[n - 1]
        else:
            avg_x = x[nxt_start:nxt_end].mean() if nxt_end > nxt_start else x[n - 1]
            avg_y = y[nxt_start:nxt_end].mean() if nxt_end > nxt_start else y[n - 1]
        rx, ry = x[start:end], y[start:end]
        if len(rx) == 0:
            continue
        area = np.abs((x[a] - avg_x) * (ry - y[a]) - (x[a] - rx) * (avg_y - y[a]))
        a = start + int(np.argmax(area))
        keep.append(a)
    keep.append(n - 1)
    return np.array(sorted(set(keep)))


# --------------------------------------------------------------------------- schema
def _jsonable(v: Any) -> Any:
    if isinstance(v, (pd.Timestamp, datetime)):
        return v.strftime("%Y-%m-%d")
    if isinstance(v, date):
        return v.isoformat()
    if isinstance(v, (np.integer,)):
        return int(v)
    if isinstance(v, (np.floating, float)):
        f = float(v)
        return None if not math.isfinite(f) else f
    if isinstance(v, np.bool_):
        return bool(v)
    return v


class Axis(BaseModel):
    title: str
    unit: str | None = None
    kind: Literal["number", "date", "category"] = "number"
    min: float | None = None
    max: float | None = None


class Series(BaseModel):
    name: str
    x: list[Any]
    y: list[float | None]
    unit: str | None = None
    role: Literal["data", "fitted", "benchmark"] = "data"
    original_points: int | None = None

    @model_validator(mode="after")
    def _same_len(self):
        if len(self.x) != len(self.y):
            raise ValueError(f"series {self.name!r}: x and y lengths differ ({len(self.x)} vs {len(self.y)})")
        return self


class ShadedRegion(BaseModel):
    start: Any
    end: Any
    label: str


class Annotation(BaseModel):
    x: Any
    y: float
    text: str


class ReferenceLine(BaseModel):
    axis: Literal["x", "y"]
    value: Any
    label: str


class Histogram(BaseModel):
    bin_edges: list[float]
    counts: dict[str, list[int]]

    @model_validator(mode="after")
    def _bins(self):
        for k, c in self.counts.items():
            if len(c) != len(self.bin_edges) - 1:
                raise ValueError(f"histogram {k!r}: need len(bin_edges)-1 counts")
        return self


class BoxStat(BaseModel):
    category: str
    whisker_low: float
    q1: float
    median: float
    q3: float
    whisker_high: float
    outliers: list[float] = Field(default_factory=list)


class Heatmap(BaseModel):
    x_categories: list[str]
    y_categories: list[str]
    values: list[list[float | None]]
    value_unit: str | None = None

    @model_validator(mode="after")
    def _shape(self):
        if len(self.values) != len(self.y_categories) or any(len(r) != len(self.x_categories) for r in self.values):
            raise ValueError("heatmap values must be len(y_categories) x len(x_categories)")
        return self


class Chart(BaseModel):
    schema_version: int = SCHEMA_VERSION
    id: str
    type: ChartType
    title: str
    subtitle: str | None = None
    x_axis: Axis
    y_axis: Axis
    series: list[Series] = Field(default_factory=list)
    shaded_regions: list[ShadedRegion] = Field(default_factory=list)
    annotations: list[Annotation] = Field(default_factory=list)
    reference_lines: list[ReferenceLine] = Field(default_factory=list)
    histogram: Histogram | None = None
    box: list[BoxStat] | None = None
    heatmap: Heatmap | None = None
    source_note: str
    result_keys: list[str] = Field(default_factory=list)

    @field_validator("id")
    @classmethod
    def _id(cls, v):
        if not v.replace("_", "").isalnum() or not v.islower():
            raise ValueError("chart id must be lower_snake_case")
        return v

    @model_validator(mode="after")
    def _by_type(self):
        t = self.type
        if t in ("line", "scatter", "bar", "stacked_bar") and not self.series:
            raise ValueError(f"{t} chart needs series")
        if t == "histogram" and self.histogram is None:
            raise ValueError("histogram chart needs histogram")
        if t == "box" and not self.box:
            raise ValueError("box chart needs box stats")
        if t == "heatmap" and self.heatmap is None:
            raise ValueError("heatmap chart needs heatmap")
        for s in self.series:
            if len(s.x) > MAX_POINTS:
                raise ValueError(f"series {s.name!r} has {len(s.x)} points > {MAX_POINTS}; downsample first")
        return self


def make_series(name: str, x, y, unit: str | None = None, role: str = "data", downsample: bool = True) -> Series:
    """Build a Series from array-likes; LTTB-downsample line-like data above MAX_POINTS."""
    x = list(x)
    y = [None if (v is None or (isinstance(v, float) and not math.isfinite(v))) else float(v) for v in y]
    n = len(x)
    if downsample and n > MAX_POINTS:
        xs = pd.Series(x)
        if pd.api.types.is_datetime64_any_dtype(xs) or isinstance(x[0], (pd.Timestamp, datetime, date)):
            xnum = pd.to_datetime(xs).astype("int64").to_numpy(dtype=float)
        else:
            xnum = np.asarray(x, dtype=float)
        ynum = np.array([np.nan if v is None else v for v in y])
        mask = ~np.isnan(ynum)
        idx_valid = np.flatnonzero(mask)
        keep = idx_valid[lttb(xnum[mask], ynum[mask], MAX_POINTS - 1)]
        x = [x[i] for i in keep]
        y = [y[i] for i in keep]
    return Series(name=name, x=[_jsonable(v) for v in x], y=y, unit=unit, role=role, original_points=n)


def regions_from_indicator(dates, indicator, label: str) -> list[ShadedRegion]:
    """Contiguous runs where indicator == 1 -> shaded regions (e.g. NBER recession months)."""
    regions, start, prev = [], None, None
    for d, v in zip(dates, indicator):
        if v == 1 and start is None:
            start = d
        if v != 1 and start is not None:
            regions.append(ShadedRegion(start=_jsonable(start), end=_jsonable(prev), label=label))
            start = None
        prev = d
    if start is not None:
        regions.append(ShadedRegion(start=_jsonable(start), end=_jsonable(prev), label=label))
    return regions


# --------------------------------------------------------------------------- export
PHONE_STYLE = {
    "figure.figsize": (5.4, 4.2),   # ~1080 px wide at 200 dpi: S21 portrait width
    "figure.dpi": 200,
    "font.size": 11,
    "axes.titlesize": 13,
    "axes.labelsize": 11,
    "xtick.labelsize": 10,
    "ytick.labelsize": 10,
    "legend.fontsize": 9,
    "lines.linewidth": 1.6,
    "axes.grid": True,
    "grid.alpha": 0.3,
}
PALETTE = ["#2563eb", "#dc2626", "#059669", "#d97706", "#7c3aed", "#0891b2"]


def _axis_label(a: Axis) -> str:
    return f"{a.title} ({a.unit})" if a.unit else a.title


def _to_plot_x(vals, kind):
    return pd.to_datetime(vals) if kind == "date" else vals


def render_png(chart: Chart, path: Path) -> Path:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    with plt.rc_context(PHONE_STYLE):
        fig, ax = plt.subplots()
        kind = chart.x_axis.kind
        for r in chart.shaded_regions:
            ax.axvspan(_to_plot_x([r.start], kind)[0], _to_plot_x([r.end], kind)[0], color="#9ca3af", alpha=0.35, lw=0)
        t = chart.type
        if t in ("line", "scatter"):
            for i, s in enumerate(chart.series):
                xs = _to_plot_x(s.x, kind)
                c = PALETTE[i % len(PALETTE)]
                y = [np.nan if v is None else v for v in s.y]
                if t == "scatter" and s.role == "data":
                    ax.scatter(xs, y, s=8, alpha=0.6, color=c, label=s.name)
                else:
                    ax.plot(xs, y, color=c, label=s.name, ls="--" if s.role != "data" else "-")
        elif t in ("bar", "stacked_bar"):
            cats = chart.series[0].x
            pos = np.arange(len(cats))
            bottom = np.zeros(len(cats))
            width = 0.8 if t == "stacked_bar" else 0.8 / len(chart.series)
            for i, s in enumerate(chart.series):
                y = np.array([0 if v is None else v for v in s.y])
                if t == "stacked_bar":
                    ax.bar(pos, y, bottom=bottom, color=PALETTE[i % len(PALETTE)], label=s.name)
                    bottom += y
                else:
                    ax.bar(pos + i * width - 0.4 + width / 2, y, width, color=PALETTE[i % len(PALETTE)], label=s.name)
            ax.set_xticks(pos, [str(c) for c in cats], rotation=45, ha="right")
        elif t == "histogram":
            h = chart.histogram
            edges = np.array(h.bin_edges)
            for i, (name, counts) in enumerate(h.counts.items()):
                ax.stairs(counts, edges, fill=True, alpha=0.5, color=PALETTE[i % len(PALETTE)], label=name)
        elif t == "box":
            stats = [
                {"label": b.category, "whislo": b.whisker_low, "q1": b.q1, "med": b.median,
                 "q3": b.q3, "whishi": b.whisker_high, "fliers": b.outliers}
                for b in chart.box
            ]
            ax.bxp(stats, showfliers=True)
        elif t == "heatmap":
            hm = chart.heatmap
            arr = np.array([[np.nan if v is None else v for v in r] for r in hm.values])
            im = ax.imshow(arr, aspect="auto", cmap="viridis")
            ax.set_xticks(range(len(hm.x_categories)), hm.x_categories, rotation=90)
            ax.set_yticks(range(len(hm.y_categories)), hm.y_categories)
            fig.colorbar(im, ax=ax, label=hm.value_unit or "")
            ax.grid(False)
        for rl in chart.reference_lines:
            if rl.axis == "y":
                ax.axhline(rl.value, color="#111827", lw=0.9, ls=":")
            else:
                ax.axvline(_to_plot_x([rl.value], kind)[0], color="#111827", lw=0.9, ls=":")
        for an in chart.annotations:
            ax.annotate(an.text, (_to_plot_x([an.x], kind)[0], an.y), fontsize=8)
        ax.set_title(chart.title)
        ax.set_xlabel(_axis_label(chart.x_axis))
        ax.set_ylabel(_axis_label(chart.y_axis))
        if chart.x_axis.min is not None or chart.x_axis.max is not None:
            ax.set_xlim(chart.x_axis.min, chart.x_axis.max)
        if chart.y_axis.min is not None or chart.y_axis.max is not None:
            ax.set_ylim(chart.y_axis.min, chart.y_axis.max)
        if t not in ("heatmap", "box") and (chart.series or chart.histogram):
            ax.legend(loc="best")
        if kind == "date":
            fig.autofmt_xdate()  # rotate date ticks so they never overlap on a phone-width PNG
        fig.text(0.01, 0.005, chart.source_note, fontsize=6, color="#6b7280")
        fig.tight_layout(rect=(0, 0.02, 1, 1))
        fig.savefig(path)
        plt.close(fig)
    return path


def export_chart(chart: Chart, out_dir: Path | str) -> tuple[Path, Path]:
    """Validate and write <id>.json + <id>.png into out_dir (normally <case>/charts/)."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    chart = Chart.model_validate(chart.model_dump())  # re-validate after any mutation
    jp = out / f"{chart.id}.json"
    jp.write_text(json.dumps(chart.model_dump(mode="json"), ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    pp = render_png(chart, out / f"{chart.id}.png")
    return jp, pp
