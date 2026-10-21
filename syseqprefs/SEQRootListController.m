#import <Preferences/PSListController.h>
#include <notify.h>

@interface SEQRootListController : PSListController
@end

@implementation SEQRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)resetApps {
    CFStringRef dom = CFSTR("com.example.syseq");
    CFArrayRef keys = CFPreferencesCopyKeyList(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys) {
        for (NSString *k in (__bridge NSArray *)keys) {
            if ([k hasPrefix:@"app."]) CFPreferencesSetAppValue((__bridge CFStringRef)k, NULL, dom);
        }
        CFRelease(keys);
    }
    CFPreferencesAppSynchronize(dom);
    notify_post("com.example.syseq/prefschanged");
}

@end
