TARGET = iphone:clang:latest:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

# Build the NetworkExtension provider as a real executable, then the workflow
# packages it manually into TouchPOCTunnel.appex. Do not use bundle.mk here:
# bundle.mk can produce a Mach-O bundle/dylib, while app extensions need a
# launchable executable inside the .appex wrapper.
TOOL_NAME = TouchPOCTunnel

TouchPOCTunnel_FILES = PacketTunnelProvider.mm
TouchPOCTunnel_FRAMEWORKS = Foundation NetworkExtension
TouchPOCTunnel_CFLAGS = -fobjc-arc -Wno-error
TouchPOCTunnel_CODESIGN_FLAGS = -Sentitlements.plist
TouchPOCTunnel_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
