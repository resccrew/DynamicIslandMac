"""Pure checks over a /state snapshot. Each returns human-readable violations (empty = all good)."""

from typing import Any

TOLERANCE = 1.0  # points


def check(state: dict[str, Any]) -> list[str]:
    violations: list[str] = []
    for rule in (_visibility, _content, _state_machine, _window_geometry, _shape_geometry, _playback, _lyrics):
        violations.extend(rule(state))
    return violations


def _visibility(s: dict[str, Any]) -> list[str]:
    out = []
    title = s.get("title") or ""
    timer = s.get("timerRemaining") is not None
    call = s.get("call") is not None
    expected_visible = (bool(s.get("isPlaying")) and title != "") or timer or call
    if s.get("isIslandVisible") != expected_visible:
        out.append(
            f"isIslandVisible={s.get('isIslandVisible')} but expected {expected_visible} "
            f"(isPlaying={s.get('isPlaying')}, title set={title != ''}, timer={timer}, call={call})"
        )
    if s.get("hasContent") != (title != ""):
        out.append(f"hasContent={s.get('hasContent')} but title is {'set' if title else 'empty'}")
    return out


def _content(s: dict[str, Any]) -> list[str]:
    """The island body follows a fixed priority: glance > call > timer > media."""
    content = s.get("content")
    if content is None:
        return []
    if s.get("glanceTitle") is not None:
        expected = "glance"
    elif s.get("call") is not None:
        expected = "call"
    elif s.get("timerRemaining") is not None:
        expected = "timer"
    elif s.get("isPlaying") and s.get("title"):
        expected = "media"
    else:
        # A paused track may still fill a click-opened card.
        expected = "media" if s.get("state") == "expanded" and s.get("hasContent") else "none"
    if content != expected:
        return [f"content={content} but priority glance>call>timer>media says {expected}"]
    return []


def _state_machine(s: dict[str, Any]) -> list[str]:
    out = []
    state = s.get("state")
    glance = s.get("glanceTitle") is not None
    hovering = bool(s.get("hoverSimulated"))
    if glance and state != "glance":
        out.append(f"glance '{s.get('glanceTitle')}' is active but state={state}")
    if not glance and not hovering:
        if s.get("isIslandVisible") and state == "hidden":
            out.append("island should be visible (playing/timer) but state=hidden")
        if not s.get("isIslandVisible") and state not in ("hidden",):
            out.append(f"nothing to show (paused/empty, no hover) but state={state} — island should hide")
    # A paused track may keep a click-opened card under the pointer (so its
    # play button stays reachable); only an empty title has nothing to show.
    if state == "expanded" and not s.get("isIslandVisible") and not s.get("hasContent"):
        out.append("state=expanded with nothing to show")
    if state == "expanded" and not s.get("isIslandVisible") and not hovering:
        out.append("paused card is still expanded after the pointer left")
    return out


def _center_x(rect: dict[str, float]) -> float:
    return rect["x"] + rect["width"] / 2


def _window_geometry(s: dict[str, Any]) -> list[str]:
    out = []
    window = s.get("islandWindow")
    notch = s.get("notchRect")
    if not window:
        return ["islandWindow missing from state"]
    frame = window["frame"]
    if frame["width"] <= 0 or frame["height"] <= 0:
        out.append(f"island window has zero size: {frame}")
    if not window.get("visible"):
        out.append("island panel is not ordered on screen")
    if notch and abs(_center_x(frame) - _center_x(notch)) > TOLERANCE:
        out.append(f"island window not centred on notch: window cx={_center_x(frame):.1f}, notch cx={_center_x(notch):.1f}")
    if abs(frame["y"]) > TOLERANCE:
        out.append(f"island window not pinned to top edge: y={frame['y']}")
    return out


def _shape_geometry(s: dict[str, Any]) -> list[str]:
    out = []
    shape = s.get("islandShapeRect")
    window = (s.get("islandWindow") or {}).get("frame")
    notch = s.get("notchRect")
    if not shape or not window:
        return out
    if abs(shape["y"]) > TOLERANCE:
        out.append(f"island shape not top-aligned: y={shape['y']}")
    if abs(_center_x(shape) - _center_x(window)) > TOLERANCE:
        out.append("island shape not horizontally centred in its window")
    if shape["width"] > window["width"] + TOLERANCE or shape["height"] > window["height"] + TOLERANCE:
        out.append(f"island shape {shape['width']}x{shape['height']} overflows window {window['width']}x{window['height']} (clipped)")
    has_notch = (s.get("screen") or {}).get("hasNotch")
    if s.get("state") == "hidden" and has_notch and notch and abs(shape["width"] - notch["width"]) > TOLERANCE:
        out.append(f"idle island width {shape['width']} != notch width {notch['width']} (would poke out)")
    return out


def _playback(s: dict[str, Any]) -> list[str]:
    duration = s.get("duration") or 0
    position = s.get("position") or 0
    out = []
    if position < 0:
        out.append(f"negative position {position}")
    if duration > 0 and position > duration + 1:
        out.append(f"position {position:.1f}s runs past duration {duration:.1f}s")
    return out


def _lyrics(s: dict[str, Any]) -> list[str]:
    count = s.get("lyricsCount") or 0
    index = s.get("currentLyricIndex")
    if index is not None and not (0 <= index < count):
        return [f"currentLyricIndex {index} out of range for {count} lines"]
    return []
