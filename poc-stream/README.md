# StreamPOC

POC này chuyển `poc-stream/plan.md` từ CLI tool sang app TrollStore một nút cho thiết bị iOS 15.8.8.

## Mục tiêu

Bấm **Capture** trong app để kiểm tra đường:

`IOSurfaceCreate -> CARenderServerRenderDisplay("LCD") -> UICreateCGImageFromIOSurface -> UIImage/PNG`

App tự phân loại kết quả:

- `PASS`: ảnh có nội dung thật, hướng capture khả thi.
- `BLACK`: API trả ảnh nhưng ảnh đen hoặc đồng màu, cần leo entitlement hoặc context chạy khác.
- `FAIL`: surface/image null, thường là signing/entitlement/sandbox hoặc symbol SPI không có.

## Build local

```bash
cd poc-stream
make clean || true
make stage FINALPACKAGE=1
```

Sau `stage`, hook `after-stage` sẽ cố gắng tạo:

```text
poc-stream/packages/StreamPOC.tipa
```

## Build GitHub Actions

Workflow riêng:

```text
.github/workflows/poc-stream.yml
```

Artifact xuất ra tên `StreamPOC-tipa`.

## Cài và test

1. Cài `StreamPOC.tipa` qua TrollStore.
2. Mở app `StreamPOC`.
3. Bấm **Capture**.
4. Đọc status trên màn hình và xem ảnh trong `UIImageView`.
5. Xem diagnostics bên dưới để biết bước nào fail.

PNG best-effort được ghi vào temporary directory của app với tên:

```text
poc_stream_capture.png
```

## Cấu trúc

- `main.mm`: entry point app.
- `AppDelegate.*`: dựng window + navigation controller.
- `ViewController.*`: UI một nút, image preview, diagnostics.
- `CaptureCore.*`: logic capture thuần để sau này bê sang pipeline thật.
- `Makefile`: Theos `APPLICATION`, cách đóng gói `.tipa` dựa theo `poc-trollstore`.
- `entitlements.plist`: entitlement Tier 1 cho thử nghiệm capture.

## Ghi chú build

`CaptureCore.mm` hiện khai báo SPI trực tiếp như `pccontrol/Screen.xm`. Nếu GitHub Actions lỗi linker vì SDK không expose symbol private, bước tiếp theo nên đổi các symbol capture sang `dlopen/dlsym` để tránh phụ thuộc `.tbd`.
