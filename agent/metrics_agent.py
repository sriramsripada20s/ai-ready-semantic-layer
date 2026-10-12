"""Builds the Metrics Analyst agent: Claude + tools + rules + memory."""

import os

from langchain.agents import create_agent
from langchain_anthropic import ChatAnthropic
from langgraph.checkpoint.memory import InMemorySaver

# Import the rules (system prompt) and the tools (Cortex Analyst + SQL Executor) we built
from agent.prompts import SYSTEM_PROMPT
from agent.tools import load_tools

# Define the specific AI model to use for the reasoning engine
MODEL = "claude-haiku-4-5-20251001"


async def build_agent():
    """Constructs and configures the AI agent ready for interaction."""

    # 1. Configure the LLM (the "brain" of the agent)
    model = ChatAnthropic(
        model=MODEL,
        api_key=os.environ["AGENT_ANTHROPIC_API_KEY"],  # not ANTHROPIC_API_KEY (keeps Claude Code on Pro)
        max_tokens=2000,
    )

    # 2. Load the tools ("ask_metrics" and "run_metric_sql")
    tools = await load_tools()

    # 3. Assemble the final agent graph
    return create_agent(
        model=model,        # The configured Claude model
        tools=tools,        # The MCP and local Python tools it is allowed to use
        system_prompt=SYSTEM_PROMPT, # The behavioral instructions and guardrails
        # The checkpointer provides short-term memory, allowing the agent to remember
        # context (like follow-up questions) for the duration of a single session/thread.
        checkpointer=InMemorySaver(),   # remembers each conversation (thread) while the program runs
    )
