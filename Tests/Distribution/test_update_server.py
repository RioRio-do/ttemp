import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/update-test-server.py"
spec = importlib.util.spec_from_file_location("update_test_server", SCRIPT)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class UpdateServerTests(unittest.TestCase):
    def test_loopback_startup_needs_no_dns_and_publishes_ready_port(self):
        with tempfile.TemporaryDirectory() as directory:
            ready = Path(directory) / "port"
            with mock.patch.object(sys, "argv", [str(SCRIPT), directory, str(ready)]), \
                 mock.patch("socket.getfqdn", side_effect=AssertionError("Unexpected DNS lookup")), \
                 mock.patch.object(fixture.ThreadingHTTPServer, "serve_forever") as serve:
                fixture.main()
            serve.assert_called_once_with()
            self.assertTrue(0 < int(ready.read_text(encoding="ascii")) < 65536)
            self.assertFalse(ready.with_suffix(".tmp").exists())


if __name__ == "__main__":
    unittest.main()
