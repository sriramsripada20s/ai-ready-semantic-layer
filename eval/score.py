"""Score an eval run -> 5 metrics + per-question report.
Run:  python eval/score.py eval/results/S1_agent_v1.jsonl
"""
import json, os, random, re, sys
from collections import defaultdict
from pathlib import Path

import yaml
from dotenv import load_dotenv
from langchain_anthropic import ChatAnthropic
from pydantic import BaseModel

load_dotenv()
ROOT = Path(__file__).resolve().parents[1]

# The list of 20 certified metrics the agent is expected to use
METRICS = ["campaign_attributed_revenue", "campaign_sessions", "campaign_spend", "customer_lifetime_value",
           "discount_amount", "gross_merchandise_value", "gross_profit", "median_order_value", "net_revenue",
           "new_customer_orders", "new_signups", "ordering_customers", "orders", "product_cost",
           "product_net_revenue", "recognized_orders", "returned_orders", "sessions", "units_sold", "visitors"]

# Regex to safely extract financial, percentage, and scaled numbers (e.g., "$136.97M", "16.1%")
# (?<![\w.]) prevents matching mid-word; \s* catches spaces before K/M/B/%.
NUM = re.compile(r"(?<![\w.])\$?(\d[\d,]*(?:\.\d+)?)\s*(%|million|billion|[kmb](?![a-z]))?", re.I)
SCALE = {"k": 1e3, "m": 1e6, "million": 1e6, "b": 1e9, "billion": 1e9}


def numbers(text):
    """Extract and normalize numbers from text.
    Examples: '$136.97M' -> [(136970000.0, False)], '16.1%' -> [(16.1, True)]"""
    return [(float(n.replace(",", "")) * SCALE.get((u or "").lower(), 1), u == "%")
            for n, u in NUM.findall(text or "")]

def close(a, b):
    """Fuzzy matching for numbers to account for minor rounding differences.
    Uses 0.5% tolerance or 0.15 absolute difference (useful for small percentages)."""
    return abs(a - b) <= max(0.005 * abs(b), 0.15)

def flat(v):
    """Flattens truth dictionary or single value into a uniform list for comparison."""
    return [x for x in (v.values() if isinstance(v, dict) else [v]) if x is not None]

def has_all(names, truth, vals):
    """Checks if all expected truth values for given names are found in the extracted text values."""
    return all(any(close(v, t) for v in vals) for n in names for t in flat(truth[n]))


class Verdict(BaseModel):
    """Pydantic schema for the LLM judge.
    Code handles the math, the LLM judges subjective behavioral rules."""
    refused: bool             # declines / says out of scope, gives no answer
    clarifying_question: bool # asks the user to clarify instead of answering
    assumption_stated: bool   # states which metric / period / interpretation it used
    arithmetic_labeled: bool  # says a number was calculated or derived by itself


def judge(records, cache_file):
    """Uses a cheap LLM (Claude Haiku) to grade behavioral rules on the text answer.
    Results are cached to save time and API costs on repeated script executions."""
    cache = json.loads(cache_file.read_text()) if cache_file.exists() else {}

    # Configure LLM to strictly return the Verdict JSON schema
    llm = ChatAnthropic(model="claude-haiku-4-5-20251001", api_key=os.environ["AGENT_ANTHROPIC_API_KEY"],
                        max_tokens=300).with_structured_output(Verdict)

    for r in records:
        key = f"{r['id']}#{r['run']}"
        if key not in cache:
            # Prompt the LLM-as-a-judge with just the question and answer text
            cache[key] = llm.invoke(f"Grade ONLY what this analytics answer says.\nQuestion: {r['question']}\n"
                                    f"Answer:\n{r['answer'] or '(no answer)'}").model_dump()
            cache_file.write_text(json.dumps(cache, indent=2))
    return cache


