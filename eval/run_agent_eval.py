"""Run the eval: every question x N runs, a fresh conversation each time. Records everything.

Run from repo root:
  python eval/run_agent_eval.py --only A1,C1,E1 --runs 1    # quick test (~3 cents)
  python eval/run_agent_eval.py                            # full: 20 questions x 3 runs
Output: eval/results/agent_<timestamp>.jsonl  (one JSON line per run)
"""

import argparse
import asyncio
import json
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path

# Establish the repository root path
ROOT = Path(__file__).resolve().parents[1]
# Add the root directory to the system path so Python can find and import the 'agent' package
sys.path.insert(0, str(ROOT))

import yaml
from langgraph.errors import GraphRecursionError

from agent.cli import STEP_LIMIT, text_of
from agent.log import setup_logging
from agent.metrics_agent import MODEL, build_agent
from agent.baseline_agent import build_baseline_agent

RESULTS = ROOT / "eval" / "results"
# Limit tool result string length in the logs so massive SQL payloads don't bloat the JSONL file
MAX_TOOL_CHARS = 4000


async def run_once(agent, question: str) -> dict:
    """Ask one question in a brand-new conversation and capture every step."""

    # Use a fresh UUID for the thread_id to ensure NO memory/context carries over between test runs.
    # Enforce the step limit to prevent infinite tool-calling loops.
    config = {"configurable": {"thread_id": str(uuid.uuid4())}, "recursion_limit": STEP_LIMIT}

    # Initialize a dictionary to record everything that happens during this specific run
    rec = {"answer": "", "tool_calls": [], "tool_results": [], "model_calls": 0,
           "input_tokens": 0, "output_tokens": 0, "error": None}

    start = time.perf_counter()
    try:
        # Process the streaming events from the agent
        async for update in agent.astream(
            {"messages": [{"role": "user", "content": question}]}, config=config, stream_mode="updates"
        ):
            for _node, data in update.items():
                if not isinstance(data, dict):
                    continue

                # Inspect the messages generated in this step
                for msg in data.get("messages", []):
                    if msg.type == "ai":
                        rec["model_calls"] += 1

                        # Record token usage for cost tracking
                        usage = msg.usage_metadata or {}
                        rec["input_tokens"] += usage.get("input_tokens", 0)
                        rec["output_tokens"] += usage.get("output_tokens", 0)

                        # Capture which tools the model decided to call, and with what arguments
                        rec["tool_calls"] += [{"name": c["name"], "args": c["args"]} for c in msg.tool_calls]

                        # If there are no tool calls in an AI message, we've reached the final text answer
                        if not msg.tool_calls:
                            rec["answer"] = text_of(msg)

                    elif msg.type == "tool":
                        # Record what the tool actually returned, truncated to keep the file size manageable
                        rec["tool_results"].append({"name": msg.name, "content": str(msg.content)[:MAX_TOOL_CHARS]})

    except GraphRecursionError:
        # Catch agents that get stuck in an endless loop of bad tool calls
        rec["error"] = f"step limit ({STEP_LIMIT}) reached"

    rec["latency_s"] = round(time.perf_counter() - start, 2)
    return rec


async def main() -> None:
    # CLI arguments allow for quick debugging of specific questions or full evaluation runs
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--only", default="", help="comma-separated question ids, e.g. A1,C1")
    parser.add_argument("--system", choices=["s1", "s2"], default="s1")
    args = parser.parse_args()

    # Suppress standard info logs so the evaluation output in the terminal stays clean
    setup_logging("WARNING")

    # Load the evaluation test suite
    questions = yaml.safe_load((ROOT / "eval" / "questions.yaml").read_text(encoding="utf-8"))

    # Filter questions if the user specified the --only flag
    if args.only:
        wanted = {x.strip() for x in args.only.split(",")}
        questions = [q for q in questions if q["id"] in wanted]

    # Set up the output directory and a timestamped JSONL file
    RESULTS.mkdir(parents=True, exist_ok=True)
    out = RESULTS / f"{args.system}_{datetime.now():%Y%m%d_%H%M%S}.jsonl"

    agent = await (build_agent() if args.system == "s1" else build_baseline_agent())
    total, n = len(questions) * args.runs, 0
    print(f"Model {MODEL} | {len(questions)} questions x {args.runs} runs -> {out.relative_to(ROOT)}\n")

    # Open in append mode ("a") to write results as they happen
    with out.open("a", encoding="utf-8") as f:
        for q in questions:
            # Run each question multiple times to account for LLM variance/non-determinism
            for run in range(1, args.runs + 1):
                n += 1
                # Basic retry logic for transient network or API errors (e.g., rate limits)
                for attempt in (1, 2):
                    try:
                        rec = await run_once(agent, q["question"])
                        break
                    except Exception as e:
                        if attempt == 2:
                            # If it fails twice, record the failure and move on so the eval doesn't crash entirely
                            rec = {"answer": "", "tool_calls": [], "tool_results": [], "model_calls": 0,
                                   "input_tokens": 0, "output_tokens": 0, "latency_s": None,
                                   "error": f"{type(e).__name__}: {e}"}
                        else:
                            print(f"   retrying in 15s after {type(e).__name__}")
                            await asyncio.sleep(15)

                # Combine the original question metadata with the recorded execution metrics
                rec = {"id": q["id"], "type": q["type"], "run": run, "question": q["question"], "model": MODEL, **rec}

                # Write to file and flush immediately so data isn't lost if the script crashes halfway
                f.write(json.dumps(rec) + "\n")
                f.flush()

                # Print a concise summary of this specific run to the terminal
                tools = " > ".join(c["name"] for c in rec["tool_calls"]) or "no tools"
                err = f" | ERROR {rec['error']}" if rec["error"] else ""
                print(f"[{n:>2}/{total}] {q['id']} run {run}: {tools} | {rec['latency_s']}s "
                      f"| in={rec['input_tokens']} out={rec['output_tokens']}{err}")

    print(f"\nDone -> {out.relative_to(ROOT)}")


if __name__ == "__main__":
    asyncio.run(main())
