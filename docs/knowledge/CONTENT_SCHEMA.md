# Content schema

Source of truth in code: `pipeline/common/content_schema.py` (pydantic) and `pipeline/common/charts.py`.
If this doc and the code disagree, the code wins — fix the doc.

## Per-case directory `pipeline/cases/<case_id>/`
| File | Written by | Contents |
|---|---|---|
| `download.py` `clean.py` `analyse.py` | human/Claude | real pipeline code; `# >>> snippet: name` … `# <<< snippet` marks code shown in the app |
| `raw/` | `Provenance.fetch` | raw files, byte-for-byte |
| `provenance.json` | `Provenance.save` | `datasets{key: url, retrieved_utc, sha256, bytes, licence_note, schema{rows, columns, dtypes, missing, head}, units, frequency…}`, `transforms[{id, dataset, rows_before, rows_after, rows_dropped, reason, details}]` |
| `expected_results.json` | `ResultStore.save` | `{key: {value, unit, description, display, produced_by}}` |
| `captured_outputs.json` | `capture_output` | `{name: printed text}` of real code runs |
| `charts/<id>.json` + `.png` | `export_chart` | chart JSON (schema in charts.py docstring) + phone PNG |
| `content.yaml` | human/Claude | the case (below) |
| `test_case.py` | human/Claude | pytest asserting every result key |
Calibration: `pipeline/calibration/<case_id>/<step_id>.yaml` → `answers: [{id, text, label: acceptable|not_acceptable, kind: strong|partial|wrong|red_flag, owner_review: bool, note}]`, ≥ 30 per graded step.
Correct numbers in answer `text` use `{expected.key}` (the build checks the key exists); deliberately wrong numbers are typed.

## content.yaml
Top level: `id, number, domain (aviation|f1|football|finance), title, tier (A|A*), decision_maker, signature_chart?,
decision, money_at_stake, concepts[], sources[] (keys in sources.json, VERIFIED), datasets[] (keys in
provenance.json), allowed_literals[] (e.g. "10-year", "2s10s" — digit-containing words that are
names, not results), steps[], debrief{concepts_learned[], common_mistakes[], interview_summary}`.

### Placeholders
- `{expected.<key>}` → replaced in the app by `results.display` for that key.
- `{captured.<name>}` → replaced by the real captured output.
- Any other digit in prose fails the build (unless it is inside an `allowed_literals` entry).

### Phases (in order)
`brief → frame → predict → data → explore → model → decide → debrief`. `predict` is the owner's
Challenge-mode phase: predict the data *before* seeing it.

### Step types
| Type | Required fields | Checked how |
|---|---|---|
| mcq / multi_select / kpi_builder | options[{id,text,correct,explanation}] | exact |
| order_steps | items (correct order) | exact |
| code_read | snippet{file,name} | info |
| *(any type)* | context_snippets[{file,name}] (optional) | shown as "The code behind this step"; never the answer of a later code_fill/code_fix |
| code_predict | snippet, output_name, options | exact (vs captured output) |
| code_fill | snippet, blanks[{token, accept[]}] | exact; token must exist in real code |
| code_fix | snippet, buggy_code, bug_explanation | exact |
| numeric | answer_key, tolerance, unit | within tolerance of result |
| concept_card | body | info |
| free_text, chart_explain, result_explain, memo | rubric, model_answer, analysis_pointer (+chart for chart_explain) | **examiner** |
| data_expectation *(challenge)* | + dataset (provenance key whose real schema is revealed after) | examiner |
| cleaning_justification *(challenge)* | + transform (provenance transform id) | examiner |
| plan_challenge *(challenge)* | + flawed_plan | examiner |
| decision_threshold *(challenge)* | rubric with a numeric anchor on the trigger value | examiner |

### Rubric (spec §5)
`points` 4–7: `{id, label, weight (sum = 100), paraphrases (3–6), keywords [[synonyms]…],
numeric {key, tolerance, tolerance_kind abs|rel, accept_percent}?, hint, why, evidence?}`
`red_flags` 3–6: `{id, critical, penalty, paraphrases, keywords?, feedback}`

### Scaffolds (explanation templates shown as optional guide)
`chart_6q` What is plotted → Pattern → Strength (a number) → Anomalies → What it can't show → So what ·
`cer` Claim → Evidence → Reasoning + one limitation ·
`memo` Recommendation (number/range) → Evidence (2–3 numbers) → Risk left → Limitations → Next step ·
`predict_data` Grain → Units → Frequency/coverage → Missing-value code → Traps ·
`justify_clean` What was done → Why → Alternative rejected → What breaks if skipped ·
`challenge_plan` What the plan assumes → Why that fails here → Fix → How you'd check ·
`threshold` Trigger metric → Value → Action → Expected error rate at that value.

## content.sqlite (bundle the app reads)
Tables: `meta(key,value)`, `cases(id,number,domain,title,tier,ord,json)`,
`steps(case_id,idx,id,phase,type,json)` (placeholders unresolved), `results(case_id,key,value_json,unit,description,display)`,
`sources`, `datasets(case_id,key,json)`, `transforms(case_id,id,json)`, `snippets(case_id,file,name,code)`,
`captured(case_id,name,output)`. Charts copied to `app/assets/content/charts/`.
Bundle schema v2 (2026-11-15) adds `course(id,title,json)`, `tiers(id,course,ord,title,json)`,
`lessons(id,tier,ord,title,json)`, `terms(id,tier,lesson,rank,term,json)` and `app/assets/content/formulas/<term>.png`.

## Finance course (`pipeline/learn/finance/`, schema in `pipeline/common/glossary.py`)
`course.yaml`: `id, title, allowed_literals[], tiers[{id, title, blurb, read_next[source keys], lessons[{id, title,
blurb, kind ("finance" by default, or "measures"), sources[]}]}]`. `terms/<lesson_id>.yaml`: ten words, each `{id, term, aliases[], short (≤ 30 words, must not
contain its own name or aliases), plain, formula{tex (matplotlib mathtext), plain, symbols[{symbol, means}]}?,
example{values{}, compute{} (ordered expressions), formats{} ("£{:,.0f}", "{:.1%}"), text with {name}
placeholders}?, fools_you, related[], in_cases[{case, step}], sources[]}`. Rank = file order. Prose fields contain no
digits (course `allowed_literals` excepted); example numbers are computed and reach the app wrapped as `[[…]]`.
Unknown fields fail validation, so YAML slips cannot silently drop text.

Measures cards (lessons with `kind: measures`, 2026-11-16) must also have `used_for` (what the measure is for) and
`in_finance` (how finance uses or names it; may contain `{name}` placeholders filled from the reading's values). They
usually carry `reading{values{}, compute{}, formats{}, question, means, misreadings[3], scale{lo, hi, format, better:
higher|lower|neither}?, point?, interval[lo, hi]?, marks[{at, label}], bands[{upto, label}], bands_source?}`. `lo`,
`hi`, `at` and `upto` are numbers or names of reading values. The build checks that every point, mark, interval end and
band lies on the scale, bands run contiguously from `lo` to `hi`, bands come with a VERIFIED `bands_source`,
misreadings differ from each other and from the right reading, and no text carries a digit outside its placeholders.
The bundle gets the texts filled in (`means` and `in_finance` with `[[…]]` markers) and every position as a number
with its formatted label, so the app only places them.
