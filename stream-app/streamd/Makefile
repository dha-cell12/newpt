# streamd - unified click + stream daemon (NON-root).
#
# Phase 2: click/touch + capture probe paths are compiled into streamd.
# Later phases will add continuous H.264 streaming.

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = streamd

streamd_FILES = main.mm TouchInjector.mm POCSocketServer.mm HIDInjectCore.mm WireProtocolParser.mm CaptureCore.mm StreamCaptureProbe.mm
streamd_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics QuartzCore IOSurface Security
streamd_PRIVATE_FRAMEWORKS = IOKit
streamd_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -Iheaders
streamd_CCFLAGS = -std=c++14
streamd_CODESIGN_FLAGS = -Sentitlements.plist
streamd_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk



