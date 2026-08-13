#!/usr/bin/env python3
"""Serve geo-viewer assets with browser-safe JavaScript MIME types."""

from __future__ import annotations

import argparse
import http.server
import json
import mimetypes
import sys
from functools import partial
from pathlib import Path
from urllib.parse import urlsplit


def load_env_value(path: Path | None, name: str) -> str | None:
    """Read one dotenv value without adding a runtime dependency."""
    if path is None or not path.is_file():
        return None
    for raw_line in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        key, separator, value = line.partition("=")
        if not separator or key.strip() != name:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        return value or None
    return None


class DevelopmentRequestHandler(http.server.SimpleHTTPRequestHandler):
    """Static handler that prevents stale module/MIME responses during local tests."""

    def __init__(self, *args, env_file: Path | None = None, **kwargs) -> None:
        self.env_file = env_file
        super().__init__(*args, **kwargs)

    def do_GET(self) -> None:
        path = urlsplit(self.path).path
        if path == "/__runtime/mapray-config":
            self._serve_mapray_config()
            return
        if path == "/favicon.ico":
            self.send_response(http.HTTPStatus.NO_CONTENT)
            self.end_headers()
            return
        super().do_GET()

    def log_message(self, format: str, *args: object) -> None:
        """Keep pythonw background serving from failing when stderr is unavailable."""
        if sys.stderr is not None:
            super().log_message(format, *args)

    def _serve_mapray_config(self) -> None:
        api_key = load_env_value(self.env_file, "MAPRAY_API_KEY")
        if not api_key:
            body = b'{"error":"MAPRAY_API_KEY is not configured"}'
            status = http.HTTPStatus.NOT_FOUND
        else:
            body = json.dumps({"apiKey": api_key}).encode("utf-8")
            status = http.HTTPStatus.OK
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", default=8001, type=int)
    parser.add_argument("--env-file", type=Path)
    args = parser.parse_args()

    root = args.directory.resolve()
    if not root.is_dir():
        parser.error(f"directory does not exist: {root}")

    mimetypes.add_type("application/javascript", ".js")
    mimetypes.add_type("application/javascript", ".mjs")
    env_file = args.env_file.resolve() if args.env_file else None
    handler = partial(
        DevelopmentRequestHandler,
        directory=str(root),
        env_file=env_file,
    )
    server = http.server.ThreadingHTTPServer((args.bind, args.port), handler)
    if sys.stdout is not None:
        print(f"Serving {root} at http://{args.bind}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
