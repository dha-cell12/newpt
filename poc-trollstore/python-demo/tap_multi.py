"""Send a sequence of taps to stress-test stability and timing.

Reads (x, y, delay_ms) triples from a simple text file, one per line, e.g.:

    621 1104 500
    400 900 300
    800 1500 0

A delay_ms of 0 fires the next tap immediately after the up event of this one.

Usage:
    python tap_multi.py <iphone_ip> <port> <sequence_file>

port is 6000 (host) or 6001 (provider).
"""
import sys
import time
from _wire import connect, tap


def parse_sequence(path):
    out = []
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 3:
                raise ValueError(f"bad line (need 'x y delay_ms'): {line!r}")
            x, y, d = float(parts[0]), float(parts[1]), float(parts[2])
            out.append((x, y, d))
    return out


def main():
    if len(sys.argv) < 4:
        print("usage: python tap_multi.py <iphone_ip> <port> <sequence_file>")
        sys.exit(1)
    host = sys.argv[1]
    port = int(sys.argv[2])
    seq = parse_sequence(sys.argv[3])

    print(f"connecting {host}:{port} -- {len(seq)} taps queued")
    sock = connect(host, port, timeout=3.0)
    try:
        for i, (x, y, delay_ms) in enumerate(seq, 1):
            print(f"  [{i}/{len(seq)}] tap ({x}, {y}) then wait {delay_ms} ms")
            tap(sock, x, y)
            if delay_ms > 0:
                time.sleep(delay_ms / 1000.0)
    finally:
        sock.close()
    print("done")


if __name__ == "__main__":
    main()
