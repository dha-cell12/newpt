Cấu trúc poc-stream đề xuất
File	Vai trò
main.mm	Toàn bộ logic: tạo IOSurface, gọi render, dump PNG, log chẩn đoán
Makefile	Theos TOOL (CLI binary, không phải app/tweak)
entitlements.plist	Nhóm entitlement capture rút gọn (xem dưới)
headers/	Khai báo SPI: CARenderServerRenderDisplay, IOSurface keys nếu cần
README.md	Lệnh build/ký/chạy + tiêu chí pass/fail
Dùng TOOL thay vì app: nhanh hơn để lặp, chạy qua SSH/trollstorehelper, không cần UI. Tham chiếu Screen.xm:164-224 cho cách dựng IOSurface properties đã được kiểm chứng.

Logic main.mm (phác thảo)
Đọc UIScreen bounds × scale để ra width/height pixel (hoặc nhận qua argv để test nhanh).
Dựng IOSurface properties giống Screen.xm:164-177 (IOSurfaceIsGlobal=1, pixelFormat BGRA).
IOSurfaceCreate → IOSurfaceLock.
CARenderServerRenderDisplay(0, CFSTR("LCD"), surface, 0, 0).
UICreateCGImageFromIOSurface → UIImagePNGRepresentation → ghi /tmp/poc_stream_<ts>.png.
IOSurfaceUnlock, release.
Log chẩn đoán mỗi bước: con trỏ surface, errno, kích thước PNG, và quan trọng nhất — kiểm tra ảnh có phải toàn đen không (sample vài pixel giữa khung).
Điểm mấu chốt: phân biệt ba kết quả — (a) ảnh thật, (b) khung đen (render bị chặn nhưng API trả về OK), (c) crash/null (thiếu entitlement/sandbox chặn). Bước 7 tự phân loại để không phải mắt thường đoán.

Entitlements rút gọn để test
Từ phân tích entitlements TrollVNC, nhóm tối thiểu nghi ngờ cần cho capture path. Plan là test phân tầng — bắt đầu tối thiểu, thêm dần nếu đen/fail:

Tầng 1 (tối thiểu, thử trước):

com.apple.QuartzCore.global-capture
com.apple.QuartzCore.secure-capture
com.apple.QuartzCore.secure-mode
com.apple.private.allow-explicit-graphics-priority
com.apple.private.IOSurface.protected-access
platform-application
com.apple.private.security.no-container
Tầng 2 (thêm nếu Tầng 1 ra khung đen):

com.apple.security.iokit-user-client-class với IOSurfaceRootUserClient, IOSurfaceAcceleratorClient, IOMobileFramebufferUserClient, IOAccelContext/IOAccelDevice
Mục đích phân tầng: biết chính xác entitlement nào là bắt buộc cho capture, thay vì bê nguyên ~300 dòng entitlements của TrollVNC mà không hiểu cái nào thực sự cần. Điều này có giá trị trực tiếp cho bước port sau.

Quy trình build/ký/chạy
Build qua Theos (make), target iphone:clang:16.5:14.0 như Makefile pccontrol.
Ký entitlements bằng TrollStore (ldid/codesign với plist Tầng 1).
Đẩy binary lên thiết bị, chạy qua SSH.
Đọc log + kéo PNG về kiểm tra mắt thường (đối chiếu với bước 7 tự động).
Tiêu chí Pass/Fail
PASS: PNG hiển thị nội dung màn hình thật → Hướng 2 khả thi, tiến hành port ScreenCapturer + pipeline.
BLACK: API OK nhưng khung đen → nâng lên entitlements Tầng 2; nếu vẫn đen, secure-mode chặn → cần điều tra thêm (có thể cần chạy ngoài sandbox hoàn toàn / persona khác).
NULL/CRASH: thiếu entitlement nền hoặc sandbox chặn → kiểm tra ký entitlement có ăn không (ldid -e), xác nhận platform-application + no-container đã áp.
Câu hỏi trước khi chốt
Theos TOOL (CLI chạy qua SSH) hay app TrollStore tối thiểu có nút bấm? Tôi nghiêng TOOL — lặp nhanh, ít nhiễu. Nhưng nếu thiết bị test không tiện SSH thì app dễ chạy hơn.
Có sẵn header SPI CARenderServerRenderDisplay để tái dùng từ pccontrol/headers/ không, hay POC tự khai báo extern gọn trong main.mm như Screen.xm:10 đang làm? Tự khai báo đỡ phải kéo cả cây header.
Test trên iOS version nào (entitlement secure-mode hành xử khác giữa iOS 14/15/16/17)? Cho tôi biết phiên bản thiết bị đích để chọn tiêu chí và fallback cho đúng.
Trả lời ba điểm là tôi hoàn thiện plan để bạn duyệt trước khi chuyển sang chế độ thực thi.

binary chạy qua filza được không? tôi không biết cách cài ssh
Chạy qua Filza được, nhưng có một vướng mắc thật cần xử lý — và nó ảnh hưởng đến cách đóng gói POC.

