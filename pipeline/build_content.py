"""Validate every case and build the app's content bundle.

    uv run python build_content.py            # validate + write app/assets/content/
    uv run python build_content.py --check    # validate only

FAILS (exit 1) if, for any case (spec §4 + project rules):
  * content.yaml does not match the schema (incl. rubric weights != 100, 4-7 points, 3-6 red flags)
  * a {expected.key} placeholder / numeric anchor / answer_key is missing from expected_results.json
  * a source key is missing from sources.json or is not VERIFIED
  * a dataset / transform referenced is missing from provenance.json, or a raw file's SHA-256 changed
  * a chart file (json + png) is missing
  * a code snippet / captured output / blank token is missing
  * a context snippet would reveal the answer of a code_fill / code_fix step that comes at or after it
  * a graded step has no calibration set (>= 30 labelled answers, both labels present)
  * authored text contains a hand-typed number (digits outside placeholders and allowed_literals)
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import yaml
from pydantic import ValidationError

from common.content_schema import GRADED_TYPES, PLACEHOLDER_RE, Case
from common.glossary import validate_course, write_course
from common.io import extract_snippets, load_captured
from common.provenance import Provenance
from common.results import ResultStore

PIPELINE = Path(__file__).resolve().parent
REPO = PIPELINE.parent
CASES_DIR = PIPELINE / "cases"
CAL_DIR = PIPELINE / "calibration"
SOURCES_FILE = REPO / "sources.json"
OUT_DIR = REPO / "app" / "assets" / "content"
LEARN_DIR = PIPELINE / "learn" / "finance"
CATALOG_FILE = PIPELINE / "catalog.yaml"
CATALOG_SIZE = 50
CATALOG_TIERS = {"A", "A*", "B", "C"}
# v2 (2026-11-15): finance course tables (course, tiers, lessons, terms) + formulas/*.png; context_snippets.
# v3 (2026-11-16): catalog (all 50 curriculum problems; `case_id` set where the case is built).
BUNDLE_SCHEMA_VERSION = 3
MIN_CALIBRATION = 30

NEGATABLE_KEYWORDS = {"cause", "causes", "caused", "causation", "prove", "proves", "proof", "certain", "guarantee"}
CAPTURED_RE = re.compile(r"\{captured\.([a-z][a-z0-9_]*)\}")
SOURCE_FIELDS = {"key", "title", "authors", "year", "url", "verified_on", "quote", "status"}
# Fields that hold identifiers or code, not prose — exempt from the hand-typed-number check.
NON_PROSE_KEYS = {
    "id", "file", "name", "chart", "dataset", "transform", "output_name", "answer_key", "key",
    "sources", "datasets", "allowed_literals", "scaffold", "type", "phase", "domain", "tier",
    "token", "accept", "buggy_code", "redo_step", "evidence", "tolerance_kind", "signature_chart",
}


# --------------------------------------------------------------------------- sources
def load_sources(path: Path = SOURCES_FILE) -> tuple[dict[str, dict], list[str]]:
    errors: list[str] = []
    if not path.exists():
        return {}, [f"{path} missing"]
    data = json.loads(path.read_text(encoding="utf-8"))
    out: dict[str, dict] = {}
    for i, s in enumerate(data):
        missing = SOURCE_FIELDS - set(s)
        if missing:
            errors.append(f"sources.json[{i}]: missing fields {sorted(missing)}")
            continue
        if s["status"] not in ("VERIFIED", "UNVERIFIED"):
            errors.append(f"sources.json {s['key']}: status must be VERIFIED or UNVERIFIED")
        if s["status"] == "VERIFIED":
            if not s["url"] or not s["verified_on"] or not s["quote"]:
                errors.append(f"sources.json {s['key']}: VERIFIED needs url, verified_on and quote")
            elif len(s["quote"].split()) >= 15:
                errors.append(f"sources.json {s['key']}: quote must be under 15 words")
        if s["key"] in out:
            errors.append(f"sources.json: duplicate key {s['key']}")
        out[s["key"]] = s
    return out, errors


# --------------------------------------------------------------------------- helpers
def walk_strings(obj: Any, path: str = "") -> list[tuple[str, str]]:
    """(path, string) for every string in a nested dict/list, e.g. ('steps[2].options[1].text', '...')."""
    out: list[tuple[str, str]] = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            out += walk_strings(v, f"{path}.{k}" if path else str(k))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            out += walk_strings(v, f"{path}[{i}]")
    elif isinstance(obj, str):
        out.append((path, obj))
    return out


def _key_of(path: str) -> str:
    """Nearest dict key on the path ('steps[2].options[1].text' -> 'text')."""
    last = path.rsplit(".", 1)[-1]
    return last.split("[")[0]


def hand_typed_numbers(text: str, allowed: list[str]) -> list[str]:
    t = PLACEHOLDER_RE.sub(" ", text)
    t = CAPTURED_RE.sub(" ", t)
    for lit in sorted(allowed, key=len, reverse=True):
        t = re.sub(re.escape(lit), " ", t, flags=re.IGNORECASE)
    return re.findall(r"\S*\d\S*", t)


def load_calibration(case_id: str, step_id: str, cal_root: Path) -> tuple[list[dict], list[str]]:
    p = cal_root / case_id / f"{step_id}.yaml"
    if not p.exists():
        return [], [f"no calibration set {p.relative_to(cal_root.parent) if cal_root.parent in p.parents else p}"]
    data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    answers = data.get("answers", [])
    errs = []
    if len(answers) < MIN_CALIBRATION:
        errs.append(f"calibration {step_id}: {len(answers)} answers < {MIN_CALIBRATION}")
    labels = {a.get("label") for a in answers}
    if not labels <= {"acceptable", "not_acceptable"}:
        errs.append(f"calibration {step_id}: labels must be acceptable/not_acceptable")
    if answers and labels != {"acceptable", "not_acceptable"}:
        errs.append(f"calibration {step_id}: needs both acceptable and not_acceptable answers")
    ids = [a.get("id") for a in answers]
    if len(ids) != len(set(ids)):
        errs.append(f"calibration {step_id}: duplicate answer ids")
    return answers, errs


# --------------------------------------------------------------------------- case validation
def validate_case(case_dir: Path, sources: dict[str, dict], cal_root: Path = CAL_DIR) -> tuple[Case | None, list[str]]:
    errs: list[str] = []
    cy = case_dir / "content.yaml"
    try:
        case = Case.model_validate(yaml.safe_load(cy.read_text(encoding="utf-8")))
    except (ValidationError, yaml.YAMLError) as e:
        return None, [f"content.yaml invalid:\n{e}"]

    results = ResultStore.load(case_dir)
    prov = Provenance(case_dir)
    captured = load_captured(case_dir)
    dump = case.model_dump()

    # placeholders + hand-typed numbers
    for path, s in walk_strings(dump):
        for key in PLACEHOLDER_RE.findall(s):
            if key not in results:
                errs.append(f"{path}: placeholder {{expected.{key}}} not in expected_results.json")
        for name in CAPTURED_RE.findall(s):
            if name not in captured:
                errs.append(f"{path}: {{captured.{name}}} not in captured_outputs.json")
        if _key_of(path) in NON_PROSE_KEYS:
            continue
        bad = hand_typed_numbers(s, case.allowed_literals)
        if bad:
            errs.append(f"{path}: hand-typed number(s) {bad} - use {{expected.key}} or allowed_literals")

    # sources
    for k in case.sources:
        if k not in sources:
            errs.append(f"source {k!r} not in sources.json")
        elif sources[k]["status"] != "VERIFIED":
            errs.append(f"source {k!r} is not VERIFIED")

    # provenance
    for d in case.datasets:
        if d not in prov.data["datasets"]:
            errs.append(f"dataset {d!r} not in provenance.json")
    errs += [f"provenance: {p}" for p in prov.verify_hashes()]
    transform_ids = {t["id"] for t in prov.data["transforms"]}

    snippet_cache: dict[str, dict[str, str]] = {}

    def snippet_code(sn) -> str | None:
        f = case_dir / sn.file
        if not f.exists():
            errs.append(f"snippet file {sn.file} missing")
            return None
        if sn.file not in snippet_cache:
            snippet_cache[sn.file] = extract_snippets(f)
        code = snippet_cache[sn.file].get(sn.name)
        if code is None:
            errs.append(f"snippet {sn.file}:{sn.name} not found")
        return code

    if case.signature_chart:
        for ext in ("json", "png"):
            if not (case_dir / "charts" / f"{case.signature_chart}.{ext}").exists():
                errs.append(f"signature_chart charts/{case.signature_chart}.{ext} missing")

    # Context code must never show the answer of a fill-the-blank / fix-the-bug step that is still ahead.
    answer_code: dict[tuple[str, str], int] = {}
    for i, st in enumerate(case.steps):
        if st.type in ("code_fill", "code_fix") and st.snippet:
            key = (st.snippet.file, st.snippet.name)
            answer_code[key] = max(answer_code.get(key, -1), i)

    for idx, st in enumerate(case.steps):
        where = f"step {st.id}"
        if st.context_snippets and st.type in ("code_fill", "code_fix"):
            errs.append(f"{where}: {st.type} steps cannot show context code (it would reveal the answer)")
        seen_ctx: set[tuple[str, str]] = set()
        for sn in st.context_snippets:
            key = (sn.file, sn.name)
            if key in seen_ctx:
                errs.append(f"{where}: context snippet {sn.file}:{sn.name} listed twice")
            seen_ctx.add(key)
            snippet_code(sn)
            if answer_code.get(key, -1) >= idx:
                errs.append(f"{where}: context snippet {sn.file}:{sn.name} is the answer of a later "
                            f"code_fill/code_fix step")
        if st.chart:
            for ext in ("json", "png"):
                if not (case_dir / "charts" / f"{st.chart}.{ext}").exists():
                    errs.append(f"{where}: chart file charts/{st.chart}.{ext} missing")
        if st.dataset and st.dataset not in prov.data["datasets"]:
            errs.append(f"{where}: dataset {st.dataset!r} not in provenance")
        if st.transform and st.transform not in transform_ids:
            errs.append(f"{where}: transform {st.transform!r} not in provenance transforms")
        if st.answer_key and st.answer_key not in results:
            errs.append(f"{where}: answer_key {st.answer_key!r} not in expected_results.json")
        if st.rubric:
            # Red-flag keywords fire on bare words, so words good answers use NEGATED ("this can't prove /
            # does not show cause") would penalise correct answers. Use paraphrases for these instead.
            for rf in st.rubric.red_flags:
                bad = {w for g in rf.keywords for w in g} & NEGATABLE_KEYWORDS
                if bad:
                    errs.append(f"{where}: red flag {rf.id} uses negatable keyword(s) {sorted(bad)}; use paraphrases")
            for p in st.rubric.points:
                if p.numeric and p.numeric.key not in results:
                    errs.append(f"{where}: numeric anchor {p.numeric.key!r} not in expected_results.json")
        if st.snippet:
            code = snippet_code(st.snippet)
            if code is not None:
                if st.output_name and st.output_name not in captured:
                    errs.append(f"{where}: captured output {st.output_name!r} missing")
                for b in st.blanks or []:
                    if b.token not in code:
                        errs.append(f"{where}: blank token {b.token!r} not in real snippet")
                if st.buggy_code is not None and st.buggy_code.strip() == code.strip():
                    errs.append(f"{where}: buggy_code is identical to the real snippet")
        if st.type in GRADED_TYPES:
            answers, cerrs = load_calibration(case.id, st.id, cal_root)
            errs += [f"{where}: {e}" for e in cerrs]
            # calibration answers may quote real numbers only via placeholders, which must resolve
            for a in answers:
                for key in PLACEHOLDER_RE.findall(str(a.get("text", ""))):
                    if key not in results:
                        errs.append(f"{where}: calibration {a.get('id')}: placeholder {{expected.{key}}} not in results")
    return case, errs


# --------------------------------------------------------------------------- bundle
DDL = """
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE cases(id TEXT PRIMARY KEY, number INTEGER, domain TEXT, title TEXT, tier TEXT,
                   ord INTEGER, json TEXT NOT NULL);
