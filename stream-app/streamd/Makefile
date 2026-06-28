# streamd - unified click + stream daemon (NON-root).
#
# Phase 3: click/touch + capture probe + video stream paths are compiled into streamd.
# Ports 7001-7006 are opened by H264Stream.mm.

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = streamd

streamd_FILES = main.mm TouchInjector.mm POCSocketServer.mm HIDInjectCore.mm WireProtocolParser.mm CaptureCore.mm StreamCaptureProbe.mm StreamCaptureSource.mm H264Stream.mm
streamd_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics QuartzCore IOSurface Security VideoToolbox CoreVideo CoreMedia
streamd_PRIVATE_FRAMEWORKS = IOKit
streamd_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -Iheaders
streamd_CCFLAGS = -std=c++14
streamd_CODESIGN_FLAGS = -Sentitlements.plist
streamd_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk



