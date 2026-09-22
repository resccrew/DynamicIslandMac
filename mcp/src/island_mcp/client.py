"""HTTP client for the app's DEBUG control server on 127.0.0.1."""

import json
import os
import urllib.error
import urllib.request
from typing import Any

from .result import Err, Ok, Result

DEFAULT_URL = "http://127.0.0.1:47800"
NOT_RUNNING = (
    "debug server not reachable at {url}. The app must be a DEBUG build and running: "
    "call rebuild_and_relaunch (release builds contain no debug server)."
)


class IslandClient:
    def __init__(self, base_url: str | None = None, timeout: float = 3.0) -> None:
        self.base_url = (base_url or os.environ.get("ISLAND_DEBUG_URL") or DEFAULT_URL).rstrip("/")
        self.timeout = timeout

    def get(self, path: str) -> Result[dict[str, Any]]:
        return self._request("GET", path, None)

    def post(self, path: str, body: dict[str, Any] | None = None) -> Result[dict[str, Any]]:
        return self._request("POST", path, body or {})

    def _request(self, method: str, path: str, body: dict[str, Any] | None) -> Result[dict[str, Any]]:
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(
            self.base_url + path,
            data=data,
            method=method,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return _decode(response.read())
        except urllib.error.HTTPError as exc:
            decoded = _decode(exc.read())
            message = decoded.value.get("error") if isinstance(decoded, Ok) else None
            return Err(f"HTTP {exc.code}: {message or exc.reason}")
        except (urllib.error.URLError, ConnectionError, TimeoutError, OSError):
            return Err(NOT_RUNNING.format(url=self.base_url))


def _decode(raw: bytes) -> Result[dict[str, Any]]:
    try:
        value = json.loads(raw or b"{}")
    except json.JSONDecodeError:
        return Err(f"invalid JSON from app: {raw[:200]!r}")
    if not isinstance(value, dict):
        return Err("unexpected JSON from app")
    return Ok(value)