Vấn đề: binary cần entitlements đã ký, không chỉ là file thực thi
Filza chạy được file binary (long-press → "Open with" / có bản Filza cho phép chmod +x rồi execute), nhưng một CLI tool thường khi chạy qua Filza sẽ không mang entitlements — mà entitlements chính là thứ cả POC này cần chứng minh. Một binary chạy "trần" qua Filza dễ bị sandbox như tiến trình con bình thường, làm hỏng chính phép thử.

Để entitlements thực sự có hiệu lực trên thiết bị TrollStore, binary phải được TrollStore ký và đăng ký (nó mới gán được platform-application + nhóm entitlement private). Một file rời chạy qua Filza không qua đường đó.

Hệ quả: nên đóng gói POC thành app TrollStore, không phải CLI tool
Đây là thay đổi so với plan trước (tôi đã nghiêng TOOL/SSH). Với ràng buộc không-SSH của bạn, đường sạch nhất là:

POC = app TrollStore tối thiểu, một nút bấm.

Build thành .app / .tipa, cài qua TrollStore — TrollStore tự ký với entitlements.plist bạn nhúng. Đây là cơ chế chuẩn để entitlements private có hiệu lực.
App chỉ cần một nút "Capture": bấm → gọi CARenderServerRenderDisplay → ghi PNG → hiển thị luôn ảnh trong UIImageView ngay trên màn hình.
Không cần Filza, không cần SSH, không cần kéo file — bạn thấy kết quả pass/fail ngay trong app: ra ảnh màn hình thật, hay khung đen, hay crash.
Điều này thực ra tốt hơn cho cổng quyết định: nó test đúng môi trường mà bản port thật sẽ chạy (binary do TrollStore ký với entitlements), không phải một biến thể chạy-qua-Filza có thể cho kết quả sai lệch.

Cấu trúc poc-stream điều chỉnh
File	Vai trò
main.mm	Entry point app tối thiểu
AppDelegate.mm/.h	Dựng window + view controller
ViewController.mm/.h	1 nút "Capture" + UIImageView + label trạng thái (pass/black/fail)
CaptureCore.mm/.h	Logic capture thuần: IOSurface → render → CGImage (tách riêng để dễ bê sang port thật)
Makefile	Theos APPLICATION thay vì TOOL
entitlements.plist	Nhóm capture Tầng 1, leo Tầng 2 nếu đen
Info.plist	Bundle id, tên hiển thị
README.md	Build → tạo .tipa → cài TrollStore → bấm nút
Tham chiếu sẵn có trong repo: poc-trollstore/AppDelegate.mm + ViewController.mm + Makefile đã là một app TrollStore chạy được — POC này có thể dựa khung đó, chỉ thay nội dung thành capture. CaptureCore dựng IOSurface theo pccontrol/Screen.xm:164-224.

Logic chẩn đoán trong app (giữ nguyên tinh thần plan cũ)
Nút "Capture" chạy tuần tự và hiển thị kết quả ngay:

Dựng IOSurface (IOSurfaceIsGlobal=1, BGRA) — log con trỏ + errno.
CARenderServerRenderDisplay(0, "LCD", surface, 0, 0).
UICreateCGImageFromIOSurface → hiển thị trong UIImageView.
Tự phân loại: sample vài pixel giữa khung → nếu toàn đen/đồng màu → báo "BLACK (secure-mode?)"; nếu có nội dung → "PASS"; nếu null/exception → "FAIL (entitlement/sandbox)".
Ghi kèm PNG ra /tmp hoặc Documents để đối chiếu nếu cần.
Label trạng thái lớn trên màn hình cho bạn kết quả tức thì, không cần đọc log.

Tiêu chí Pass/Fail (không đổi)
PASS: UIImageView hiện màn hình thật → Hướng 2 khả thi.
BLACK: ảnh đen/đồng màu → leo entitlements Tầng 2 (iokit-user-client-class), rebuild, cài lại, bấm lại.
FAIL/CRASH: null hoặc app chết → kiểm tra TrollStore đã áp entitlements chưa, xác nhận platform-application + no-container.
Câu hỏi để chốt plan
Đồng ý chuyển POC từ CLI sang app TrollStore một nút? Đây là điều kiện để entitlements có hiệu lực mà không cần SSH/Filza-execute. Tôi khuyến nghị mạnh hướng này.
Có cần fallback chạy-qua-Filza không? Tôi nghĩ không — app TrollStore vừa dễ hơn vừa test đúng môi trường. Nhưng nếu bạn vẫn muốn một biến thể CLI để thử song song, tôi thêm vào plan.
iOS version thiết bị đích? Quyết định tiêu chí secure-mode và thứ tự leo entitlements (hành vi khác nhau rõ giữa iOS 15/16/17+).
Trả lời là tôi hoàn thiện plan cuối để bạn duyệt trước khi chuyển sang thực thi.

đồng ý chuyển POC từ CLI sang app TrollStore một nút IOS 15.8.8 triển khai cho tôi.