CREATE TABLE steps(case_id TEXT, idx INTEGER, id TEXT, phase TEXT, type TEXT, json TEXT NOT NULL,
                   PRIMARY KEY(case_id, id));
CREATE TABLE results(case_id TEXT, key TEXT, value_json TEXT, unit TEXT, description TEXT,
                     display TEXT, PRIMARY KEY(case_id, key));
CREATE TABLE sources(key TEXT PRIMARY KEY, title TEXT, authors TEXT, year TEXT, url TEXT,
                     verified_on TEXT, quote TEXT, status TEXT);
CREATE TABLE datasets(case_id TEXT, key TEXT, json TEXT, PRIMARY KEY(case_id, key));
CREATE TABLE transforms(case_id TEXT, id TEXT, json TEXT, PRIMARY KEY(case_id, id));
CREATE TABLE snippets(case_id TEXT, file TEXT, name TEXT, code TEXT, PRIMARY KEY(case_id, file, name));
CREATE TABLE captured(case_id TEXT, name TEXT, output TEXT, PRIMARY KEY(case_id, name));
"""


def write_bundle(cases: list[tuple[Path, Case]], sources: dict[str, dict], out_dir: Path, course=None,
                 catalog: list[dict] | None = None) -> Path:
    """course = (Course, ordered terms) from validate_course, or None (framework fixtures); catalog likewise."""
    if out_dir.exists():
        shutil.rmtree(out_dir)
    (out_dir / "charts").mkdir(parents=True)
    (out_dir / "formulas").mkdir(parents=True)
    db_path = out_dir / "content.sqlite"
    con = sqlite3.connect(db_path)
    con.executescript(DDL)
    con.executemany("INSERT INTO meta VALUES(?,?)", [
        ("bundle_schema_version", str(BUNDLE_SCHEMA_VERSION)),
        ("built_utc", datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")),
    ])
    for s in sources.values():
        con.execute("INSERT INTO sources VALUES(?,?,?,?,?,?,?,?)", (
            s["key"], s["title"], json.dumps(s["authors"]) if isinstance(s["authors"], list) else s["authors"],
            str(s["year"]), s["url"], s["verified_on"], s["quote"], s["status"]))
    for ord_, (cdir, case) in enumerate(cases):
        cj = case.model_dump(exclude={"steps"})
        con.execute("INSERT INTO cases VALUES(?,?,?,?,?,?,?)",
                    (case.id, case.number, case.domain, case.title, case.tier, ord_, json.dumps(cj)))
        if case.signature_chart:
            for ext in ("json", "png"):
                shutil.copy2(cdir / "charts" / f"{case.signature_chart}.{ext}",
                             out_dir / "charts" / f"{case.signature_chart}.{ext}")
        snippets: dict[tuple[str, str], str] = {}
        for i, st in enumerate(case.steps):
            con.execute("INSERT INTO steps VALUES(?,?,?,?,?,?)",
                        (case.id, i, st.id, st.phase, st.type, json.dumps(st.model_dump(exclude_none=True))))
            for sn in ([st.snippet] if st.snippet else []) + list(st.context_snippets):
                snippets[(sn.file, sn.name)] = extract_snippets(cdir / sn.file)[sn.name]
            if st.chart:
                for ext in ("json", "png"):
                    shutil.copy2(cdir / "charts" / f"{st.chart}.{ext}", out_dir / "charts" / f"{st.chart}.{ext}")
        for (f, n), code in snippets.items():
            con.execute("INSERT INTO snippets VALUES(?,?,?,?)", (case.id, f, n, code))
        for k, r in ResultStore.load(cdir).items():
            con.execute("INSERT INTO results VALUES(?,?,?,?,?,?)",
                        (case.id, k, json.dumps(r["value"]), r["unit"], r["description"], r["display"]))
        prov = Provenance(cdir)
        for k, d in prov.data["datasets"].items():
            con.execute("INSERT INTO datasets VALUES(?,?,?)", (case.id, k, json.dumps(d)))
        for t in prov.data["transforms"]:
            con.execute("INSERT INTO transforms VALUES(?,?,?)", (case.id, t["id"], json.dumps(t)))
        for n, o in load_captured(cdir).items():
            con.execute("INSERT INTO captured VALUES(?,?,?)", (case.id, n, o))
    if course is not None:
        write_course(con, course[0], course[1], out_dir)
    if catalog is not None:
        write_catalog(con, catalog)
    con.commit()
    con.close()
    return db_path


def load_catalog(path: Path, cases: list[Case]) -> tuple[list[dict], list[str]]:
    """The 50 curriculum problems (pipeline/catalog.yaml). Every built case must be in it, in the same sector."""
    errs: list[str] = []
    probs = (yaml.safe_load(path.read_text(encoding="utf-8")) or {}).get("problems", [])
    nums = [p.get("number") for p in probs]
    if sorted(nums) != list(range(1, CATALOG_SIZE + 1)):
        errs.append(f"catalog: problems must be numbered 1..{CATALOG_SIZE} exactly once")
    for p in probs:
        where = f"catalog P{p.get('number')}"
        for k in ("domain", "title", "summary", "tier"):
            if not p.get(k):
                errs.append(f"{where}: missing {k}")
        if p.get("tier") not in CATALOG_TIERS:
            errs.append(f"{where}: tier {p.get('tier')!r} not in {sorted(CATALOG_TIERS)}")
        if re.search(r"\(\D*\d{4}\)", p.get("summary", "")):
            errs.append(f"{where}: summary carries a citation; only VERIFIED sources may be shown")
    by_num = {p.get("number"): p for p in probs}
    for c in cases:
        p = by_num.get(c.number)
        if p is None:
            errs.append(f"catalog: built case {c.id} (P{c.number}) is not in the catalog")
        elif p["domain"] != c.domain:
            errs.append(f"catalog: P{c.number} is {p['domain']} in the catalog but {c.domain} in {c.id}")
        else:
            p["case_id"] = c.id
    ranks = [p["build_rank"] for p in probs if p.get("build_rank") is not None]
    if len(ranks) != len(set(ranks)):
        errs.append("catalog: build_rank values must be unique")
    return probs, errs


def write_catalog(con, probs: list[dict]) -> None:
    con.execute("CREATE TABLE catalog(number INTEGER PRIMARY KEY, domain TEXT, title TEXT, summary TEXT, tier TEXT, "
                "build_rank INTEGER, case_id TEXT)")
    for p in probs:
        con.execute("INSERT INTO catalog VALUES(?,?,?,?,?,?,?)", (p["number"], p["domain"], p["title"], p["summary"],
                                                                  p["tier"], p.get("build_rank"), p.get("case_id")))


def discover_cases(cases_dir: Path) -> list[Path]:
    return sorted(p.parent for p in cases_dir.glob("*/content.yaml"))


def build(cases_dir: Path = CASES_DIR, cal_root: Path = CAL_DIR, sources_file: Path = SOURCES_FILE,
          out_dir: Path = OUT_DIR, check_only: bool = False, order: list[str] | None = None,
          learn_dir: Path | None = None, partial_course: bool = False, catalog_file: Path | None = None) -> int:
    """learn_dir: the finance course to validate and bundle (None = cases only, as in framework tests)."""
    sources, errors = load_sources(sources_file)
    for e in errors:
        print(f"FAIL sources: {e}")
    ok_cases: list[tuple[Path, Case]] = []
    for cdir in discover_cases(cases_dir):
        case, errs = validate_case(cdir, sources, cal_root)
        if errs:
            errors += errs
            print(f"FAIL {cdir.name}: {len(errs)} problem(s)")
            for e in errs:
                print(f"   - {e}")
        else:
            print(f"OK   {cdir.name}: {len(case.steps)} steps")
            ok_cases.append((cdir, case))
    course = None
    if learn_dir is not None:
        case_steps = {case.id: {s.id for s in case.steps} for _, case in ok_cases}
        c, ordered, cerrs = validate_course(learn_dir, sources, case_steps, complete=not partial_course)
        if cerrs:
            errors += cerrs
            print(f"FAIL course {learn_dir.name}: {len(cerrs)} problem(s)")
            for e in cerrs:
                print(f"   - {e}")
        else:
            print(f"OK   course {learn_dir.name}: {len(ordered)} words")
            course = (c, ordered)
    catalog = None
    if catalog_file is not None:
        catalog, kerrs = load_catalog(catalog_file, [c for _, c in ok_cases])
        if kerrs:
            errors += kerrs
            for e in kerrs:
                print(f"FAIL {e}")
        else:
            print(f"OK   catalog: {len(catalog)} problems, {sum(1 for p in catalog if p.get('case_id'))} built")
    if errors:
        print(f"\nBUILD FAILED: {len(errors)} problem(s)")
        return 1
    if order:
        rank = {cid: i for i, cid in enumerate(order)}
        ok_cases.sort(key=lambda t: rank.get(t[1].id, 999))
    if not check_only:
        db = write_bundle(ok_cases, sources, out_dir, course, catalog)
        print(f"\nwrote {db} ({len(ok_cases)} case(s))")
    return 0


# Spec §8 build order (portfolio-first), used to order cases in the app.
BUILD_ORDER = ["p50_yield_curve", "p34_home_adv", "p3_delay_propagation", "p13_tyre_deg", "p1_jet_fuel_hedge",
               "p33_manager_bounce", "p18_safety_car", "p41_pairs_trading", "p14_undercut", "p40_credit_scoring",
               "p25_ucl_event_study", "p38_order_book", "p42_mortgage_prepay"]

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate only")
    ap.add_argument("--partial-course", action="store_true", help="allow an unfinished course (work in progress)")
    a = ap.parse_args()
    sys.exit(build(check_only=a.check, order=BUILD_ORDER, learn_dir=LEARN_DIR, partial_course=a.partial_course,
                   catalog_file=CATALOG_FILE))
