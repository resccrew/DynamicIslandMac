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


# --- system now playing + calls ---

def test_inject_passes_source_bundle_id(app):
    server.inject_now_playing("Video", bundle_id="com.google.Chrome")
    assert app.requests[-1][2]["bundle_id"] == "com.google.Chrome"


def test_inject_without_bundle_id_omits_it(app):
    server.inject_now_playing("Song")
    assert "bundle_id" not in app.requests[-1][2]


@pytest.mark.parametrize(
    "call, path, body",
    [
        (lambda: server.send_command("play_pause"), "/simulate/command", {"command": "play_pause"}),
        (lambda: server.inject_call("ru.keepcoder.Telegram", camera=True),
         "/inject/call", {"bundle_id": "ru.keepcoder.Telegram", "camera": True, "elapsed": 0}),
        (lambda: server.clear_call(), "/inject/call/clear", {}),
        (lambda: server.set_call_apps(["com.apple.CoreSpeech"]),
         "/simulate/call-apps", {"bundle_ids": ["com.apple.CoreSpeech"]}),
    ],
)
def test_call_and_command_tools_hit_endpoints(app, call, path, body):
    assert "error" not in call()
    assert app.requests[-1][1:] == (path, body)


def test_send_command_rejects_unknown(app):
    assert server.send_command("stop").startswith("error")
    assert app.requests == []


def call_state(**extra):
    s = playing_state()
    s.update(content="call", call={"app": "Telegram", "bundleID": "ru.keepcoder.Telegram", "cameraOn": False, "elapsed": 3})
    s.update(extra)
    return s


def test_call_counts_as_visible_even_when_paused():
    s = call_state(isPlaying=False)
    assert invariants.check(s) == []
    s["isIslandVisible"] = False
    s["state"] = "hidden"
    assert any("isIslandVisible" in v for v in invariants.check(s))


def test_content_priority():
    assert invariants.check(call_state()) == []
    assert any("priority" in v for v in invariants.check(call_state(content="media")))
    glance = call_state(glanceTitle="Встреча", state="glance", content="glance")
    assert invariants.check(glance) == []
    timer_and_call = call_state(timerRemaining=30)
    assert invariants.check(timer_and_call) == []
    assert any("priority" in v for v in invariants.check(call_state(timerRemaining=30, content="timer")))


def test_content_media_and_none():
    s = playing_state()
    s["content"] = "media"
    assert invariants.check(s) == []
    s.update(isPlaying=False, isIslandVisible=False, state="hidden", content="none")
    s["islandShapeRect"] = dict(BASE_STATE["islandShapeRect"])
    assert invariants.check(s) == []


# --- system Clock timer ---

def timer_state(**timer):
    s = copy.deepcopy(BASE_STATE)
    t = {"id": "x", "title": "", "duration": 300, "paused": False, "remaining": 120}
    t.update(timer)
    s.update(timerRemaining=round(t["remaining"]), timer=t, isIslandVisible=True,
             state="collapsed", content="timer")
    s["islandShapeRect"] = playing_state()["islandShapeRect"]
    return s


def test_system_timer_consistent_state_passes():
    assert invariants.check(timer_state()) == []
    assert invariants.check(timer_state(paused=True, remaining=42)) == []


def test_system_timer_mismatch_is_reported():
    s = timer_state()
    s["timerRemaining"] = None
    assert any("timerRemaining" in v for v in invariants.check(s))
    s = timer_state()
    s["timer"] = None
    assert any("timer=None" in v for v in invariants.check(s))


def test_system_timer_drift_and_bounds():
    s = timer_state(remaining=100)
    s["timerRemaining"] = 110
    assert any("drifts" in v for v in invariants.check(s))
    s = timer_state(duration=60, remaining=90)
    assert any("exceeds" in v for v in invariants.check(s))


def test_start_timer_forwards_system_timer_options(app):
    server.start_timer(seconds=12, paused=True, title="Паста")
    method, path, body = app.requests[-1]
    assert path == "/simulate/timer"
    assert body["seconds"] == 12 and body["paused"] is True and body["title"] == "Паста"
    server.start_timer(fire=True)
    assert app.requests[-1][2]["fire"] is True
    server.start_timer(cancel=True)
    assert app.requests[-1][2]["cancel"] is True


# --- nothing under the camera notch ---

def notch_state(frames, state="collapsed"):
    s = playing_state()
    s["state"] = state
    s["notchRect"] = {"x": 751, "y": 0, "width": 208, "height": 37.5}
    s["contentFrames"] = frames
    return s


def test_content_in_the_ears_passes():
    frames = {
        "leading": {"x": 723, "y": 6, "width": 26, "height": 26},
        "trailing": {"x": 965, "y": 12, "width": 30, "height": 14},
    }
    assert [v for v in invariants.check(notch_state(frames)) if "overlaps the camera" in v] == []


def test_countdown_under_the_notch_is_reported():
    frames = {"trailing": {"x": 940, "y": 12, "width": 40, "height": 16}}
    violations = [v for v in invariants.check(notch_state(frames)) if "overlaps the camera" in v]
    assert violations and "trailing" in violations[0]


def test_notch_rule_ignores_expanded_and_glance():
    frames = {"leading": {"x": 800, "y": 5, "width": 40, "height": 20}}
    for state in ("expanded", "glance", "hidden"):
        assert [v for v in invariants.check(notch_state(frames, state)) if "overlaps the camera" in v] == []
