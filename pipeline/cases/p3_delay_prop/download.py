"""P3 · Download BTS Reporting Carrier On-Time Performance monthly files (2025) untouched.

Source: US Bureau of Transportation Statistics, TranStats PREZIP. US government data (public domain).
The 12 zips are about 350 MB, so they are NOT committed (git-ignored); their SHA-256 is in provenance.json and
the committed aggregate tables (aggregates/) let the tests run without them. Re-download: run this file.
Field definitions are read from the readme.html shipped inside each zip (verified 2026-11-09).
"""

from __future__ import annotations

import io
import zipfile
from pathlib import Path

import pandas as pd

from common.provenance import Provenance

CASE_DIR = Path(__file__).resolve().parent
YEAR = 2025
URL = "https://transtats.bts.gov/PREZIP/On_Time_Reporting_Carrier_On_Time_Performance_1987_present_{year}_{month}.zip"
LICENCE = ("US Bureau of Transportation Statistics (TranStats), Reporting Carrier On-Time Performance. US federal "
           "government data, public domain. Cite: BTS, https://www.transtats.bts.gov/DatabaseInfo.asp?QO_VQ=EFD")


def key(month: int) -> str:
    return f"bts_ontime_{YEAR}_{month:02d}"


def csv_from_zip(path: Path) -> tuple[str, bytes]:
    with zipfile.ZipFile(path) as z:
        name = next(n for n in z.namelist() if n.lower().endswith(".csv"))
        return name, z.read(name)


def download(refresh: bool = False) -> Provenance:
    prov = Provenance(CASE_DIR)
    for m in range(1, 13):
        k = key(m)
        path = prov.fetch(k, URL.format(year=YEAR, month=m), f"ontime_{YEAR}_{m:02d}.zip", licence_note=LICENCE,
                          source_page="https://www.transtats.bts.gov/DatabaseInfo.asp?QO_VQ=EFD", refresh=refresh)
        name, raw = csv_from_zip(path)
        head = pd.read_csv(io.BytesIO(raw), nrows=5, dtype=str)
        rows = sum(1 for _ in io.BytesIO(raw)) - 1
        prov.data["datasets"][k]["schema"] = {
            "rows": rows, "columns": list(head.columns), "head": head.iloc[:3, :20].to_dict(orient="records"),
            "member": name}
        prov.annotate(k, year=YEAR, month=m, units="times hhmm local; delays in minutes",
                      verified_on="2026-11-09", verified_how="Field definitions read in the zip's readme.html",
                      committed=False)  # ~350 MB: git-ignored; hash checked whenever the file is present
        print(f"{k}: {rows:,} flights, {len(head.columns)} columns")
        prov.save()
    return prov


if __name__ == "__main__":
    download()
