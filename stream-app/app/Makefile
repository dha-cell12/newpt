# StreamControl - TrollStore app: UI + supervisor that spawns streamd.
#
# Builds a standalone iOS application (NOT a tweak), packaged for TrollStore.
# The streamd binary is bundled inside StreamControl.app so the supervisor can
# spawn it by relative path.

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = StreamControl

StreamControl_FILES = main.mm AppDelegate.mm ViewController.mm StreamSupervisor.mm
StreamControl_RESOURCE_FILES = Info.plist
StreamControl_FRAMEWORKS = UIKit CoreFoundation CoreGraphics
StreamControl_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c
StreamControl_CCFLAGS = -std=c++14
StreamControl_CODESIGN_FLAGS = -Sentitlements.plist
StreamControl_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
