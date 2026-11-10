"""Cross-checks that keep prose, labels and docs consistent with the computed results.

Added after the 2026-11-10 cross-check found: result counts typed as words ("three test recessions"), an
acceptable calibration answer missing the pandemic caveat, and stale "N flagged" counts in docs. Each test
below would have caught one of those.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest
import yaml

PIPELINE = Path(__file__).resolve().parents[1]
REPO = PIPELINE.parent
CASES = PIPELINE / "cases"
BUILT = sorted(d.name for d in CASES.iterdir() if (d / "expected_results.json").exists())


def results(case: str) -> dict:
    data = json.loads((CASES / case / "expected_results.json").read_text(encoding="utf-8"))
    data = data.get("results", data)
    return {k: v["value"] for k, v in data.items()}


def calibration(case: str) -> list[dict]:
    out = []
    for y in sorted((PIPELINE / "calibration" / case).glob("*.yaml")):
        out += yaml.safe_load(y.read_text(encoding="utf-8"))["answers"]
    return out


# ---- 1. Claims written in words must still be true -------------------------------------------------
# Each entry: (case, claim as written in content.yaml, check on expected_results). If a re-run flips one of
# these, the prose is wrong and must be rewritten, not just re-numbered.
PROSE_CLAIMS = [
    ("p50_yield_curve", "10y-3m ranks months better than 2s10s", lambda r: r["auc_oos_10y3m"] > r["auc_oos_2s10s"]),
    ("p50_yield_curve", "both Brier skills are worse than the base rate",
     lambda r: r["bss_oos_10y3m"] < 0 and r["bss_oos_2s10s"] < 0),
    ("p50_yield_curve", "2s10s has the less bad Brier skill", lambda r: r["bss_oos_2s10s"] > r["bss_oos_10y3m"]),
    ("p50_yield_curve", "skill was positive before the split", lambda r: r["bss_oos_pre_split_10y3m"] > 0),
    ("p50_yield_curve", "today: no action", lambda r: r["latest_prob_10y3m"] < r["threshold"]),
    ("p50_yield_curve", "signal came before each test recession",
     lambda r: r["oos_recessions_caught"] == r["n_oos_recessions"]),
    ("p50_yield_curve", "threshold is fragile (moves with the embargo)",
     lambda r: r["threshold"] != r["threshold_embargo12"]),
    ("p50_yield_curve", "'{n_train_recessions_at_start} recession' is singular", lambda r: r["n_train_recessions_at_start"] == 1),
    ("p50_yield_curve", "HAC slope is clearly negative", lambda r: r["probit_p_hac_10y3m"] < 0.05),
    ("p50_yield_curve", "the lower the spread, the higher the share",
     lambda r: r["fwd_share_le0_2s10s"] > r["fwd_share_above1_2s10s"]),
    ("p34_home_adv", "no single league significant after Holm", lambda r: r["n_leagues_significant"] == 0),
    ("p34_home_adv", "pooled home-win drop is significant", lambda r: r["hw_change"] < 0 and r["hw_change_p"] < 0.05),
    ("p34_home_adv", "pooled goal-difference drop is significant", lambda r: r["gd_change_p"] < 0.05),
    ("p34_home_adv", "rebound when fans returned is not significant", lambda r: r["gd_reversal_p"] >= 0.05),
    ("p34_home_adv", "strict window interval includes zero", lambda r: r["gd_change_strict_p"] >= 0.05),
    ("p34_home_adv", "spring half normally higher than autumn", lambda r: r["gd_fans_spring"] > r["gd_fans_autumn"]),
    ("p3_delay_prop", "raw pass-through over one hundred percent", lambda r: r["pass_raw_b1"] > 1),
    ("p3_delay_prop", "excess pass-through about one for one", lambda r: 0.9 <= r["pass_b1"] <= 1.1),
    ("p3_delay_prop", "carrier-weighted and clean-day curves match pooled",
     lambda r: abs(r["pass_cw_b1"] - r["pass_b1"]) < 0.05 and abs(r["pass_clean_b1"] - r["pass_b1"]) < 0.05),
    ("p3_delay_prop", "out-of-time check fails", lambda r: r["buffer_rule_holds_octdec"] == "no"),
    ("p3_delay_prop", "Oct-Dec needs a longer turn", lambda r: r["buffer_turn_octdec"] > r["buffer_min_turn"]),
]


@pytest.mark.parametrize("case,claim,check", PROSE_CLAIMS, ids=[f"{c}:{t}" for c, t, _ in PROSE_CLAIMS])
def test_prose_claim_still_true(case, claim, check):
    assert check(results(case)), f"{case}: the content says '{claim}' but the results no longer support it"


# ---- 2. No result counts typed as words ------------------------------------------------------------
NUMBER_WORDS = r"(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"
COUNTED_NOUNS = r"(?:test recessions|recessions|training recessions?|leagues? (?:are|were|is|was) significant|matches|flights|months were)"


@pytest.mark.parametrize("case", BUILT)
def test_no_result_counts_spelled_out(case):
    text = (CASES / case / "content.yaml").read_text(encoding="utf-8")
    text = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    hits = re.findall(rf"\b{NUMBER_WORDS}\s+{COUNTED_NOUNS}\b", text, flags=re.IGNORECASE)
    assert not hits, f"{case}: counts typed as words, use {{expected.key}}: {hits}"


# ---- 3. Calibration label policies -----------------------------------------------------------------
CAUGHT_ALL = re.compile(r"caught all|each of the \{expected\.n_oos_recessions\}|all \{expected\.n_oos_recessions\}|"
                        r"before all \{expected\.n_oos_recessions\}", re.IGNORECASE)


def test_p50_caught_all_claims_carry_pandemic_caveat():
    bad = [a["id"] for a in calibration("p50_yield_curve")
           if a["label"] == "acceptable" and CAUGHT_ALL.search(a["text"]) and "pandemic" not in a["text"].lower()]
    assert not bad, f"acceptable answers claim every recession was caught without the pandemic caveat: {bad}"


@pytest.mark.parametrize("case", BUILT)
def test_calibration_kinds_agree_with_labels(case):
    for a in calibration(case):
        if a["kind"] in ("wrong", "red_flag"):
            assert a["label"] == "not_acceptable", (case, a["id"])
        if a["kind"] == "strong" and a["label"] != "acceptable":
            assert a.get("owner_review"), (case, a["id"], "strong answer relabelled without an owner-review flag")


# ---- 4. Docs that quote counts must match the repo -------------------------------------------------
def test_docs_flagged_counts_match_calibration():
    flagged = {c: sum(1 for a in calibration(c) if a.get("owner_review")) for c in BUILT}
    wrong = []
    for md in [*(REPO / "docs").rglob("*.md"), REPO / "README.md"]:
        if not md.exists() or "source" in md.parts:
            continue
        text = md.read_text(encoding="utf-8")
        for m in re.finditer(r"(\d+)\s+(?:calibration answers\s+)?flagged", text):
            line_start = text.rfind("\n", 0, m.start()) + 1
            context = md.name + text[line_start:m.end()]
            for c in BUILT:
                tag = c.split("_")[0]
                if c in context or re.search(rf"\b{tag}\b", context, flags=re.IGNORECASE):
                    if int(m.group(1)) != flagged[c]:
                        wrong.append(f"{md.relative_to(REPO)}: says {m.group(1)} flagged for {c}, actual {flagged[c]}")
    assert not wrong, wrong
