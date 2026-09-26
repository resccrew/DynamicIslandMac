"""In-process fake of the app's DEBUG control server."""

import copy
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

BASE_STATE: dict[str, Any] = {
    "state": "hidden",
    "isIslandVisible": False,
    "hasContent": False,
    "title": "",
    "artist": "",
    "isPlaying": False,
    "position": 0,
    "duration": 0,
    "lyricsCount": 0,
    "currentLyricIndex": None,
    "timerRemaining": None,
    "glanceTitle": None,
    "hoverSimulated": False,
    "injecting": False,
    # The legacy "hide on pause" mode, which most tests below exercise.
    "settings": {"hideWhenPaused": True},
    "screen": {"frame": {"x": 0, "y": 0, "width": 1512, "height": 982}, "scale": 2, "hasNotch": True},
    "notchRect": {"x": 663, "y": 0, "width": 186, "height": 32},
    "islandWindow": {"frame": {"x": 589, "y": 0, "width": 334, "height": 205}, "visible": True, "alpha": 1},
    "islandShapeRect": {"x": 663, "y": 0, "width": 186, "height": 36},
}


class FakeApp:
    def __init__(self) -> None:
        self.state = copy.deepcopy(BASE_STATE)
        self.requests: list[tuple[str, str, dict[str, Any]]] = []
        app = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args: Any) -> None:
                pass

            def _reply(self, status: int, body: dict[str, Any]) -> None:
                data = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self) -> None:
                app.requests.append(("GET", self.path, {}))
                if self.path == "/state":
                    return self._reply(200, app.state)
                if self.path == "/logs":
                    return self._reply(200, {"events": [{"t": i, "event": f"e{i}"} for i in range(10)]})
                self._reply(404, {"error": "unknown"})

            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length", 0))
                body = json.loads(self.rfile.read(length) or b"{}")
                app.requests.append(("POST", self.path, body))
                if self.path == "/inject/now-playing" and "title" not in body:
                    return self._reply(400, {"error": "title is required"})
                self._reply(200, {"ok": True})

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, args=(0.01,), daemon=True).start()

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
