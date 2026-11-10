"""Provenance: save raw files untouched and record where every byte and every dropped row came from.

Spec §2: one provenance.json entry per raw file (source URL, retrieval timestamp, SHA-256,
licence/terms note, row count, columns) and every transformation applied, with counts of rows
dropped and why.

Usage in a case:
    prov = Provenance(CASE_DIR)
    path = prov.fetch("fred_T10Y2Y", url, "T10Y2Y.csv", licence_note="...")
    df = pd.read_csv(path, ...)
    prov.describe("fred_T10Y2Y", df)          # prints + records schema
    prov.log_transform("fred_T10Y2Y", "drop_na", rows_before, rows_after, reason="...")
    prov.save()
"""

from __future__ import annotations

import hashlib
import json
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pandas as pd
import requests

RAW_DIR = "raw"
PROVENANCE_FILE = "provenance.json"
DEFAULT_HEADERS = {
    # Some data portals (FRED among them) stall on requests without a browser-like User-Agent.
    "User-Agent": "Mozilla/5.0 (case-trainer research pipeline; +https://github.com/)",
    "Accept": "text/csv,application/json,*/*",
}


class ProvenanceError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _now_utc() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


@dataclass
class _Downloader:
    """Separated so tests can swap in a fake without network access."""

    timeout: float = 60.0
    retries: int = 3
    backoff: float = 3.0

    def get(self, url: str, headers: dict[str, str]) -> bytes:
        last: Exception | None = None
        for attempt in range(1, self.retries + 1):
            try:
                r = requests.get(url, headers=headers, timeout=self.timeout)
                r.raise_for_status()
                return r.content
            except requests.RequestException as e:  # pragma: no cover - network dependent
                last = e
                if attempt < self.retries:
                    time.sleep(self.backoff * attempt)
        raise ProvenanceError(f"Download failed after {self.retries} attempts: {url}\n{last}")


class Provenance:
    def __init__(self, case_dir: Path | str, downloader: _Downloader | None = None):
        self.case_dir = Path(case_dir)
        self.raw_dir = self.case_dir / RAW_DIR
        self.path = self.case_dir / PROVENANCE_FILE
        self.downloader = downloader or _Downloader()
        if self.path.exists():
            self.data: dict[str, Any] = json.loads(self.path.read_text(encoding="utf-8"))
        else:
            self.data = {"datasets": {}, "transforms": []}
        self.data.setdefault("datasets", {})
        self.data.setdefault("transforms", [])

    # ------------------------------------------------------------------ download
    def fetch(
        self,
        key: str,
        url: str,
        filename: str,
        licence_note: str,
        source_page: str | None = None,
        refresh: bool = False,
        headers: dict[str, str] | None = None,
        extra: dict[str, Any] | None = None,
    ) -> Path:
        """Download `url` to raw/<filename> byte-for-byte and record it.

        If the file already exists and refresh=False, the cached copy is used (so results stay
        reproducible); its SHA-256 must match the recorded one, otherwise we raise.
        """
        if not licence_note.strip():
            raise ProvenanceError(f"{key}: licence_note is required")
        self.raw_dir.mkdir(parents=True, exist_ok=True)
        dest = self.raw_dir / filename
        entry = self.data["datasets"].get(key)

        if dest.exists() and not refresh:
            digest = sha256_file(dest)
            if entry and entry.get("sha256") and entry["sha256"] != digest:
                raise ProvenanceError(
                    f"{key}: raw file {dest} changed on disk (sha256 mismatch). "
                    "Re-download explicitly with refresh=True and record why."
                )
            if entry:
                return dest
            retrieved = None  # file present but never recorded (e.g. copied in by hand)
        else:
            content = self.downloader.get(url, {**DEFAULT_HEADERS, **(headers or {})})
            dest.write_bytes(content)
            digest = sha256_file(dest)
            retrieved = _now_utc()

        self.data["datasets"][key] = {
            **(entry or {}),
            "key": key,
            "url": url,
            "source_page": source_page,
            "file": f"{RAW_DIR}/{filename}",
            "retrieved_utc": retrieved or (entry or {}).get("retrieved_utc"),
            "sha256": digest,
            "bytes": dest.stat().st_size,
            "licence_note": licence_note,
            **(extra or {}),
        }
        return dest

    # ------------------------------------------------------------------ schema
    def describe(self, key: str, df: pd.DataFrame, print_schema: bool = True, head_rows: int = 5) -> dict:
        """Record (and print) the schema of a loaded raw file: columns, dtypes, head, row count,
        missing values per column. Spec §2: print the schema before writing code that uses it."""
        if key not in self.data["datasets"]:
            raise ProvenanceError(f"{key}: describe() called before fetch()")
        schema = {
            "rows": int(len(df)),
            "columns": [str(c) for c in df.columns],
            "dtypes": {str(c): str(t) for c, t in df.dtypes.items()},
            "missing": {str(c): int(n) for c, n in df.isna().sum().items()},
            "head": df.head(head_rows).astype(str).to_dict(orient="records"),
        }
        self.data["datasets"][key]["schema"] = schema
        if print_schema:
            print(f"=== schema: {key} ===")
            print(f"rows: {schema['rows']}")
            for c in schema["columns"]:
                print(f"  {c:<24} {schema['dtypes'][c]:<16} missing={schema['missing'][c]}")
            print(df.head(head_rows).to_string())
        return schema

    def annotate(self, key: str, **fields: Any) -> None:
        """Attach verified metadata (units, frequency, title) checked on the source page."""
        if key not in self.data["datasets"]:
            raise ProvenanceError(f"{key}: annotate() called before fetch()")
        self.data["datasets"][key].update(fields)

    # ------------------------------------------------------------------ transforms
    def log_transform(
        self,
        dataset: str,
        step_id: str,
        rows_before: int,
        rows_after: int,
        reason: str,
        details: dict[str, Any] | None = None,
    ) -> dict:
        """Record one transformation. Any change in row count needs a non-empty reason.

        step_id is stable and is referenced by `cleaning_justification` steps in content.yaml.
        """
        if not reason or not reason.strip():
            raise ProvenanceError(f"{dataset}/{step_id}: every transform needs a reason")
        if any(t["id"] == step_id for t in self.data["transforms"]):
            # re-running a pipeline replaces the entry rather than duplicating it
            self.data["transforms"] = [t for t in self.data["transforms"] if t["id"] != step_id]
        rec = {
            "id": step_id,
            "dataset": dataset,
            "rows_before": int(rows_before),
            "rows_after": int(rows_after),
            "rows_dropped": int(rows_before) - int(rows_after),
            "reason": reason.strip(),
            "details": details or {},
        }
        self.data["transforms"].append(rec)
        return rec

    def transform(self, step_id: str) -> dict:
        for t in self.data["transforms"]:
            if t["id"] == step_id:
                return t
        raise KeyError(step_id)

    # ------------------------------------------------------------------ persistence
    def verify_hashes(self) -> list[str]:
        """Return a list of problems (missing raw file / SHA mismatch). Empty list = OK."""
        problems = []
        for key, e in self.data["datasets"].items():
            p = self.case_dir / e["file"]
            if not p.exists():
                # Large raw data kept out of git on purpose (committed: false): absent is fine, but whenever the
                # file is present (re-downloaded) its hash is still checked below.
                if e.get("committed") is False:
                    continue
                problems.append(f"{key}: missing {p}")
            elif sha256_file(p) != e["sha256"]:
                problems.append(f"{key}: sha256 mismatch for {p}")
        return problems

    def save(self) -> Path:
        self.path.write_text(json.dumps(self.data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        return self.path
