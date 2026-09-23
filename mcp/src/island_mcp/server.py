"""MCP server for testing DynamicIslandMac: reads live state from the app's DEBUG control server,
injects tracks, simulates hover/glance/timer, takes island screenshots and checks invariants."""

import json
import logging
import os
import subprocess
import time
from pathlib import Path
from typing import Any

from mcp.server.mcpserver import Image, MCPServer

from . import capture, invariants
from .client import IslandClient
from .result import Err, Ok, Result

log = logging.getLogger("island_mcp")

INSTRUCTIONS = """\
QA tools for the DynamicIslandMac app (macOS Dynamic Island clone). Needs a DEBUG build running:
call rebuild_and_relaunch first if get_state says the debug server is unreachable.
- get_state: live view-model + window geometry (top-left points, main display).
- inject_now_playing / clear_injection: fake a track without Spotify; the real poller is paused while injected.
- hover, tap, show_glance, start_timer, toggle_lock_preview: drive the UI states.
- The timer is the SYSTEM Clock timer (Часы/Siri/Shortcuts), read from mobiletimerd's log;
  start_timer injects one (seconds/paused/title/fire), cancel=true returns to real timers.
- Now Playing is system-wide (any app or browser tab; state.nowPlayingSource="system").
  inject_now_playing(bundle_id=...) fakes the source app (its icon shows when there is no artwork);
  send_command drives play/pause/next through the same path as the island's buttons.
- inject_call / clear_call fake a call (priority: glance > call > timer > media, see state.content);
  set_call_apps makes extra bundle ids count as call apps to exercise REAL mic detection
  (e.g. "com.apple.CoreSpeech" while Siri listens; a call starts after 2s of mic use).
- screenshot_island: crop around the island; frames>1 for animations (fade, spring).
- check_invariants: after every action, list violated rules (visibility, state machine, geometry).
- get_logs: in-memory event history (state changes, injections).
- The physical notch is not in screenshots: an idle/hidden island looks like wallpaper there, that is expected.
- tap/hover keep a simulated pointer over the island; call hover(inside=false) to release it.
Look at screenshots AND invariants; report every mismatch as a bug with repro steps.
"""

PROJECT_DIR = Path(os.environ.get("ISLAND_PROJECT_DIR", Path(__file__).resolve().parents[3]))
APP_PATH = PROJECT_DIR / "build" / "DynamicIslandMac.app"
# Exact process name: `pkill -f <path>` would also match any shell whose command line mentions it.
PROCESS_NAME = "DynamicIslandMac"

mcp = MCPServer(name="island", instructions=INSTRUCTIONS)
client = IslandClient()
capturer: capture.Capturer = capture.screencapture


def _text(result: Result[Any]) -> str:
    if isinstance(result, Err):
        return f"error: {result.error}"
    return json.dumps(result.value, ensure_ascii=False, indent=1)


def _post(path: str, body: dict[str, Any] | None = None) -> str:
    return _text(client.post(path, body))


@mcp.tool()
def get_state() -> str:
    """Current island state, track, flags and window/notch geometry (top-left points)."""
    return _text(client.get("/state"))


@mcp.tool()
def inject_now_playing(
    title: str,
    artist: str = "",
    playing: bool = True,
    position: float = 0,
    duration: float = 200,
    artwork_path: str | None = None,
    bundle_id: str | None = None,
) -> str:
    """Feed a fake track into the app (pauses the real Spotify/Music poller until clear_injection).
    Call again with playing=false to simulate pause."""
    body: dict[str, Any] = {
        "title": title,
        "artist": artist,
        "playing": playing,
        "position": position,
        "duration": duration,
    }
    if artwork_path:
        body["artwork_path"] = str(Path(artwork_path).expanduser())
    if bundle_id:
        body["bundle_id"] = bundle_id
    return _post("/inject/now-playing", body)


@mcp.tool()
def send_command(command: str) -> str:
    """Transport command via the island's own path to the active source: play_pause, next or previous.
    Works on the real player (Spotify, a YouTube tab …) when nothing is injected."""
    if command not in ("play_pause", "next", "previous"):
        return "error: command must be play_pause, next or previous"
    return _post("/simulate/command", {"command": command})


@mcp.tool()
def inject_call(bundle_id: str, app: str | None = None, camera: bool = False, elapsed: float = 0) -> str:
    """Fake a call in an app (e.g. ru.keepcoder.Telegram); pauses real call detection until clear_call."""
    body: dict[str, Any] = {"bundle_id": bundle_id, "camera": camera, "elapsed": elapsed}
    if app:
        body["app"] = app
    return _post("/inject/call", body)


@mcp.tool()
def clear_call() -> str:
    """End the injected call; real mic/camera detection takes over again."""
    return _post("/inject/call/clear")


@mcp.tool()
def set_call_apps(bundle_ids: list[str]) -> str:
    """Treat these extra bundle ids as call apps (live test of the real CoreAudio detection). [] resets."""
    return _post("/simulate/call-apps", {"bundle_ids": bundle_ids})


