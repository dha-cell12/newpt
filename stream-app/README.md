# stream-app

Khung chuẩn hợp nhất **click + stream** cho Tlinkauto trên TrollStore (iOS 15.8.8).

## Kiến trúc

```
[App TrollStore: StreamControl]  ← UI (mở 1 lần sau reboot)
   └─ StreamSupervisor: spawn + watchdog (KHÔNG root)
        └─ [streamd]  ← daemon hợp nhất
             ├─ click/    HID injection (task 10, cổng 6000)
             ├─ stream/   capture + H.264 (cổng 7001-7006)
             └─ transport/ socket servers (tách cổng)
```

Root helper (`privhelper/`) để dành cho clear keychain / app data — thêm sau,
spawn qua `spawnRoot` + `persona-mgmt`, KHÔNG ảnh hưởng `streamd`.

## Phạm vi đợt khung chuẩn

- Click (task 10) + stream (capture→H264→client) chạy được.
- UI đồng bộ phong cách Tlinkauto ở mức bố cục (navigation + light mode).
- Self-test tap trong UI.
- CHƯA tối ưu latency (pipelining/low-latency rate control để đợt sau).
- CHƯA đồng bộ phần quản lý/play script.

## Thành phần và nguồn

| Thành phần | Nguồn |
|-----------|-------|
| click/TouchInjector, HIDInjectCore, WireProtocolParser | `poc-trollstore` (đã pass) |
| stream/CaptureCore | `poc-stream` (đã pass entitlement capture) |
| stream/H264Stream | `pccontrol/H264Stream.xm` |
| transport/SocketServer | `poc-trollstore/POCSocketServer.mm` + tách cổng stream |

## Cổng

| Cổng | Dùng cho |
|------|----------|
| 6000 | Click (task 10, wire-protocol legacy) |
| 7001-7006 | Stream H.264 (6 profile, giữ tương thích client PC) |

## Build

```
make            # build cả app (.tipa) lẫn streamd
```

`streamd` được đóng gói vào bundle app (`StreamControl.app/streamd`) để app
spawn bằng đường dẫn tương đối.

## Entitlements

`streamd/entitlements.plist` HỢP NHẤT hai nhóm đã chứng minh riêng rẽ:
- Nhóm HID (click): `com.apple.private.hid.client.event-dispatch` + IOKit HID user-clients.
- Nhóm capture (stream): `com.apple.QuartzCore.global-capture`, IOSurface, v.v.

Bước 1 kiểm chứng ký hợp nhất trước khi bê toàn bộ code.
