import copy

import pytest
from mcp.server.mcpserver import Image

from island_mcp import capture, invariants, server
from island_mcp.client import IslandClient
from island_mcp.result import Err, Ok

from .fake_app import BASE_STATE, FakeApp


@pytest.fixture
def app(monkeypatch):
    fake = FakeApp()
    monkeypatch.setattr(server, "client", IslandClient(fake.url))
    yield fake
    fake.close()


def playing_state():
    s = copy.deepcopy(BASE_STATE)
    s.update(state="collapsed", isIslandVisible=True, hasContent=True, title="Song", isPlaying=True, duration=200)
    s["islandShapeRect"] = {"x": 610, "y": 0, "width": 292, "height": 38}
    return s


# --- client ---

def test_client_unreachable_gives_actionable_error():
    result = IslandClient("http://127.0.0.1:1").get("/state")
    assert isinstance(result, Err)
    assert "rebuild_and_relaunch" in result.error


def test_client_http_error_carries_app_message(app):
    result = IslandClient(app.url).post("/inject/now-playing", {})
    assert isinstance(result, Err) and "title is required" in result.error


# --- tools ---

def test_get_state_returns_json(app):
    assert '"state": "hidden"' in server.get_state()


def test_inject_sends_body_and_expands_artwork_path(app):
    server.inject_now_playing("Song", "Artist", playing=False, artwork_path="~/a.png")
    method, path, body = app.requests[-1]
    assert (method, path) == ("POST", "/inject/now-playing")
    assert body["playing"] is False and body["title"] == "Song"
    assert not body["artwork_path"].startswith("~")


@pytest.mark.parametrize(
    "call, path",
    [
        (lambda: server.clear_injection(), "/inject/clear"),
        (lambda: server.hover(False), "/simulate/hover"),
        (lambda: server.tap(), "/simulate/tap"),
        (lambda: server.show_glance("Hi"), "/simulate/glance"),
        (lambda: server.start_timer(2), "/simulate/timer"),
        (lambda: server.toggle_lock_preview(), "/simulate/lock-preview"),
    ],
)
def test_action_tools_hit_endpoints(app, call, path):
    assert "error" not in call()
    assert app.requests[-1][1] == path


def test_get_logs_limits(app):
    assert server.get_logs(last=3).count('"event"') == 3


def test_check_invariants_ok(app):
    assert server.check_invariants().startswith("OK")


def test_check_invariants_reports_violation(app):
    app.state.update(title="Song", hasContent=True, isPlaying=False, isIslandVisible=False, state="collapsed")
    out = server.check_invariants()
    assert out.startswith("VIOLATIONS") and "should hide" in out


def test_screenshot_island_crops_window_and_bursts(app, monkeypatch):
    seen = []
    monkeypatch.setattr(server, "capturer", lambda rect: (seen.append(rect), Ok(b"png"))[1])
    monkeypatch.setattr(capture.time, "sleep", lambda _: None)
    out = server.screenshot_island(padding=10, frames=3)
    assert sum(isinstance(x, Image) for x in out) == 3
    assert seen[0] == {"x": 579, "y": 0, "width": 354, "height": 215}


def test_screenshot_island_error_when_app_down(monkeypatch):
    monkeypatch.setattr(server, "client", IslandClient("http://127.0.0.1:1"))
    assert server.screenshot_island()[0].startswith("error")


def test_rebuild_rejects_bad_config():
    assert server.rebuild_and_relaunch("fast").startswith("error")


# --- invariants ---

def test_invariants_clean_states():
    assert invariants.check(copy.deepcopy(BASE_STATE)) == []
    assert invariants.check(playing_state()) == []


def test_paused_track_must_hide_but_keep_content():
    s = playing_state()
    s.update(isPlaying=False, isIslandVisible=False, state="hidden")
    s["islandShapeRect"] = copy.deepcopy(BASE_STATE["islandShapeRect"])
    assert invariants.check(s) == []
    s["isIslandVisible"] = True
    assert any("isIslandVisible" in v for v in invariants.check(s))


def test_timer_counts_as_visible():
    s = copy.deepcopy(BASE_STATE)
    s.update(timerRemaining=60, isIslandVisible=True, state="collapsed")
    s["islandShapeRect"] = playing_state()["islandShapeRect"]
    assert invariants.check(s) == []


def test_glance_must_be_glance_state():
    s = copy.deepcopy(BASE_STATE)
    s["glanceTitle"] = "Meeting"
    assert any("glance" in v for v in invariants.check(s))


def test_geometry_violations():
    s = playing_state()
    s["islandWindow"]["frame"]["x"] += 20
    s["islandWindow"]["frame"]["y"] = 5
    s["islandShapeRect"]["width"] = 400
    found = "\n".join(invariants.check(s))
    assert "not centred on notch" in found and "top edge" in found and "overflows" in found


def test_idle_width_must_match_notch():
    s = copy.deepcopy(BASE_STATE)
    s["islandShapeRect"]["width"] = 200
    s["islandShapeRect"]["x"] = 656
    assert any("notch width" in v for v in invariants.check(s))


def test_playback_and_lyrics_bounds():
    s = playing_state()
    s.update(position=500, lyricsCount=3, currentLyricIndex=3)
    found = "\n".join(invariants.check(s))
    assert "past duration" in found and "out of range" in found


def test_region_around_clamps_to_screen():
    rect = capture.region_around({"x": 5, "y": 0, "width": 100, "height": 50}, {"x": 0, "y": 0, "width": 90, "height": 900}, 20)
    assert rect == {"x": 0, "y": 0, "width": 90, "height": 70}


def test_rebuild_timeout_returns_error(monkeypatch):
    def slow(*args, **kwargs):
        raise server.subprocess.TimeoutExpired(cmd="build_app.sh", timeout=900)

    monkeypatch.setattr(server.subprocess, "run", slow)
    assert server.rebuild_and_relaunch("debug").startswith("error: build did not finish")


def test_rebuild_missing_script_returns_error(monkeypatch):
    def missing(*args, **kwargs):
        raise FileNotFoundError("build_app.sh")

    monkeypatch.setattr(server.subprocess, "run", missing)
    assert server.rebuild_and_relaunch("debug").startswith("error: cannot run build_app.sh")
