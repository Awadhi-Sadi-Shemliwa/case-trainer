"""P13 · Clean OpenF1 race laps into a lap table with one drop reason per lap (or none = clean lap).

Writes committed aggregates (CC BY-NC-SA 4.0, derived from OpenF1):
  aggregates/laps.csv.gz   every lap of every DRY race, with tyre fields and the first drop reason that applies
  aggregates/stints.csv    every stint of every dry race (stint length, whether it ended in a pit stop)
  aggregates/pit_stops.csv in-lap + out-lap time loss per pit stop
  aggregates/races.csv     one row per race: circuit, wet flag, lap counts
analyse.py reads only these, so the tests run in a fresh clone without the raw JSON.

Drop reasons are applied in this order and each lap gets the FIRST one that applies (counts logged once, as totals).
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd

from common.io import capture_output
from common.provenance import Provenance

CASE_DIR = Path(__file__).resolve().parent
RAW = CASE_DIR / "raw"
AGG = CASE_DIR / "aggregates"
SEASONS = (2023, 2024, 2025)
DRY = {"SOFT", "MEDIUM", "HARD"}
TRAFFIC_GAP_S = 1.0       # median gap to the car ahead during the lap below this = dirty air (DRS-gap convention)
INCIDENT_S = 5.0          # slower than the stint's median clean lap by more than this = incident / damage / blue flags
RESTART_LAPS = 1          # laps after a SC/VSC/red period that are also dropped (restart, tyres and brakes cold)

REASONS = {
    "no_time": "No lap time recorded, so the lap cannot be modelled.",
    "lap1": "Lap 1 starts from a standstill; its time measures the start, not tyre wear.",
    "no_stint": "The lap is not inside any stint, so compound and tyre age are unknown.",
    "out_lap": "Out-lap: includes the pit exit and cold tyres, not racing pace.",
    "in_lap": "In-lap: includes slowing for the pit entry, not racing pace.",
    "neutralised": ("Safety Car, Virtual Safety Car or red flag during the lap (or the restart lap after it): "
                    "everyone drives a set slow pace, which says nothing about the tyres."),
    "rain": "Rain was falling (weather feed) when the lap started: a wet track on slicks, not tyre wear.",
    "traffic": (f"Median gap to the car ahead during the lap under {TRAFFIC_GAP_S:g} s: dirty air slows the car "
                "and overheats the tyres, which would be mistaken for wear."),
    "incident": (f"More than {INCIDENT_S:g} s slower than the stint's median lap: spins, damage, blue flags or "
                 "long battles, not gradual wear."),
}
ORDER = list(REASONS)


def load(ep: str, sk: int) -> pd.DataFrame:
    return pd.DataFrame(json.loads((RAW / f"{ep}_{sk}.json").read_text(encoding="utf-8")))


def sessions() -> pd.DataFrame:
    rows = []
    for y in SEASONS:
        rows += [s for s in json.loads((RAW / f"sessions_{y}.json").read_text(encoding="utf-8")) if not s.get("is_cancelled")]
    return pd.DataFrame(rows).sort_values("date_start").reset_index(drop=True)


def ts(s: pd.Series) -> pd.Series:
    return pd.to_datetime(s, utc=True, format="ISO8601")


def windows(rc: pd.DataFrame) -> list[tuple[pd.Timestamp, pd.Timestamp]]:
    """Neutralised periods from race control: SC deployed..in this lap, VSC deployed..ending, red flag (instant)."""
    if rc.empty:
        return []
    rc = rc.assign(t=ts(rc["date"])).sort_values("t")
    out, open_sc, open_vsc = [], None, None
    for r in rc.itertuples():
        msg = str(r.message).upper()
        if r.category == "SafetyCar":
            if msg.startswith("VIRTUAL SAFETY CAR DEPLOYED"):
                open_vsc = r.t
            elif msg.startswith("VIRTUAL SAFETY CAR ENDING") and open_vsc is not None:
                out.append((open_vsc, r.t)); open_vsc = None
            elif msg.startswith("SAFETY CAR DEPLOYED"):
                open_sc = r.t
            elif msg.startswith("SAFETY CAR IN THIS LAP") and open_sc is not None:
                out.append((open_sc, r.t)); open_sc = None
        elif r.flag == "RED":
            out.append((r.t, r.t))
    end = rc["t"].max()
    out += [(t, end) for t in (open_sc, open_vsc) if t is not None]   # never closed: neutral to the end of the log
    return out


def race_laps(s: pd.Series) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, dict]:
    sk = int(s["session_key"])
    laps, st = load("laps", sk), load("stints", sk)
    rc, iv, wx = load("race_control", sk), load("intervals", sk), load("weather", sk)
    compounds = set(st["compound"].dropna().str.upper()) if not st.empty else set()
    rain = bool((wx["rainfall"] > 0).any()) if not wx.empty else False
    wet = bool(compounds - DRY)   # inters/wets used; rain on slicks is handled lap by lap ("rain")
    info = {"session_key": sk, "year": int(s["year"]), "circuit": s["circuit_short_name"], "country": s["country_name"],
            "date": s["date_start"][:10], "wet": wet, "rain_recorded": rain, "laps_raw": len(laps),
            "non_dry_compounds": ",".join(sorted(compounds - DRY))}
    if wet or laps.empty:
        return pd.DataFrame(), pd.DataFrame(), pd.DataFrame(), info

    laps = laps[["driver_number", "lap_number", "date_start", "lap_duration", "is_pit_out_lap"]].copy()
    laps["start"] = ts(laps["date_start"])
    st = st.sort_values(["driver_number", "stint_number"])
    st["compound"] = st["compound"].str.upper()
    st["last_stint"] = st.groupby("driver_number")["stint_number"].transform("max") == st["stint_number"]

    # stint membership (lap inside [lap_start, lap_end]); a lap in two stints would be a data error
    m = laps.merge(st[["driver_number", "stint_number", "lap_start", "lap_end", "compound", "tyre_age_at_start",
                       "last_stint"]], on="driver_number", how="left")
    m = m[(m.lap_number >= m.lap_start) & (m.lap_number <= m.lap_end)]
    assert not m.duplicated(["driver_number", "lap_number"]).any(), f"session {sk}: lap in two stints"
    laps = laps.merge(m[["driver_number", "lap_number", "stint_number", "lap_start", "lap_end", "compound",
                         "tyre_age_at_start", "last_stint"]], on=["driver_number", "lap_number"], how="left")
    # >>> snippet: tyre_age
    # tyre age = laps already on the set when this lap starts (stints report age at fitting)
    laps["tyre_age"] = laps["tyre_age_at_start"] + (laps["lap_number"] - laps["lap_start"])
    # <<< snippet

    # neutralised: lap time window overlaps a SC/VSC/red period, plus the next RESTART_LAPS laps of each driver
    laps["end"] = laps["start"] + pd.to_timedelta(laps["lap_duration"].fillna(0), unit="s")
    neut = pd.Series(False, index=laps.index)
    for a, b in windows(rc):
        hit = (laps["start"] <= b) & (laps["end"] >= a) & laps["start"].notna()
        neut |= hit
        after = laps[(laps["start"] > b)].sort_values("start").groupby("driver_number").head(RESTART_LAPS).index
        neut.loc[after] = True
    laps["neutralised"] = neut

    # rain: the latest weather sample at or before the lap start shows rainfall
    laps["raining"] = False
    if not wx.empty and laps["start"].notna().any():
        w = wx.assign(t=ts(wx["date"])).sort_values("t")[["t", "rainfall"]]
        lp = laps[["start"]].dropna().reset_index().sort_values("start")
        r = pd.merge_asof(lp, w, left_on="start", right_on="t", direction="backward")
        laps.loc[r["index"], "raining"] = (r["rainfall"].fillna(0) > 0).to_numpy()

    # traffic: median interval to the car ahead over the samples taken during the lap
    laps["median_gap_ahead"] = np.nan
    if not iv.empty:
        iv = iv.assign(t=ts(iv["date"]), gap=pd.to_numeric(iv["interval"], errors="coerce")).dropna(subset=["t"])
        lp = laps.dropna(subset=["start"]).sort_values("start")
        tagged = pd.merge_asof(iv.sort_values("t"), lp[["driver_number", "lap_number", "start", "end"]],
                               left_on="t", right_on="start", by="driver_number", direction="backward")
        tagged = tagged[tagged["t"] <= tagged["end"]]
        med = tagged.groupby(["driver_number", "lap_number"])["gap"].median()
        laps = laps.set_index(["driver_number", "lap_number"])
        laps.loc[med.index, "median_gap_ahead"] = med
        laps = laps.reset_index()

    # >>> snippet: drop_rules
    conds = {
        "no_time": laps["lap_duration"].isna(),
        "lap1": laps["lap_number"] == 1,
        "no_stint": laps["stint_number"].isna(),
        "out_lap": laps["is_pit_out_lap"].fillna(False).astype(bool)
                   | ((laps["lap_number"] == laps["lap_start"]) & (laps["stint_number"] > 1)),
        "in_lap": (laps["lap_number"] == laps["lap_end"]) & ~laps["last_stint"].fillna(True).astype(bool),
        "neutralised": laps["neutralised"],
        "rain": laps["raining"],
        "traffic": laps["median_gap_ahead"] < TRAFFIC_GAP_S,
    }
    laps["drop_reason"] = None
    for r in ORDER[:-1]:
        laps.loc[laps["drop_reason"].isna() & conds[r].fillna(False), "drop_reason"] = r
    # <<< snippet
    # incident: compared with the stint's median among laps that survived the rules above
    keep = laps["drop_reason"].isna()
    med = laps[keep].groupby(["driver_number", "stint_number"])["lap_duration"].transform("median")
    laps["delta_to_stint_median"] = np.nan
    laps.loc[keep, "delta_to_stint_median"] = laps.loc[keep, "lap_duration"] - med
    laps.loc[keep & (laps["delta_to_stint_median"] > INCIDENT_S), "drop_reason"] = "incident"

    laps["session_key"] = sk
    laps["race_laps"] = int(laps["lap_number"].max())
    cols = ["session_key", "driver_number", "lap_number", "lap_duration", "stint_number", "compound", "tyre_age",
            "tyre_age_at_start", "median_gap_ahead", "delta_to_stint_median", "neutralised", "race_laps", "drop_reason"]
    out = laps[cols]

    stints = st.assign(session_key=sk, length=st["lap_end"] - st["lap_start"] + 1, ended_in_pit=~st["last_stint"])
    stints = stints[["session_key", "driver_number", "stint_number", "compound", "tyre_age_at_start", "lap_start",
                     "lap_end", "length", "ended_in_pit"]]

    # pit loss: in-lap + out-lap minus two of the driver's median clean laps; stops in neutralised laps excluded
    clean_med = out[out.drop_reason.isna()].groupby("driver_number")["lap_duration"].median()
    li = laps.set_index(["driver_number", "lap_number"])
    stops = []
    for r in stints[stints.ended_in_pit].itertuples():
        a, b = (r.driver_number, r.lap_end), (r.driver_number, r.lap_end + 1)
        if a in li.index and b in li.index and r.driver_number in clean_med.index:
            tin, tout = li.at[a, "lap_duration"], li.at[b, "lap_duration"]
            stops.append({"session_key": sk, "driver_number": r.driver_number, "lap": r.lap_end,
                          "in_lap": tin, "out_lap": tout, "median_clean": clean_med[r.driver_number],
                          "pit_loss": tin + tout - 2 * clean_med[r.driver_number],
                          "neutralised": bool(li.at[a, "neutralised"] or li.at[b, "neutralised"])})
    info.update(laps_dry=len(out), laps_clean=int(out.drop_reason.isna().sum()))
    return out, stints, pd.DataFrame(stops), info


def clean() -> None:
    AGG.mkdir(exist_ok=True)
    prov = Provenance(CASE_DIR)
    ses = sessions()
    L, S, P, R = [], [], [], []
    for s in ses.itertuples(index=False):
        laps, stints, stops, info = race_laps(pd.Series(s._asdict()))
        R.append(info)
        if not laps.empty:
            L.append(laps); S.append(stints); P.append(stops)
        print(f"{info['date']} {info['circuit']:<14} wet={info['wet']!s:<5} laps={info['laps_raw']:>5} "
              f"clean={info.get('laps_clean', 0):>5}")
    races = pd.DataFrame(R)
    laps = pd.concat(L, ignore_index=True)
    stints, stops = pd.concat(S, ignore_index=True), pd.concat(P, ignore_index=True)
    laps.to_csv(AGG / "laps.csv.gz", index=False, compression={"method": "gzip", "mtime": 0})
    stints.to_csv(AGG / "stints.csv", index=False)
    stops.to_csv(AGG / "pit_stops.csv", index=False)
    races.to_csv(AGG / "races.csv", index=False)

    total = int(races["laps_raw"].sum())
    dry = int(races.loc[~races.wet, "laps_raw"].sum())
    prov.log_transform("openf1_all", "wet_races_excluded", total, dry,
                       reason=("Races where intermediate or wet tyres were used are excluded: wet running is a different "
                               "tyre problem. Rain on slicks is handled lap by lap (drop_rain)."),
                       details={"races": int(races.wet.sum()), "of_races": len(races),
                                "which": races.loc[races.wet, ["date", "circuit"]].astype(str).agg(" ".join, axis=1).tolist()})
    before = len(laps)
    for r in ORDER:
        n = int((laps.drop_reason == r).sum())
        prov.log_transform("openf1_all", f"drop_{r}", before, before - n, reason=REASONS[r] + " Totals over all dry races.")
        before -= n
    prov.save()
    print(f"\n{len(races)} races, {int(races.wet.sum())} wet; {len(laps):,} dry laps -> {before:,} clean laps")
    print(laps.drop_reason.value_counts(dropna=False).to_string())


if __name__ == "__main__":
    with capture_output(CASE_DIR, "clean_log"):
        clean()
