"""Interactive Metrics Analyst.

Run from repo root:  python -m agent.cli
Commands: /new = start a fresh conversation, /quit = exit
"""

import asyncio
import logging
import time
import uuid

from langgraph.errors import GraphRecursionError

from agent.log import setup_logging
from agent.metrics_agent import build_agent

# Set up a logger specifically for tracking the conversation flow
log = logging.getLogger("agent.flow")

# Safety limit: Prevent infinite loops if the agent gets stuck trying and failing
# to use tools over and over. 12 steps allow for a few tool attempts + reasoning.
STEP_LIMIT = 12  # model + tool steps per question (~5 tool rounds)


def text_of(msg) -> str:
    """Claude's content can be a string or a list of blocks; return the text."""
    # LangChain message contents can be simple strings or complex block structures.
    # This helper extracts just the readable text regardless of the format.
    if isinstance(msg.content, str):
        return msg.content
    return "".join(b.get("text", "") for b in msg.content if isinstance(b, dict) and b.get("type") == "text")


def short(value, n: int = 300) -> str:
    """Helper to truncate long strings for cleaner console logging."""
    # Replaces newlines with spaces and cuts off the string if it exceeds 'n' characters
    s = str(value).replace("\n", " ")
    return s if len(s) <= n else s[:n] + "..."


async def ask(agent, question: str, thread_id: str) -> str:
    """Submits a question to the agent and streams the thought process/execution."""

    # Configure the execution: tie it to a specific memory thread and apply the step limit
    config = {"configurable": {"thread_id": thread_id}, "recursion_limit": STEP_LIMIT}
    start, answer = time.perf_counter(), ""

    # stream_mode="updates": one event per step, so we can log each decision as it happens
    # By looping through updates, we can watch the AI plan, call tools, and receive data in real-time.
    async for update in agent.astream(
        {"messages": [{"role": "user", "content": question}]}, config=config, stream_mode="updates"
    ):
        for node, data in update.items():
            if not isinstance(data, dict):
                continue

            # Look at the messages generated in this specific step
            for msg in data.get("messages", []):

                # If it's a message from Claude (the AI)
                if msg.type == "ai":
                    # Check if Claude is trying to use a tool (like ask_metrics or run_metric_sql)
                    for call in msg.tool_calls:
                        log.info("[%s] Claude -> call %s(%s)", node, call["name"], short(call["args"], 200))

                    # If there are no tool calls, Claude has reached a final conclusion
                    if not msg.tool_calls:
                        answer = text_of(msg)
                        log.info("[%s] Claude -> final answer", node)

                    # Log token usage to track API costs and context window size
                    usage = msg.usage_metadata or {}
                    log.info("[%s] tokens in=%s out=%s", node, usage.get("input_tokens"), usage.get("output_tokens"))

                # If it's a message returning data from a tool
                elif msg.type == "tool":
                    log.info("[%s] %s returned: %s", node, msg.name, short(msg.content))

    log.info("Done in %.1fs", time.perf_counter() - start)
    return answer


async def main() -> None:
    """The main interactive loop (REPL) for the user terminal."""
    setup_logging()

    # Initialize the agent graph
    agent = await build_agent()

    # Create a unique ID for the initial conversation thread
    thread_id = str(uuid.uuid4())
    print("Metrics Analyst ready. Ask a question (/new = new conversation, /quit = exit).")

    while True:
        # Prompt the user for input. Use asyncio.to_thread so standard input doesn't block the async event loop.
        question = (await asyncio.to_thread(input, "\nYou: ")).strip()

        # Skip empty inputs
        if not question:
            continue

        # Handle custom exit command
        if question == "/quit":
            break

        # Handle custom reset command: generate a new thread ID to give the agent a "blank slate"
        if question == "/new":
            thread_id = str(uuid.uuid4())
            print("(new conversation)")
            continue

        try:
            # Process the user's question and print the final answer
            print("\nAnalyst:", await ask(agent, question, thread_id))
        except GraphRecursionError:
            # If the agent hits the STEP_LIMIT, it raises this error. Catch it cleanly.
            print(f"\nAnalyst: Stopped after {STEP_LIMIT} steps without an answer. Try a more specific question.")


if __name__ == "__main__":
    # Standard entry point to start the async event loop
    asyncio.run(main())
