# Rootless par défaut. Autres schémas : make package THEOS_PACKAGE_SCHEME=roothide (ou vide = rootful)
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SysEQ

SysEQ_FILES = Tweak.xm EQDSP.c EQOverlay.m
SysEQ_CFLAGS = -O2 -Wno-unused-variable -Wno-deprecated-declarations -Wno-unused-function
SysEQ_OBJCFLAGS = -fobjc-arc
SysEQ_FRAMEWORKS = UIKit AudioToolbox Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
