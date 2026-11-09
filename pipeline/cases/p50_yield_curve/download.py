"""P50 · Download the three FRED series untouched and record provenance.

Series verified on their FRED pages on 2026-11-05 (title / units / frequency recorded below).
FRED marks these series "Copyrighted: Citation Required": we cite FRED in provenance, charts and the
case text, and redistribute only the raw CSVs needed to reproduce the results.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from common.provenance import Provenance

CASE_DIR = Path(__file__).resolve().parent
FRED_CSV = "https://fred.stlouisfed.org/graph/fredgraph.csv?id={sid}"
FRED_PAGE = "https://fred.stlouisfed.org/series/{sid}"
CITATION = ("Federal Reserve Bank of St. Louis, {title} [{sid}], retrieved from FRED, "
            "Federal Reserve Bank of St. Louis; https://fred.stlouisfed.org/series/{sid}")

SERIES = {
    "fred_T10Y2Y": {
        "sid": "T10Y2Y",
        "title": "10-Year Treasury Constant Maturity Minus 2-Year Treasury Constant Maturity",
        "units": "Percent, Not Seasonally Adjusted", "frequency": "Daily",
    },
    "fred_T10Y3M": {
        "sid": "T10Y3M",
        "title": "10-Year Treasury Constant Maturity Minus 3-Month Treasury Constant Maturity",
        "units": "Percent, Not Seasonally Adjusted", "frequency": "Daily",
    },
    "fred_USREC": {
        "sid": "USREC",
        "title": "NBER based Recession Indicators for the United States from the Period following the Peak through the Trough",
        "units": "+1 or 0, Not Seasonally Adjusted", "frequency": "Monthly",
        "dating_note": "Trough method: peak month excluded, trough month included (FRED series notes).",
    },
}


def download(refresh: bool = False) -> Provenance:
    prov = Provenance(CASE_DIR)
    for key, meta in SERIES.items():
        sid = meta["sid"]
        path = prov.fetch(
            key,
            FRED_CSV.format(sid=sid),
            f"{sid}.csv",
            licence_note="FRED: 'Copyrighted: Citation Required'. Cite as: " + CITATION.format(title=meta["title"], sid=sid),
            source_page=FRED_PAGE.format(sid=sid),
            refresh=refresh,
        )
        prov.annotate(key, **{k: v for k, v in meta.items()}, verified_on="2026-11-05",
                      verified_how="Opened FRED series page; title/units/frequency copied from page")
        # Spec §2: print the schema of every raw file before writing code that uses it.
        # dtype=str on purpose: we want to SEE what the missing-value marker looks like, not let pandas guess.
        raw = pd.read_csv(path, dtype=str, keep_default_na=False)
        prov.describe(key, raw)
        non_numeric = raw.iloc[:, 1][pd.to_numeric(raw.iloc[:, 1], errors="coerce").isna()]
        print(f"{key}: non-numeric value markers -> {non_numeric.value_counts().to_dict()}")
        prov.annotate(key, non_numeric_markers=non_numeric.value_counts().to_dict())
    prov.save()
    return prov


if __name__ == "__main__":
    download()
