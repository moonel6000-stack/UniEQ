TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SysEQPrefs

SysEQPrefs_FILES = SEQRootListController.m SEQAppsController.m
SysEQPrefs_FRAMEWORKS = UIKit
# Le SDK Xcode récent n'embarque plus le framework privé Preferences :
# on résout ses symboles au chargement (il est déjà présent dans l'app Réglages).
SysEQPrefs_LDFLAGS = -undefined dynamic_lookup
SysEQPrefs_INSTALL_PATH = /Library/PreferenceBundles
SysEQPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable

include $(THEOS_MAKE_PATH)/bundle.mk
