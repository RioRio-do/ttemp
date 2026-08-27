#!/usr/bin/env python3
"""Serve only the isolated update fixture, with a machine-readable ready signal."""

from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys


def main():
    directory, ready_path = sys.argv[1:]
    ready = Path(ready_path)
    handler = partial(SimpleHTTPRequestHandler, directory=directory)
    with ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
        pending = ready.with_suffix(".tmp")
        pending.write_text(f"{server.server_port}\n", encoding="ascii")
        pending.replace(ready)
        server.serve_forever()


if __name__ == "__main__":
    main()
