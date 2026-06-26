TARGET = iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = TouchPOCTunnel

TouchPOCTunnel_FILES = PacketTunnelProvider.mm
TouchPOCTunnel_FRAMEWORKS = Foundation NetworkExtension
TouchPOCTunnel_CFLAGS = -fobjc-arc -Wno-error
TouchPOCTunnel_CODESIGN_FLAGS = -Sentitlements.plist
TouchPOCTunnel_INSTALL_PATH = /Applications/TouchPOC.app/PlugIns

TouchPOCTunnel_BUNDLE_EXTENSION = appex
BUNDLE_EXTENSION = appex

include $(THEOS_MAKE_PATH)/bundle.mk