"""Smoke test: question -> ask_metrics (MCP) -> SQL -> run_metric_sql (SQL API) -> number.

Run from repo root:
  python scripts/test_mcp.py                       # INFO: the flow
  $env:LOG_LEVEL="DEBUG"; python scripts/test_mcp.py   # DEBUG: raw payloads + SQL
"""

import asyncio
import logging
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # so "agent" is importable

from agent.log import setup_logging
from agent.snowflake_client import mcp_client, parse_analyst, run_metric_sql, tool_text

log = logging.getLogger("test_mcp")
QUESTION = "What is our total net revenue?"


async def main() -> None:
    log.info("STEP 1 tools/list")
    t = time.perf_counter()
    tools = await mcp_client().get_tools()
    log.info("tools found: %s (%.2fs)", [x.name for x in tools], time.perf_counter() - t)
    ask = next(x for x in tools if x.name == "ask_metrics")
    log.debug("ask_metrics input schema: %s", ask.args_schema)

    log.info('STEP 2 ask_metrics: "%s"', QUESTION)
    t = time.perf_counter()
    parsed = parse_analyst(tool_text(await ask.ainvoke({"message": QUESTION})))
    log.info("ask_metrics done (%.2fs)", time.perf_counter() - t)
    log.info("INTERPRETATION %s", parsed["interpretation"])
    if not parsed["sql"]:
        log.info("No SQL returned, stopping (question may be out of scope).")
        return

    log.info("STEP 3 run SQL")
    log.info("RESULT %s", await run_metric_sql(parsed["sql"]))

    log.info("STEP 4 guard test (raw table query)")
    try:
        await run_metric_sql("select sum(net_amount) from analytics.marts.fct_orders")
        log.error("GUARD FAILED: raw table query was allowed")
    except ValueError:
        log.info("Guard test OK")


if __name__ == "__main__":
    setup_logging()
    asyncio.run(main())
