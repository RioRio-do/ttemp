#!/usr/bin/env python3
"""Serve only the isolated update fixture, with a machine-readable ready signal."""

from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socketserver import TCPServer
import sys


class LoopbackServer(ThreadingHTTPServer):
    def server_bind(self):
        # HTTPServer normally calls getfqdn here. No reverse DNS is needed for
        # an IPv4 loopback fixture, and a CI resolver must not block readiness.
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address


def main():
    directory, ready_path = sys.argv[1:]
    ready = Path(ready_path)
    handler = partial(SimpleHTTPRequestHandler, directory=directory)
    with LoopbackServer(("127.0.0.1", 0), handler) as server:
        pending = ready.with_suffix(".tmp")
        pending.write_text(f"{server.server_port}\n", encoding="ascii")
        pending.replace(ready)
        server.serve_forever()


if __name__ == "__main__":
    main()
