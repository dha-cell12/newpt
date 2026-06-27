"""Shared helpers for the TouchPOC fixed-width wire protocol.

Frame layout per touch (after leading "10" + count):
    [type:1][index:2][x:5][y:5]\r\n

x and y on the wire are pixels * 10, zero-padded to 5 digits.
"""
import socket
import time

DEFAULT_HOST_PORT = 6000
DEFAULT_PROVIDER_PORT = 6001


def encode_touch(typ: int, finger: int, x: float, y: float) -> bytes:
    """Encode a single touch packet (one finger, one phase).

    typ: 0 = up, 1 = down, 2 = move
    finger: finger index 0..
    x, y: pixel coordinates (will be multiplied by 10 and rounded).
    """
    return (
        "10"
        "1"
        f"{typ:d}"
        f"{finger:02d}"
        f"{int(round(x * 10)):05d}"
        f"{int(round(y * 10)):05d}"
        "\r\n"
    ).encode()


def tap(sock: socket.socket, x: float, y: float,
        finger: int = 1, hold_seconds: float = 0.08) -> None:
    """Send a down/up pair representing a tap at (x, y)."""
    sock.sendall(encode_touch(1, finger, x, y))
    time.sleep(hold_seconds)
    sock.sendall(encode_touch(0, finger, x, y))


def connect(host: str, port: int, timeout: float = 2.0) -> socket.socket:
    return socket.create_connection((host, port), timeout=timeout)
