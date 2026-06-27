"""Tap with automatic host -> provider fallback.

Tries the host TCP server on port 6000 first (lowest latency). If that
connection is refused or times out, falls back to the provider's TCP server
on port 6001. Prints which path was used.

Usage:
    python tap_auto.py <iphone_ip> [x_px y_px]
"""
import socket
import sys
from _wire import connect, tap, DEFAULT_HOST_PORT, DEFAULT_PROVIDER_PORT


def try_connect(host: str, port: int, timeout: float):
    try:
        return connect(host, port, timeout=timeout)
    except (OSError, socket.timeout) as exc:
        print(f"  {host}:{port} failed: {exc.__class__.__name__}: {exc}")
        return None


def main():
    if len(sys.argv) < 2:
        print("usage: python tap_auto.py <iphone_ip> [x_px y_px]")
        sys.exit(1)
    host = sys.argv[1]
    x = float(sys.argv[2]) if len(sys.argv) > 2 else 621.0
    y = float(sys.argv[3]) if len(sys.argv) > 3 else 1104.0

    print("trying host path (port 6000) ...")
    sock = try_connect(host, DEFAULT_HOST_PORT, timeout=1.0)
    path = "host"
    if sock is None:
        print("falling back to provider path (port 6001) ...")
        sock = try_connect(host, DEFAULT_PROVIDER_PORT, timeout=2.0)
        path = "provider"
    if sock is None:
        print("both paths unreachable")
        sys.exit(2)

    print(f"using path={path} tap at ({x}, {y})")
    tap(sock, x, y)
    sock.close()
    print("done")


if __name__ == "__main__":
    main()
