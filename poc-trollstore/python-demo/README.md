# python-demo

Small scripts for driving the TouchPOC app over its TCP wire protocol.

## Wire format

Fixed-width ASCII, one frame per line:

```
"10" + "1" + type(1) + finger(02d) + x*10(05d) + y*10(05d) + "\r\n"
```

- type: 0 = up, 1 = down, 2 = move
- finger: 00..99
- x, y: pixels (multiplied by 10 on the wire to allow one decimal place)

A tap is two frames: a down then an up, typically 80 ms apart.

## Ports

| Port | Server          | Persists when POC force-quit? |
|-----:|-----------------|-------------------------------|
| 6000 | host app        | No                            |
| 6001 | tunnel provider | Yes (on-demand respawns it)   |

## Scripts

- `tap_host.py <ip> [x y]` -- send a single tap via the host (port 6000).
- `tap_provider.py <ip> [x y]` -- send a single tap via the provider (port 6001).
- `tap_auto.py <ip> [x y]` -- try host first, fall back to provider on failure.
- `tap_multi.py <ip> <port> <seq_file>` -- replay a sequence of taps from a text file.

All scripts share `_wire.py` for encoding and connection helpers.

## Default coordinates

The single-tap scripts default to (621, 1104) -- the geometric centre of an
iPhone 6s Plus rendered at 1242x2208 px.
