"""Build the answer key from MetricFlow: independent of the agent, Cortex and the Snowflake semantic view.

Run from repo root:  python eval/build_ground_truth.py
Reads eval/questions.yaml, writes eval/ground_truth.json
"""

import csv
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

# Establish paths relative to the script location (assumes script is in /eval)
ROOT = Path(__file__).resolve().parents[1]
QUESTIONS = ROOT / "eval" / "questions.yaml"
OUT = ROOT / "eval" / "ground_truth.json"

# Ensure the MetricFlow CLI is available in the current environment
MF = shutil.which("mf") or sys.exit("mf not found. Run: conda activate semantic-layer")

# Cache to prevent running identical mf queries multiple times across different questions
_cache: dict = {}


def mf_query(metric: str, group_by: str | None = None) -> list[dict]:
    """Run one MetricFlow query, return rows with lower-case column names. Cached."""
    key = (metric, group_by)

    # Check cache first to save network/warehouse execution time
    if key not in _cache:
        # Use a temporary directory for the CSV export so we don't clutter the repo
        with tempfile.TemporaryDirectory() as tmp:
            csv_path = Path(tmp) / "result.csv"

            # Construct the base MetricFlow CLI command
            cmd = [MF, "query", "--metrics", metric, "--csv", str(csv_path)]
            if group_by:
                cmd += ["--group-by", group_by]

            print(f"  mf query --metrics {metric}" + (f" --group-by {group_by}" if group_by else ""))

            # Execute the command against the live data warehouse
            # Force UTF-8: mf prints an emoji spinner that crashes on Windows' cp1252 default
            env = {**os.environ, "PYTHONUTF8": "1", "PYTHONIOENCODING": "utf-8"}
            run = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env)
            if run.returncode != 0:
                sys.exit(f"mf query failed:\n{run.stdout}\n{run.stderr}")

            # Read the CSV output and normalize column headers to lowercase for predictable access
            with csv_path.open(newline="", encoding="utf-8") as f:
                _cache[key] = [{k.lower(): v for k, v in row.items()} for row in csv.DictReader(f)]

    return _cache[key]


def to_number(value: str):
    """Safely cast empty strings or None to None, otherwise cast to float."""
    return None if value in ("", None) else float(value)


def resolve(spec: dict, values: dict):
    """Turn one truth spec into a number (or a {label: number} dict for all: true)."""

    # 1. Derived Metrics: Calculate a value based on previously resolved metrics in the same question
    # Example YAML: expr: "revenue / users"
    if "expr" in spec:
        # Evaluate the math expression using the `values` dict as local variables.
        # __builtins__: {} is used as a basic safety measure to prevent arbitrary code execution during eval.
        return round(eval(spec["expr"], {"__builtins__": {}}, values), 4)

    # Fetch the raw data from MetricFlow
    rows = mf_query(spec["metric"], spec.get("group_by"))
    col, dim = spec["metric"].lower(), (spec.get("group_by") or "").lower()

    # 2. Dictionary output: Return all rows grouped by the dimension (e.g., revenue by category)
    if spec.get("all"):
        return {str(r[dim]): to_number(r[col]) for r in rows}

    # 3. Single Pick: Filter the results for a specific dimension value
    # Example YAML: group_by: "country", pick: "US"
    if "pick" in spec:
        match = [r for r in rows if str(r[dim]).lower().startswith(str(spec["pick"]).lower())]
        if len(match) != 1:
            sys.exit(f"pick {spec['pick']!r} matched {len(match)} rows in {dim}: {[r[dim] for r in rows]}")
        return to_number(match[0][col])

    # 4. Scalar output: Expect exactly one row (e.g., total overall revenue)
    if len(rows) != 1:
        sys.exit(f"{spec['metric']} returned {len(rows)} rows; expected 1")
    return to_number(rows[0][col])


def main() -> None:
    # Load the test suite definitions
    questions = yaml.safe_load(QUESTIONS.read_text(encoding="utf-8"))
    truth = {}

    for q in questions:
        values: dict = {}

        # Sequentially resolve each truth spec in the question.
        # Order matters here because a spec might use 'expr' to reference an earlier spec's result.
        for name, spec in (q.get("truth") or {}).items():
            values[name] = resolve(spec, values)

        truth[q["id"]] = values
        print(f"{q['id']}: {values}\n")

    # Dump the compiled evaluation dictionary to JSON for the testing script to consume
    OUT.write_text(json.dumps(truth, indent=2), encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)} for {len(truth)} questions")


if __name__ == "__main__":
    main()
