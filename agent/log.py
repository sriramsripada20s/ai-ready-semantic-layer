"""Logging setup for the agent: readable format + automatic secret redaction."""

import logging
import os

from dotenv import load_dotenv

load_dotenv()


class RedactSecrets(logging.Filter):
    """Replace any token/API key value with ***REDACTED*** in every log line (ours and libraries')."""

    def __init__(self) -> None:
        super().__init__()
        self.secrets = [v for k, v in os.environ.items() if k.endswith(("_PAT", "_API_KEY")) and v]

    def filter(self, record: logging.LogRecord) -> bool:
        msg = record.getMessage()
        for secret in self.secrets:
            msg = msg.replace(secret, "***REDACTED***")
        record.msg, record.args = msg, None
        return True


def setup_logging(level: str | None = None) -> None:
    """LOG_LEVEL env var controls detail: DEBUG (everything) / INFO (flow) / WARNING (problems only)."""
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter(
        "%(asctime)s.%(msecs)03d | %(levelname)-5s | %(name)-22s | %(message)s", "%H:%M:%S"))
    handler.addFilter(RedactSecrets())

    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level or os.getenv("LOG_LEVEL", "INFO"))

    # Library noise: keep httpx at INFO (one line per HTTP call: URL + status, no headers)
    logging.getLogger("httpx").setLevel(logging.INFO)
    for http_logger in ("httpx", "httpx2"):
      logging.getLogger(http_logger).setLevel(logging.INFO)
    for noisy in ("httpcore", "httpcore2", "mcp", "anyio"):
      logging.getLogger(noisy).setLevel(logging.WARNING)
