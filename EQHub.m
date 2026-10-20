#import <UIKit/UIKit.h>
#include <notify.h>
#include "EQShared.h"

extern int proc_name(int pid, void *buffer, uint32_t buffersize);

static int gTokState = -1;
static int gTokActive = -1;
static NSMutableDictionary<NSString *, NSNumber *> *gAppTokens;
static NSMutableSet<NSString *> *gPublished;

static int tokenFor(NSString *name) {
    NSNumber *n = gAppTokens[name];
    if (n) return n.intValue;
    int t = -1;
    if (notify_register_check(name.UTF8String, &t) != NOTIFY_STATUS_OK) return -1;
    gAppTokens[name] = @(t);
    return t;
}

static void setApp(NSString *name, uint64_t v) {
    int t = tokenFor(name);
    if (t < 0) return;
    notify_set_state(t, v);
    notify_post(name.UTF8String);
}

@implementation SEQHub

+ (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gAppTokens = [NSMutableDictionary dictionary];
        gPublished = [NSMutableSet set];
        notify_register_check(SEQ_STATE_NOTIFY, &gTokState);
        int t1, t2;
        notify_register_dispatch(SEQ_PREFS_NOTIFY, &t1, dispatch_get_main_queue(), ^(int x) { [SEQHub publish]; });
        notify_register_dispatch(SEQ_ACTIVE_NOTIFY, &gTokActive, dispatch_get_main_queue(), ^(int x) { [SEQHub activity]; });
        (void)t2;
        [SEQHub publish];
    });
}

+ (void)publish {
    SEQSettings s;
    SEQLoadSettings(&s);

    int mode = 0;
    CFPropertyListRef m = CFPreferencesCopyAppValue(CFSTR("mode"), SEQ_PREFS_DOMAIN);
    if (m) { if (CFGetTypeID(m) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)m, kCFNumberIntType, &mode); CFRelease(m); }

    BOOL show = YES;
    CFPropertyListRef sh = CFPreferencesCopyAppValue(CFSTR("showOverlay"), SEQ_PREFS_DOMAIN);
    if (sh) { if (CFGetTypeID(sh) == CFBooleanGetTypeID()) show = CFBooleanGetValue((CFBooleanRef)sh); CFRelease(sh); }

    uint64_t st = SEQPack(&s) | (mode ? 2ull : 0ull);
    if (gTokState >= 0) notify_set_state(gTokState, st);
    notify_post(SEQ_STATE_NOTIFY);

    /* liste des apps cochées */
    NSMutableSet<NSString *> *now = [NSMutableSet set];
    CFArrayRef keys = CFPreferencesCopyKeyList(SEQ_PREFS_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys) {
        for (NSString *k in (__bridge NSArray *)keys) {
            if (![k hasPrefix:@"app."]) continue;
            CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)k, SEQ_PREFS_DOMAIN);
            BOOL on = (v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)v));
            if (v) CFRelease(v);
            if (on) [now addObject:[NSString stringWithFormat:@"%s%@", SEQ_APP_PREFIX, [k substringFromIndex:4]]];
        }
        CFRelease(keys);
    }
    for (NSString *n in now) setApp(n, 1);
    for (NSString *n in [gPublished copy]) if (![now containsObject:n]) setApp(n, 0);
    [gPublished setSet:now];

    [SEQOverlay setVisible:show];
}

+ (void)activity {
    uint64_t pid = 0;
    if (gTokActive >= 0) notify_get_state(gTokActive, &pid);
    char buf[64] = {0};
    proc_name((int)pid, buf, sizeof(buf));
    [SEQOverlay setStatus:[NSString stringWithFormat:@"Actif : %s", buf]];
}

@end
