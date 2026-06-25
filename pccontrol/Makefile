#export THEOS_DEVICE_IP = 192.168.0.6

include $(THEOS)/makefiles/common.mk

TLINKAUTO_TOUCH_FILE_LOG ?= 0

TWEAK_NAME = pccontrol

pccontrol_FILES = Tweak.xm SocketResponder.xm IPCMessagePort.xm Touch.xm Screen.xm Task.xm Process.xm Connectivity.xm AlertBox.xm Common.xm Record.xm Play.xm Window.xm Popup.xm TemplateMatch.xm ScreenMatch.xm Toast.xm Image.xm TesseractOCRTask.mm ColorPicker.xm UIKeyboard.xm DeviceInfo.xm HardwareKey.xm Scheduler.xm RuntimeUtils.xm H264Stream.xm jsruntime/TLinkJSNativeRequest.mm jsruntime/TLinkJSNativeResponse.mm jsruntime/TLinkInProcessNativeBridge.mm jsruntime/TLinkJSRuntimeCore.mm jsruntime/TLinkJSHelperProtocol.mm TLinkautoJSRuntime.mm TouchIndicator/TouchIndicatorWindow.xm TouchIndicator/TouchIndicatorView.xm TouchIndicator/TouchIndicatorCoordinateView.xm TouchIndicator/TouchIndicatorViewList.xm ScriptPlayer.xm Activator/ActivatorListener.xm TextRecognization/VKOcrManager.xm TextRecognization/TextRecognizer.xm UpdateCache.xm TLinkTaskContext.mm ../third_party/TesseractOCR/TesseractOCR/G8Tesseract.mm ../third_party/TesseractOCR/TesseractOCR/G8PixWrapper.mm ../third_party/TesseractOCR/TesseractOCR/G8TextMonitor.mm ../third_party/TesseractOCR/TesseractOCR/G8RecognizedBlock.m ../third_party/TesseractOCR/TesseractOCR/G8HierarchicalRecognizedBlock.m ../third_party/TesseractOCR/TesseractOCR/G8TesseractParameters.m ../third_party/TesseractOCR/TesseractOCR/UIImage+G8Filters.m
pccontrol_CFLAGS = -Wno-error -Wno-module-import-in-extern-c -fobjc-arc -DENABLE_TESSERACT_OCR=1 -DTLINKAUTO_TOUCH_FILE_LOG=$(TLINKAUTO_TOUCH_FILE_LOG)
pccontrol_FRAMEWORKS = UIKit AssetsLibrary AVFoundation CoreMedia CoreVideo IOSurface Photos VideoToolbox JavaScriptCore
pccontrol_ARCHS = arm64
pccontrol_CCFLAGS = -std=c++14

pccontrol_CFLAGS += -F$(THEOS_PROJECT_DIR)/frameworks
pccontrol_LDFLAGS += -F$(THEOS_PROJECT_DIR)/frameworks
pccontrol_CFLAGS += -I$(THEOS_PROJECT_DIR)/frameworks/opencv2.framework/Versions/A/Headers
pccontrol_CCFLAGS += -I$(THEOS_PROJECT_DIR)/frameworks/opencv2.framework/Versions/A/Headers
pccontrol_CFLAGS += -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/Tesseract.xcframework/ios-arm64/Headers -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/Leptonica.xcframework/ios-arm64/Headers -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/JPEG.xcframework/ios-arm64/Headers -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/PNG.xcframework/ios-arm64/Headers -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/TIFF.xcframework/ios-arm64/Headers
pccontrol_CCFLAGS += -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/Tesseract.xcframework/ios-arm64/Headers -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/Leptonica.xcframework/ios-arm64/Headers -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/JPEG.xcframework/ios-arm64/Headers -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/PNG.xcframework/ios-arm64/Headers -I$(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/TIFF.xcframework/ios-arm64/Headers
pccontrol_LDFLAGS += $(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/Tesseract.xcframework/ios-arm64/libtesseract.a $(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/Leptonica.xcframework/ios-arm64/libleptonica.a $(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/PNG.xcframework/ios-arm64/libpng16.a $(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/JPEG.xcframework/ios-arm64/libjpeg.a $(THEOS_PROJECT_DIR)/third_party/TesseractOCR/TesseractOCR/xcframework/TIFF.xcframework/ios-arm64/libtiff.a -lz -lc++

pccontrol_PRIVATE_FRAMEWORKS = IOKit MobileCoreServices
pccontrol_EXTRA_FRAMEWORKS = opencv2
pccontrol_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "chown -R mobile:mobile /var/mobile/Library/TLinkauto && killall -9 SpringBoard;"
