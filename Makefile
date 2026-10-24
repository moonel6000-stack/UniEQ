# Rootless par défaut. Autres schémas : make package THEOS_PACKAGE_SCHEME=roothide (ou vide = rootful)
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SysEQ SysEQProbe

SysEQ_FILES = Tweak.xm EQDSP.c EQOverlay.m EQHub.m EQSettingsView.m EQProbeNames.c
SysEQ_CFLAGS = -O2 -Wno-unused-variable -Wno-deprecated-declarations -Wno-unused-function
SysEQ_OBJCFLAGS = -fobjc-arc
SysEQ_FRAMEWORKS = UIKit AudioToolbox AVFoundation Foundation

SysEQProbe_FILES = EQProbe.c EQProbeNames.c
SysEQProbe_CFLAGS = -O2 -Wno-unused-variable

SUBPROJECTS += syseqprefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
