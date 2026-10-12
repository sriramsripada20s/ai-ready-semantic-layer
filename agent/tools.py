"""Tools the agent can call. Claude sees only each tool's name, docstring and input schema."""

import json
import logging

from langchain.tools import tool

from agent import snowflake_client as sf

# Initialize a logger to track when tools are loaded or used
log = logging.getLogger("agent.tools")

# Safety limit: Prevent the agent's context window from overflowing if a query returns thousands of rows
MAX_ROWS = 200  # keep tool results small enough for the model to read


# The @tool decorator exposes this Python function to the LangChain AI agent
@tool
async def run_metric_sql(sql: str) -> str:
    """Execute the SQL returned by ask_metrics and return the result as JSON (columns + rows).

    Pass the SQL exactly as ask_metrics returned it. Only read-only queries over the
    ECOM_METRICS semantic view are accepted; anything else is refused.
    """
    try:
        # Attempt to run the SQL using the secure client we built in snowflake_client.py
        result = await sf.run_metric_sql(sql)

    except ValueError as e:          # guard refused it
        # If the local security guardrails block the query, return the reason as a string
        # This allows the AI to see the error and try again, rather than crashing the whole program
        return f"REFUSED by SQL guard: {e}"

    except RuntimeError as e:        # Snowflake returned an error
        # If Snowflake fails to execute it (e.g., syntax error), return the database error to the AI
        return f"Snowflake error: {e}"

    # If the query succeeds but returns too much data, truncate it
    if len(result["rows"]) > MAX_ROWS:
        total = len(result["rows"])
        result["rows"] = result["rows"][:MAX_ROWS] # Slice the list to keep only up to MAX_ROWS

        # Add a note so the AI knows it's only looking at a partial dataset
        result["note"] = f"Truncated to first {MAX_ROWS} of {total} rows."

    # Convert the Python dictionary back into a JSON string so the AI can read it easily
    return json.dumps(result)


async def load_tools() -> list:
    """ask_metrics comes from the Snowflake MCP server; run_metric_sql is local Python."""

    # Connect to the Snowflake MCP server and fetch all available remote tools
    mcp_tools = await sf.mcp_client().get_tools()

    # Filter the list to isolate just the Cortex Analyst translation tool
    ask = [t for t in mcp_tools if t.name == "ask_metrics"]

    # Failsafe: if the MCP server is down or misconfigured, stop immediately
    if not ask:
        raise RuntimeError("ask_metrics not found on the MCP server")

    # Combine the remote Snowflake MCP tool with our local Python execution tool
    tools = [*ask, run_metric_sql]

    # Log the final list of tools that will be handed to the AI agent
    log.info("Tools loaded: %s", [t.name for t in tools])

    return tools
