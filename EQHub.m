#import <UIKit/UIKit.h>
#include <notify.h>
#include "EQShared.h"
#import "EQSettingsView.h"

static int gTokState = -1;
static int gTokActive = -1;
static NSMutableDictionary<NSString *, NSNumber *> *gAppTokens;
static NSMutableSet<NSString *> *gPublished;
static NSDictionary<NSNumber *, NSDictionary *> *gHashMap;
static NSDate *gHashMapDate;
static NSMutableDictionary<NSString *, NSDictionary *> *gActive;
static dispatch_source_t gTimer;

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
        gActive = [NSMutableDictionary dictionary];
        notify_register_check(SEQ_STATE_NOTIFY, &gTokState);
        int t1;
        notify_register_dispatch(SEQ_PREFS_NOTIFY, &t1, dispatch_get_main_queue(), ^(int x) { [SEQHub publish]; });
        notify_register_dispatch(SEQ_ACTIVE_NOTIFY, &gTokActive, dispatch_get_main_queue(), ^(int x) { [SEQHub activity]; });

        gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), 3 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(gTimer, ^{ [SEQHub updateStatus]; });
        dispatch_resume(gTimer);

        [SEQHub publish];
    });
}

+ (void)publish {
    SEQSettings s;
    SEQLoadSettings(&s);

    int mode = SEQGetPrefInt("mode", 0);
    BOOL show = SEQGetPrefBool("showOverlay", true);
    static const char *outKeys[5] = { "out.speaker", "out.wired", "out.bt", "out.airplay", "out.other" };
    uint64_t mask = 0;
    for (int i = 0; i < 5; i++) if (SEQGetPrefBool(outKeys[i], true)) mask |= (1ull << i);

    uint64_t st = SEQPack(&s) | (mode ? 2ull : 0ull) | (mask << 56);
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

+ (NSDictionary *)appForHash:(uint64_t)h {
    NSNumber *k = @(h);
    NSDictionary *a = gHashMap[k];
    if (!a && (!gHashMapDate || [[NSDate date] timeIntervalSinceDate:gHashMapDate] > 30)) {
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (NSDictionary *d in SEQInstalledApps()) m[@(SEQHashString([d[@"bid"] UTF8String]))] = d;
        gHashMap = m;
        gHashMapDate = [NSDate date];
        a = gHashMap[k];
    }
    return a;
}

+ (void)activity {
    uint64_t h = 0;
    if (gTokActive >= 0) notify_get_state(gTokActive, &h);
    NSDictionary *a = [SEQHub appForHash:h];
    if (!a) return;
    gActive[a[@"bid"]] = @{ @"bid": a[@"bid"], @"name": a[@"name"], @"t": [NSDate date] };
    [SEQHub updateStatus];
}

+ (NSArray<NSDictionary *> *)activeApps {
    NSDate *now = [NSDate date];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *bid in [gActive allKeys]) {
        NSDictionary *d = gActive[bid];
        if ([now timeIntervalSinceDate:d[@"t"]] > 6.0) { [gActive removeObjectForKey:bid]; continue; }
        [out addObject:d];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        return [x[@"name"] localizedCaseInsensitiveCompare:y[@"name"]];
    }];
    return out;
}

+ (void)updateStatus {
    NSArray *a = [SEQHub activeApps];
    NSString *txt;
    if (a.count == 0) {
        txt = @"Aucun son détecté";
    } else {
        NSMutableArray *names = [NSMutableArray array];
        for (NSDictionary *d in a) [names addObject:d[@"name"]];
        txt = [@"Son : " stringByAppendingString:[names componentsJoinedByString:@", "]];
    }
    [SEQOverlay setStatus:txt];
}

@end
