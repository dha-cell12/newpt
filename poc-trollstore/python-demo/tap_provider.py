"""Tap via the provider-side TCP server on port 6001.

The provider extension keeps running after the host app is force-quit (when
on-demand VPN is enabled), so this path stays available where tap_host.py
fails.

Usage:
    python tap_provider.py <iphone_ip> [x_px y_px]
"""
import sys
from _wire import connect, tap, DEFAULT_PROVIDER_PORT


def main():
    if len(sys.argv) < 2:
        print("usage: python tap_provider.py <iphone_ip> [x_px y_px]")
        sys.exit(1)
    host = sys.argv[1]
    x = float(sys.argv[2]) if len(sys.argv) > 2 else 621.0
    y = float(sys.argv[3]) if len(sys.argv) > 3 else 1104.0

    print(f"connecting {host}:{DEFAULT_PROVIDER_PORT} ...")
    sock = connect(host, DEFAULT_PROVIDER_PORT, timeout=3.0)
    print(f"tap at ({x}, {y})")
    tap(sock, x, y)
    sock.close()
    print("done")


if __name__ == "__main__":
    main()
