"""Region screenshots via macOS `screencapture` (points in, Retina pixels out)."""

import io
import subprocess
import tempfile
import time
from collections.abc import Callable
from pathlib import Path

from PIL import Image as PILImage

from .result import Err, Ok, Result

type Rect = dict[str, float]
type Capturer = Callable[[Rect], Result[bytes]]

MAX_SIDE = 1400


def region_around(window: Rect, screen: Rect, padding: float) -> Rect:
    """Window frame grown by padding, clamped to the screen (all top-left points)."""
    x = max(screen["x"], window["x"] - padding)
    y = max(screen["y"], window["y"] - padding)
    right = min(screen["x"] + screen["width"], window["x"] + window["width"] + padding)
    bottom = min(screen["y"] + screen["height"], window["y"] + window["height"] + padding)
    return {"x": x, "y": y, "width": max(0.0, right - x), "height": max(0.0, bottom - y)}


def screencapture(rect: Rect) -> Result[bytes]:
    if rect["width"] <= 0 or rect["height"] <= 0:
        return Err(f"empty capture region {rect}")
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "shot.png"
        region = ",".join(str(round(rect[k])) for k in ("x", "y", "width", "height"))
        proc = subprocess.run(
            ["screencapture", "-x", "-t", "png", "-R", region, str(out)],
            capture_output=True,
            timeout=15,
        )
        if proc.returncode != 0 or not out.exists():
            return Err(
                "screencapture failed — grant Screen Recording to the app running Claude Code "
                f"(System Settings → Privacy & Security). {proc.stderr.decode(errors='replace').strip()}"
            )
        return Ok(_shrink(out.read_bytes()))


def _shrink(png: bytes) -> bytes:
    image = PILImage.open(io.BytesIO(png))
    if max(image.size) <= MAX_SIDE:
        return png
    image.thumbnail((MAX_SIDE, MAX_SIDE))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def burst(capture: Capturer, rect: Rect, frames: int, interval: float) -> Result[list[bytes]]:
    shots = []
    for index in range(frames):
        if index:
            time.sleep(interval)
        shot = capture(rect)
        if isinstance(shot, Err):
            return shot
        shots.append(shot.value)
    return Ok(shots)
