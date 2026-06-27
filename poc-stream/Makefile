# POC TrollStore screen-capture app.
#
# Builds a standalone iOS application (NOT a tweak), packaged for TrollStore.
# Target test device: iOS 15.8.8 arm64.

TARGET = iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = StreamPOC

StreamPOC_FILES = main.mm AppDelegate.mm ViewController.mm CaptureCore.mm
StreamPOC_RESOURCE_FILES = Info.plist
StreamPOC_FRAMEWORKS = UIKit CoreFoundation CoreGraphics QuartzCore IOSurface Security
StreamPOC_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -Wno-deprecated-declarations
StreamPOC_CCFLAGS = -std=c++14
StreamPOC_CODESIGN_FLAGS = -Sentitlements.plist
StreamPOC_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	-@echo "[after-stage] attempting local .tipa packaging (best-effort)..."
	-@APP=$$(find $(THEOS_STAGING_DIR) -maxdepth 3 -name 'StreamPOC.app' -type d | head -n1); \
	  if [ -n "$$APP" ]; then \
	    test -f "$$APP/Info.plist" || cp $(THEOS_PROJECT_DIR)/Info.plist "$$APP/Info.plist"; \
	    test -f "$$APP/Info.plist" || { echo "[after-stage] ERROR: $$APP/Info.plist missing"; exit 1; }; \
	    rm -rf $(THEOS_STAGING_DIR)/Payload && mkdir -p $(THEOS_STAGING_DIR)/Payload && \
	    cp -R "$$APP" $(THEOS_STAGING_DIR)/Payload/StreamPOC.app && \
	    test -f "$(THEOS_STAGING_DIR)/Payload/StreamPOC.app/Info.plist" || { echo "[after-stage] ERROR: Payload/StreamPOC.app/Info.plist missing"; exit 1; }; \
	    mkdir -p $(THEOS_PROJECT_DIR)/packages && \
	    rm -f $(THEOS_PROJECT_DIR)/packages/StreamPOC.tipa && \
	    ( cd $(THEOS_STAGING_DIR) && zip -qr9 $(THEOS_PROJECT_DIR)/packages/StreamPOC.tipa Payload ) && \
	    unzip -l $(THEOS_PROJECT_DIR)/packages/StreamPOC.tipa | grep -q 'Payload/StreamPOC.app/Info.plist' && \
	    echo "[after-stage] wrote packages/StreamPOC.tipa"; \
	  else \
	    echo "[after-stage] StreamPOC.app not found; skipping (CI will package instead)"; \
	  fi
