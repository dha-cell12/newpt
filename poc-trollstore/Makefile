# POC TrollStore touch-injection app.
#
# Builds a standalone iOS application (NOT a tweak), packaged for TrollStore.
# Target iOS 15-16, arm64. No Substrate, no daemon, no SpringBoard injection.

TARGET = iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TouchPOC

TouchPOC_FILES = main.mm AppDelegate.mm ViewController.mm TouchInjector.mm POCSocketServer.mm NEManager.mm HIDInjectCore.mm WireProtocolParser.mm
# Keep Info.plist inside TouchPOC.app root. TrollStore requires
# Payload/TouchPOC.app/Info.plist in the final .tipa.
TouchPOC_RESOURCE_FILES = Info.plist
TouchPOC_FRAMEWORKS = UIKit CoreFoundation CoreGraphics AVFoundation NetworkExtension
TouchPOC_PRIVATE_FRAMEWORKS = IOKit
TouchPOC_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c
TouchPOC_CCFLAGS = -std=c++14
TouchPOC_CODESIGN_FLAGS = -Sentitlements.plist
TouchPOC_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk

# Local convenience: after staging, also emit a TrollStore-installable .tipa by
# wrapping the signed .app in a Payload/ directory. This is best-effort for
# local builds; CI packages the .tipa independently and does not rely on this
# hook. The leading '-' on each command keeps a hook failure from aborting the
# overall build.
after-stage::
	-@echo "[after-stage] attempting local .tipa packaging (best-effort)..."
	-@APP=$$(find $(THEOS_STAGING_DIR) -maxdepth 3 -name 'TouchPOC.app' -type d | head -n1); \
	  if [ -n "$$APP" ]; then \
	    test -f "$$APP/Info.plist" || cp $(THEOS_PROJECT_DIR)/Info.plist "$$APP/Info.plist"; \
	    test -f "$$APP/Info.plist" || { echo "[after-stage] ERROR: $$APP/Info.plist missing"; exit 1; }; \
	    rm -rf $(THEOS_STAGING_DIR)/Payload && mkdir -p $(THEOS_STAGING_DIR)/Payload && \
	    cp -R "$$APP" $(THEOS_STAGING_DIR)/Payload/TouchPOC.app && \
	    test -f "$(THEOS_STAGING_DIR)/Payload/TouchPOC.app/Info.plist" || { echo "[after-stage] ERROR: Payload/TouchPOC.app/Info.plist missing"; exit 1; }; \
	    mkdir -p $(THEOS_PROJECT_DIR)/packages && \
	    rm -f $(THEOS_PROJECT_DIR)/packages/TouchPOC.tipa && \
	    ( cd $(THEOS_STAGING_DIR) && zip -qr9 $(THEOS_PROJECT_DIR)/packages/TouchPOC.tipa Payload ) && \
	    unzip -l $(THEOS_PROJECT_DIR)/packages/TouchPOC.tipa | grep -q 'Payload/TouchPOC.app/Info.plist' && \
	    echo "[after-stage] wrote packages/TouchPOC.tipa"; \
	  else \
	    echo "[after-stage] TouchPOC.app not found; skipping (CI will package instead)"; \
	  fi
