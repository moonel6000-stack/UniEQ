TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SysEQPrefs

SysEQPrefs_FILES = SEQRootListController.m SEQAppsController.m
SysEQPrefs_FRAMEWORKS = UIKit
SysEQPrefs_PRIVATE_FRAMEWORKS = Preferences
SysEQPrefs_INSTALL_PATH = /Library/PreferenceBundles
SysEQPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable

include $(THEOS_MAKE_PATH)/bundle.mk
