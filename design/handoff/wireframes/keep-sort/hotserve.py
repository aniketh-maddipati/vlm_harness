#!/usr/bin/env python3
"""Tiny hot-reload static server for wireframe HTML. Watches the folder; injects a reload script."""
from __future__ import annotations

import argparse
import hashlib
import mimetypes
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

RELOAD_JS = b"""
<script>
(() => {
  let last = '';
  async function tick() {
    try {
      const r = await fetch('/__hot', { cache: 'no-store' });
      const t = await r.text();
      if (last && t !== last) location.reload();
      last = t;
    } catch (_) {}
    setTimeout(tick, 600);
  }
  tick();
})();
</script>
"""


def fingerprint(root: Path) -> str:
    h = hashlib.sha1()
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        if p.name.startswith(".") or p.name == "hotserve.py":
            continue
        try:
            st = p.stat()
            h.update(str(p.relative_to(root)).encode())
            h.update(str(st.st_mtime_ns).encode())
            h.update(str(st.st_size).encode())
        except OSError:
            pass
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--root", default=".")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    state = {"fp": fingerprint(root)}

    def watch() -> None:
        while True:
            time.sleep(0.5)
            fp = fingerprint(root)
            if fp != state["fp"]:
                state["fp"] = fp

    threading.Thread(target=watch, daemon=True).start()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *a) -> None:
            pass

        def do_GET(self) -> None:  # noqa: N802
            path = unquote(urlparse(self.path).path)
            if path == "/__hot":
                body = state["fp"].encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if path == "/":
                path = "/import-wf.html"
            rel = path.lstrip("/")
            if ".." in rel.split("/"):
                self.send_error(400)
                return
            file = root / rel
            if not file.is_file():
                self.send_error(404)
                return
            data = file.read_bytes()
            ctype = mimetypes.guess_type(str(file))[0] or "application/octet-stream"
            if file.suffix.lower() in {".html", ".htm"} and b"</body>" in data.lower():
                # inject before </body>
                lower = data.lower()
                i = lower.rfind(b"</body>")
                data = data[:i] + RELOAD_JS + data[i:]
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    httpd = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"hot http://{args.bind}:{args.port}/import-wf.html  (watching {root})", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
