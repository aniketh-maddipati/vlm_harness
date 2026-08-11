#!/usr/bin/env python3
"""Local FAST-lane dashboard — streams lane events as NDJSON + a tiny HTML page.

Non-blocking: watch-mode runner posts events here; FULL/HEAVY never lock the
editing worktree (see worktree_runner.py).
"""
from __future__ import annotations

import argparse
import json
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EVENT_LOG = ROOT / "artifacts" / "harness" / "dashboard" / "events.ndjson"
STATIC = Path(__file__).resolve().parent / "static"

_lock = threading.Lock()


def append_event(event: dict) -> None:
    EVENT_LOG.parent.mkdir(parents=True, exist_ok=True)
    event = dict(event)
    event.setdefault("ts", datetime.now(timezone.utc).isoformat())
    with _lock:
        with EVENT_LOG.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(event, sort_keys=True) + "\n")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:  # quieter
        return

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path in {"/", "/index.html"}:
            html = (STATIC / "index.html").read_bytes()
            self._send(200, html, "text/html; charset=utf-8")
            return
        if self.path.startswith("/events"):
            data = EVENT_LOG.read_bytes() if EVENT_LOG.is_file() else b""
            self._send(200, data, "application/x-ndjson")
            return
        if self.path.startswith("/health"):
            self._send(200, b'{"ok":true}\n', "application/json")
            return
        self._send(404, b"not found\n", "text/plain")

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/event":
            self._send(404, b"not found\n", "text/plain")
            return
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length)
        try:
            event = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            self._send(400, b'{"ok":false}\n', "application/json")
            return
        append_event(event)
        self._send(200, b'{"ok":true}\n', "application/json")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args(argv)
    EVENT_LOG.parent.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"harness dashboard http://{args.host}:{args.port}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
