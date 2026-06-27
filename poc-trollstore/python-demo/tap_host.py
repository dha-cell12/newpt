"""Tap via the host-side TCP server on port 6000.

Works while the POC app is foreground or background (not force-quit).
This matches the user's original working script and serves as the baseline.

Usage:
    python tap_host.py <iphone_ip> [x_px y_px]
"""
import sys
from _wire import connect, tap, DEFAULT_HOST_PORT


def main():
    if len(sys.argv) < 2:
        print("usage: python tap_host.py <iphone_ip> [x_px y_px]")
        sys.exit(1)
    host = sys.argv[1]
    x = float(sys.argv[2]) if len(sys.argv) > 2 else 621.0
    y = float(sys.argv[3]) if len(sys.argv) > 3 else 1104.0

    print(f"connecting {host}:{DEFAULT_HOST_PORT} ...")
    sock = connect(host, DEFAULT_HOST_PORT, timeout=3.0)
    print(f"tap at ({x}, {y})")
    tap(sock, x, y)
    sock.close()
    print("done")


if __name__ == "__main__":
    main()
