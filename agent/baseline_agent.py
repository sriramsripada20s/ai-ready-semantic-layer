"""S2 baseline: same model and rules as the Metrics Analyst, but NO semantic layer.
Claude sees raw ANALYTICS.MARTS tables and writes its own SQL."""

import json
import logging
import os
import re

from langchain.agents import create_agent
from langchain.tools import tool
from langchain_anthropic import ChatAnthropic
from langgraph.checkpoint.memory import InMemorySaver

from agent import snowflake_client as sf
from agent.metrics_agent import MODEL

log = logging.getLogger("agent.baseline")
MAX_ROWS = 200
# 3-part table names must be ANALYTICS.MARTS.<table> (2-part "alias.column" is fine)
_NON_MARTS_TABLE = re.compile(r"\b(?:from|join)\s+(?!analytics\.marts\.)\w+\.\w+\.\w+", re.I)

SCHEMA_SQL = """
select table_name,
       listagg(column_name || ' ' || data_type, ', ') within group (order by ordinal_position)
from analytics.information_schema.columns
where table_schema = 'MARTS' and table_name not like 'METRICFLOW%'
group by table_name
order by table_name"""

PROMPT = """You are a data analyst for an e-commerce company. You answer business questions by
writing Snowflake SQL against the tables below and running it with run_raw_sql.

Tables:
{schema}

Rules for every answer:
- Every number must come from a run_raw_sql result in this conversation. Never guess, recall, or invent numbers.
- Explain how each number was calculated (table, columns, filters).
- If the question is ambiguous, state the assumption you made, or ask one short clarifying question.
- If you do arithmetic on query results, show the inputs and label the result "calculated".
- If the data cannot answer the question, say so plainly and do not estimate.
- Never provide personal data about individuals (names, emails, addresses).
- If a query fails you may fix the SQL and retry, but never work around the SQL guard.
- Keep answers short: the number first, then how it was calculated, then assumptions.
"""


def check_raw_sql(sql: str) -> str:
    """Read-only, single statement, ANALYTICS.MARTS tables only, no semantic view."""
    body = re.sub(r"--[^\n]*", "", sql).strip().rstrip(";").strip()
    if ";" in body:
        raise ValueError("Only one SQL statement is allowed.")
    if not re.match(r"^(select|with)\b", body, re.I):
        raise ValueError("Only SELECT queries are allowed.")
    if re.search(r"semantic_view", body, re.I):
        raise ValueError("The semantic view is not available in this baseline.")
    if _NON_MARTS_TABLE.search(body):
        raise ValueError("Only ANALYTICS.MARTS tables may be queried.")
    if sf._WRITE_WORDS.search(body):
        raise ValueError("Write/DDL keywords are not allowed.")
    return body


@tool
async def run_raw_sql(sql: str) -> str:
    """Run a read-only Snowflake SQL query on the ANALYTICS.MARTS tables and return JSON (columns + rows).
    Always use fully qualified names, e.g. ANALYTICS.MARTS.FCT_ORDERS."""
    try:
        result = await sf.execute_sql(check_raw_sql(sql))
    except ValueError as e:
        return f"REFUSED by SQL guard: {e}"
    except RuntimeError as e:
        return f"Snowflake error: {e}"
    if len(result["rows"]) > MAX_ROWS:
        total = len(result["rows"])
        result["rows"], result["note"] = result["rows"][:MAX_ROWS], f"Truncated to {MAX_ROWS} of {total} rows."
    return json.dumps(result)


async def build_baseline_agent():
    rows = (await sf.execute_sql(SCHEMA_SQL))["rows"]
    schema = "\n".join(f"- ANALYTICS.MARTS.{table}: {cols}" for table, cols in rows)
    log.info("Baseline schema loaded: %d tables", len(rows))
    model = ChatAnthropic(model=MODEL, api_key=os.environ["AGENT_ANTHROPIC_API_KEY"], max_tokens=2000)
    return create_agent(model=model, tools=[run_raw_sql], system_prompt=PROMPT.format(schema=schema),
                        checkpointer=InMemorySaver())
