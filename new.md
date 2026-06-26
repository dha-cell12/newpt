Đã triển khai tiếp Phase 0.

Đã làm

TLinkJSRuntimeCore không còn import/cast trực tiếp TLinkautoJSRuntime.
TLinkautoDeviceBridge.runtime đổi sang id, giảm coupling với façade concrete.
TLinkInProcessNativeBridge có host được inject từ TLinkautoJSRuntime, không dùng TLinkTaskExecutionContext.runtime.
Xóa runtime pointer khỏi TLinkTaskExecutionContext và TLinkScriptSession.
Di chuyển raw processTask(...) execution vào TLinkInProcessNativeBridge.
TLinkautoJSRuntime không còn import Task.h, không còn gọi processTask, không còn expose taskResultForPayload.
Các direct runTask còn lại giờ route qua bridge bằng TLinkJSNativeMethodRawTask.
Thêm stable native method constants trong TLinkJSNativeRequest.
Thay raw executeNativeRequest:@"..." bằng constants.
Mở rộng TLinkJSHelperProtocol:
envelope key constants
command/state allowlist
protocol version compatibility check
JSON-compatible payload validation
basic stateChanged validation
basic nativeRPCRequest validation
Xóa toàn bộ PHASE0_BRIDGE_TODO markers.
Boundary Check

TLinkJSRuntimeCore.mm: không còn Task.h, processTask, taskResultForPayload, hoặc import façade concrete.
TLinkautoJSRuntime.mm: không còn Task.h, processTask, hoặc taskResultForPayload.
processTask hiện chỉ còn trong TLinkInProcessNativeBridge, đúng vai trò in-process adapter.
Verification

Đã chạy git diff --check.
Không có whitespace error, chỉ có cảnh báo LF/CRLF của Git trên Windows.

Khuyến nghị Sửa tiếp Phase 0 theo từng nhóm nhỏ, build/test sau mỗi nhóm:

Frame/Image/OCR group
framePickColor
framePickColors
frameFindColor
frameIsColors
frameFindMultiColor
findImageInFrame
ocrLanguages
ocrFrame
ocr
App/Device/Connectivity group
openApp, killApp, appState, appInfo, appPid
frontMostAppId, frontMostPid, orientation
appPaths, listBundles, openUrl
wifi/bluetooth/airplane/cellular
info, batteryInfo
UI/Input/Scheduler group
alert/dialog/clearDialog
keyboard/clipboard/text input
hardwareKey/pressHardwareKey
keepAwake/touchIndicator
rootDir/currentDir/botPath
saveScreenshotToAlbum/clearScreenshotAlbum
setAutoLaunch/listAutoLaunch/setTimer/removeTimer
Touch/screen leftovers
longPress
gesture
pickColor
screenshotRegion
batch
releaseAllFrames
Phase 0 Done Definition

Public typed JS APIs create stable TLinkJSNativeRequest.
TLinkInProcessNativeBridge handles each stable method.
rawTask remains only for device.runTask internal/debug.
TLinkautoJSRuntime.mm has no return [self runTask: in public typed APIs except runTask itself.
