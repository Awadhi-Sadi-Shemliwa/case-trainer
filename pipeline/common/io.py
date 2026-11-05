"""Real code + real output for the code-reading steps (spec §3: 'he reads real pipeline code,
predicts outputs, fills blanks and fixes bugs, and the app compares his answer to the real output
the pipeline captured').

Snippets: mark a region in any pipeline source file

    # >>> snippet: load_raw
    df = pd.read_csv(path, na_values=".")
    print(df.dtypes)
    # <<< snippet

extract_snippets(file) returns {"load_raw": "<code without markers>"}.

Captured output: wrap the real code when it runs

    with capture_output(CASE_DIR, "load_raw"):
        print(df.dtypes)

The printed text is still shown on the console AND saved to captured_outputs.json.
"""

from __future__ import annotations

import contextlib
import io
import json
import re
import sys
import textwrap
from pathlib import Path

CAPTURE_FILE = "captured_outputs.json"
_START = re.compile(r"^\s*# >>> snippet: ([a-z][a-z0-9_]*)\s*$")
_END = re.compile(r"^\s*# <<< snippet\s*$")


class SnippetError(ValueError):
    pass


def extract_snippets(path: Path | str) -> dict[str, str]:
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    out: dict[str, str] = {}
    name: str | None = None
    buf: list[str] = []
    for i, line in enumerate(lines, 1):
        m = _START.match(line)
        if m:
            if name:
                raise SnippetError(f"{path}:{i}: nested snippet {m.group(1)} inside {name}")
            name, buf = m.group(1), []
            continue
        if _END.match(line):
            if not name:
                raise SnippetError(f"{path}:{i}: snippet end without start")
            if name in out:
                raise SnippetError(f"{path}: duplicate snippet {name}")
            out[name] = textwrap.dedent("\n".join(buf)).strip("\n")
            name = None
            continue
        if name:
            buf.append(line)
    if name:
        raise SnippetError(f"{path}: snippet {name} never closed")
    return out


class _Tee(io.TextIOBase):
    def __init__(self, *streams):
        self.streams = streams

    def write(self, s):
        for st in self.streams:
            st.write(s)
        return len(s)

    def flush(self):
        for st in self.streams:
            st.flush()


@contextlib.contextmanager
def capture_output(case_dir: Path | str, name: str):
    path = Path(case_dir) / CAPTURE_FILE
    buf = io.StringIO()
    old = sys.stdout
    sys.stdout = _Tee(old, buf)
    try:
        yield buf
    finally:
        sys.stdout = old
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
        data[name] = buf.getvalue().rstrip("\n")
        path.write_text(json.dumps(dict(sorted(data.items())), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_captured(case_dir: Path | str) -> dict[str, str]:
    p = Path(case_dir) / CAPTURE_FILE
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