@mcp.tool()
def clear_injection() -> str:
    """Stop injecting; the real player poller takes over again within ~1s."""
    return _post("/inject/clear")


@mcp.tool()
def hover(inside: bool = True) -> str:
    """Simulate the pointer entering (inside=true) or leaving the island."""
    return _post("/simulate/hover", {"inside": inside})


@mcp.tool()
def tap() -> str:
    """Simulate a click on the island (toggles the expanded card while something plays).
    The pointer is treated as over the island until hover(inside=false)."""
    return _post("/simulate/tap")


@mcp.tool()
def show_glance(title: str, subtitle: str | None = None) -> str:
    """Show a 4-second glance (the notice mechanism used for calendar events/timer end)."""
    return _post("/simulate/glance", {"title": title, "subtitle": subtitle})


@mcp.tool()
def start_timer(
    minutes: float = 1,
    cancel: bool = False,
    seconds: float | None = None,
    paused: bool = False,
    title: str = "",
    fire: bool = False,
) -> str:
    """Inject a system-Clock-like timer (the island follows the macOS Clock app's timers).
    seconds overrides minutes; paused=true freezes it; fire=true simulates it going off
    (the "Таймер завершён" glance); cancel=true ends the injection and brings back the
    real Clock timers."""
    body: dict = {"minutes": minutes, "cancel": cancel}
    if seconds is not None:
        body["seconds"] = seconds
    if paused:
        body["paused"] = True
    if title:
        body["title"] = title
    if fire:
        body["fire"] = True
    return _post("/simulate/timer", body)


@mcp.tool()
def toggle_lock_preview() -> str:
    """Show/hide the lock-screen card overlay without locking the Mac."""
    return _post("/simulate/lock-preview")


@mcp.tool()
def get_logs(last: int = 50) -> str:
    """Recent in-app events (state changes, injections), newest last."""
    result = client.get("/logs")
    if isinstance(result, Ok):
        return _text(Ok(result.value.get("events", [])[-last:]))
    return _text(result)


@mcp.tool()
def check_invariants() -> str:
    """Check the live state against the app's rules. Returns OK or a list of violations."""
    result = client.get("/state")
    if isinstance(result, Err):
        return _text(result)
    violations = invariants.check(result.value)
    if not violations:
        return f"OK — all invariants hold (state={result.value.get('state')})"
    return "VIOLATIONS:\n" + "\n".join(f"- {v}" for v in violations)


@mcp.tool()
def screenshot_island(padding: float = 30, frames: int = 1, interval: float = 0.1, full_window: bool = True) -> list[str | Image]:
    """Screenshot around the island. frames>1 captures a burst (e.g. frames=6, interval=0.08 right
    after a pause to see the fade). full_window=false crops to the current shape rect instead of the panel."""
    state = client.get("/state")
    if isinstance(state, Err):
        return [f"error: {state.error}"]
    s = state.value
    key = "islandWindow" if full_window else "islandShapeRect"
    target = s.get(key, {})
    target = target.get("frame", target) if full_window else target
    if not target:
        return [f"error: {key} missing from state"]
    rect = capture.region_around(target, s["screen"]["frame"], padding)
    shots = capture.burst(capturer, rect, max(1, min(frames, 20)), max(0.0, interval))
    if isinstance(shots, Err):
        return [f"error: {shots.error}"]
    note = f"state={s.get('state')} region={rect} frames={len(shots.value)}"
    return [note, *(Image(data=png, format="png") for png in shots.value)]


@mcp.tool()
def rebuild_and_relaunch(config: str = "debug") -> str:
    """Build the app (./build_app.sh debug|release), quit the running copy, launch the fresh build
    and wait for the debug server. Takes up to a few minutes on a cold build."""
    if config not in ("debug", "release"):
        return "error: config must be debug or release"
    try:
        build = subprocess.run(
            ["./build_app.sh", config], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=900
        )
    except subprocess.TimeoutExpired:
        return "error: build did not finish within 15 minutes"
    except OSError as exc:
        return f"error: cannot run build_app.sh: {exc}"
    if build.returncode != 0:
        errors = [line for line in build.stdout.splitlines() + build.stderr.splitlines() if "error" in line]
        return "error: build failed\n" + "\n".join((errors or build.stderr.splitlines())[-30:])
    subprocess.run(["pkill", "-x", PROCESS_NAME], capture_output=True)
    time.sleep(1)
    subprocess.run(["open", "-n", str(APP_PATH)], capture_output=True)
    if config == "release":
        return f"built and launched release build ({APP_PATH}); debug tools are unavailable in release"
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        state = client.get("/state")
        if isinstance(state, Ok):
            return f"rebuilt and relaunched debug build; state={state.value.get('state')}"
        time.sleep(0.5)
    return "error: app launched but the debug server did not answer within 20s"


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")  # stderr
    mcp.run()