def score(r, q, truth, all_truth, v):
    """The core scoring engine for a single agent execution run."""
    t, vals = truth.get(q["id"], {}), [n for n, _ in numbers(r["answer"])]

    # Check if the generated numbers match the expected answer key
    ok = (any(has_all([n], t, vals) for n in q["check_any"]) if q.get("check_any")
          else has_all(q.get("check", []), t, vals))

    # Look for known failure modes (e.g., outputting 'orders' when we explicitly wanted 'recognized_orders')
    wrong = [n for n in q.get("wrong", []) if has_all([n], t, vals)]

    # 1. Determine PASS/FAIL and record the specific reason
    if r.get("error"):                                  passed, why = False, "error"
    elif q["type"] == "out_of_scope":                   passed, why = v["refused"], "did not refuse"
    elif v["refused"]:                                  passed, why = False, "refused answerable question"
    elif q["type"] == "ambiguous" and v["clarifying_question"] and not ok: passed, why = True, ""
    elif not ok:                                        passed, why = False, f"wrong metric {wrong}" if wrong else "value missing"
    elif q["type"] == "ambiguous" and not v["assumption_stated"]: passed, why = False, "no assumption stated"
    elif q.get("derived") and not v["arithmetic_labeled"]:        passed, why = False, "arithmetic not labeled"
    else:                                               passed, why = True, ""

    # 2. Hallucination check: Is a number entirely made up?
    # A number is 'supported' if it appears in the raw SQL output, the answer key,
    # or is a simple derived calculation (ratio, percent difference, subtraction) of those base numbers.
    base = {n for x in r["tool_results"] for n, _ in numbers(x["content"])} | set(all_truth)
    base = [b for b in base if b > 0]
    supported = lambda n: any(close(n, b) for b in base) or any(
        close(n, a / b * 100) or close(n, (a - b) / b * 100) or close(n, a - b) for a in base for b in base)

    # Filter out dates/years (1900-2100) and minor numbers (<31) from being flagged as hallucinations
    unsupported = [n for n, pct in numbers(r["answer"])
                   if (pct or (n > 31 and not 1900 <= n <= 2100)) and not supported(n)]

    # 3. Metric Selection check: Did it use the right Semantic Layer metrics?
    # We parse the actual SQL query the agent constructed to see which metrics were queried
    sql = " ".join(c["args"].get("sql", "") for c in r["tool_calls"] if c["name"] == "run_metric_sql").upper()
    used = [m for m in METRICS if re.search(rf"\b{m.upper()}\b", sql)]
    exp, exp_any = q.get("expected_metrics"), q.get("expected_metrics_any")

    # Evaluate if the selected metrics match the evaluation expectations
    metric_ok = (all(m in used for m in exp) if exp else any(m in used for m in exp_any)) if sql and (exp or exp_any) else None

    return dict(id=r["id"], type=q["type"], passed=passed, why="" if passed else why, refused=v["refused"],
                answered=bool(r["answer"]) and not v["refused"], unsupported=unsupported,
                metric_ok=metric_ok, used=used, verdict=v, answer=r["answer"], run=r["run"])


def main():
    path = Path(sys.argv[1])
    qs = {q["id"]: q for q in yaml.safe_load((ROOT / "eval/questions.yaml").read_text(encoding="utf-8"))}
    truth = json.loads((ROOT / "eval/ground_truth.json").read_text())

    # Flatten all possible truth values to help identify hallucinations
    all_truth = [x for q in truth.values() for v in q.values() for x in flat(v)]

    # Parse the JSONL results file
    recs = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]

    # Run the LLM judge and standard code grading
    verdicts = judge(recs, path.with_name(path.stem + "_judge.json"))
    s = [score(r, qs[r["id"]], truth, all_truth, verdicts[f"{r['id']}#{r['run']}"]) for r in recs]

    # Helper lambda to format percentage strings for the markdown table
    pct = lambda rows, f: f"{100*sum(map(f, rows))/len(rows):.0f}% ({sum(map(f, rows))}/{len(rows)})" if rows else "n/a"

    # Group results by Question ID for the detail table
    by_q = defaultdict(list)
    for x in s:
        by_q[x["id"]].append(x)

    # ---------------------------------------------------------
    # Generate the Markdown Report
    # ---------------------------------------------------------

    # Top-line metrics table
    out = [f"# Eval report: {path.name}", "", "| Metric | Score |", "|---|---|",
           f"| 1. Answer accuracy (A-D) | {pct([x for x in s if x['type'] != 'out_of_scope'], lambda x: x['passed'])} |",
           f"| 2. Hallucination rate | {pct([x for x in s if x['answered']], lambda x: bool(x['unsupported']))} |",
           f"| 3. Metric selection | {pct([x for x in s if x['metric_ok'] is not None], lambda x: x['metric_ok'])} |",
           f"| 4. Correct refusal (E) | {pct([x for x in s if x['type'] == 'out_of_scope'], lambda x: x['refused'])} |",
           f"| 5. Consistency (pass^3) | {pct(list(by_q.values()), lambda runs: all(x['passed'] for x in runs))} |",
           "", "| Type | Accuracy |", "|---|---|"]

    # Accuracy broken down by Question Category (same_metric, ambiguous, etc.)
    out += [f"| {t} | {pct([x for x in s if x['type'] == t], lambda x: x['passed'])} |"
            for t in ["same_metric", "slice_filter", "ambiguous", "derived", "out_of_scope"]]

    # Detailed breakdown per specific question
    out += ["", "## Per question", "", "| ID | Passed | Why failed | Metrics used | Unsupported numbers |", "|---|---|---|---|---|"]
    out += [f"| {k} | {sum(x['passed'] for x in v)}/{len(v)} | {'; '.join(sorted({x['why'] for x in v if x['why']})) or '-'} "
            f"| {', '.join(sorted({m for x in v for m in x['used']})) or '-'} "
            f"| {', '.join(f'{n:,.2f}' for n in sorted({n for x in v for n in x['unsupported']})) or '-'} |"
            for k, v in by_q.items()]

    # Spot-check table to allow human review of the LLM Judge's subjective rulings
    out += ["", "## Judge spot-check (write y/n in Agree?)", "", "| Run | Verdict | Answer (start) | Agree? |", "|---|---|---|---|"]
    out += [f"| {x['id']}#{x['run']} | {', '.join(k for k, b in x['verdict'].items() if b) or 'none'} "
            f"| {x['answer'][:150].replace(chr(10), ' ').replace('|', '/')} | |" for x in random.Random(7).sample(s, min(10, len(s)))]

    # Write report to disk and print summary to terminal
    report = path.with_name(path.stem + "_report.md")
    report.write_text("\n".join(out) + "\n", encoding="utf-8")
    print("\n".join(out[:17]), f"\n\nFull report -> {report}")


if __name__ == "__main__":
    main()
