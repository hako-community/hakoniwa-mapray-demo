from __future__ import annotations

import http.server
import json
import tempfile
import threading
import unittest
import urllib.request
from functools import partial
from pathlib import Path

from serve_geo_viewer import DevelopmentRequestHandler, load_env_value


class RuntimeMaprayConfigTest(unittest.TestCase):
    def test_load_env_value(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / ".env"
            env_file.write_text(
                "# local secret\nexport MAPRAY_API_KEY='test-key'\n",
                encoding="utf-8",
            )
            self.assertEqual(load_env_value(env_file, "MAPRAY_API_KEY"), "test-key")
            self.assertIsNone(load_env_value(env_file, "MISSING"))

    def test_runtime_endpoint_is_no_store(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env_file = root / ".env"
            env_file.write_text("MAPRAY_API_KEY=test-key\n", encoding="utf-8")
            handler = partial(
                DevelopmentRequestHandler,
                directory=str(root),
                env_file=env_file,
            )
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                url = f"http://127.0.0.1:{server.server_port}/__runtime/mapray-config"
                with urllib.request.urlopen(url, timeout=5) as response:
                    body = json.load(response)
                    self.assertEqual(body, {"apiKey": "test-key"})
                    self.assertIn("no-store", response.headers["Cache-Control"])
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
