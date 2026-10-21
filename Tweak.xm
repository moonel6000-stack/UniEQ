#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <notify.h>
#include <substrate.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <os/lock.h>
#include "EQShared.h"

static dispatch_queue_t gQ;

/* ---------- sortie audio courante (haut-parleur, filaire, Bluetooth, AirPlay, autre) ---------- */
static int classifyRoute(void) {
    int bits = 0;
    AVAudioSessionRouteDescription *r = [AVAudioSession sharedInstance].currentRoute;
    for (AVAudioSessionPortDescription *p in r.outputs) {
        NSString *t = p.portType;
        if ([t isEqualToString:AVAudioSessionPortBuiltInSpeaker] || [t isEqualToString:AVAudioSessionPortBuiltInReceiver]) bits |= 1;
        else if ([t isEqualToString:AVAudioSessionPortHeadphones] || [t isEqualToString:AVAudioSessionPortLineOut]) bits |= 2;
        else if ([t isEqualToString:AVAudioSessionPortBluetoothA2DP] || [t isEqualToString:AVAudioSessionPortBluetoothHFP] || [t isEqualToString:AVAudioSessionPortBluetoothLE]) bits |= 4;
        else if ([t isEqualToString:AVAudioSessionPortAirPlay]) bits |= 8;
        else bits |= 16;
    }
    return bits;
}

static void refreshRoute(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ SEQSetRoute(classifyRoute()); });
}

static void startRouteWatch(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionRouteChangeNotification
                                                              object:nil
                                                               queue:nil
                                                          usingBlock:^(NSNotification *n) { SEQSetRoute(classifyRoute()); }];
            SEQSetRoute(classifyRoute());
        });
    });
}

/* ---------- rendu : on s'accroche en "post-render" sur l'unité de sortie ---------- */
static OSStatus eqNotify(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *io) {
    if ((*flags & kAudioUnitRenderAction_PostRender) && !(*flags & kAudioUnitRenderAction_OutputIsSilence) && io) {
        SEQProcess((SEQCtx *)refCon, io, frames);
    }
    return noErr;
}

static bool isOutputUnit(AudioUnit unit) {
    AudioComponent comp = AudioComponentInstanceGetComponent(unit);
    if (!comp) return false;
    AudioComponentDescription d;
    if (AudioComponentGetDescription(comp, &d) != noErr) return false;
    if (d.componentType != kAudioUnitType_Output) return false;
    return d.componentSubType == kAudioUnitSubType_RemoteIO || d.componentSubType == kAudioUnitSubType_VoiceProcessingIO;
}

#define SEQ_MAXUNITS 64
static AudioUnit gUnits[SEQ_MAXUNITS];
static int gNumUnits = 0;
static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;

static void ensureNotify(AudioUnit unit) {
    if (!unit || !isOutputUnit(unit)) return;
    bool add = false;
    os_unfair_lock_lock(&gLock);
    bool found = false;
    for (int i = 0; i < gNumUnits; i++) if (gUnits[i] == unit) { found = true; break; }
    if (!found && gNumUnits < SEQ_MAXUNITS) { gUnits[gNumUnits++] = unit; add = true; }
    os_unfair_lock_unlock(&gLock);
    if (!add) return;
    startRouteWatch();
    SEQCtx *c = (SEQCtx *)calloc(1, sizeof(SEQCtx));
    c->unit = unit;
    c->bus = 0;
    AudioUnitAddRenderNotify(unit, (AURenderCallback)(void *)eqNotify, c);
}

static void forgetUnit(AudioUnit unit) {
    os_unfair_lock_lock(&gLock);
    for (int i = 0; i < gNumUnits; i++) {
        if (gUnits[i] == unit) { gUnits[i] = gUnits[--gNumUnits]; break; }
    }
    os_unfair_lock_unlock(&gLock);
}

static OSStatus (*orig_Init)(AudioUnit);
static OSStatus hook_Init(AudioUnit u) {
    OSStatus s = orig_Init(u);
    if (s == noErr) ensureNotify(u);
    return s;
}
static OSStatus (*orig_Start)(AudioUnit);
static OSStatus hook_Start(AudioUnit u) {
    ensureNotify(u);
    refreshRoute();
    return orig_Start(u);
}
static OSStatus (*orig_Dispose)(AudioComponentInstance);
static OSStatus hook_Dispose(AudioComponentInstance u) {
    forgetUnit(u);
    return orig_Dispose(u);
}

/* ---------- état reçu depuis SpringBoard (via notifyd, sans accès fichier) ---------- */
static uint64_t gSelfHash = 0;
static int gTokState = -1;
static int gTokApp = -1;

static void pullState(void) {
    uint64_t st = 0, a = 0;
    if (gTokState >= 0) notify_get_state(gTokState, &st);
    if (gTokApp >= 0) notify_get_state(gTokApp, &a);
    SEQApplyState(st, a != 0);
}

extern "C" void SEQAnnounceActive(void) {
    if (!gSelfHash) return;
    dispatch_async(gQ, ^{
        static int t = -1;
        if (t < 0) notify_register_check(SEQ_ACTIVE_NOTIFY, &t);
        if (t >= 0) notify_set_state(t, gSelfHash);
        notify_post(SEQ_ACTIVE_NOTIFY);
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [SEQHub start];
    });
}
%end

%ctor {
    gQ = dispatch_queue_create("com.example.syseq.q", DISPATCH_QUEUE_SERIAL);

    notify_register_dispatch(SEQ_STATE_NOTIFY, &gTokState, gQ, ^(int t) { pullState(); });

    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (bid.length) {
        gSelfHash = SEQHashString(bid.UTF8String);
        NSString *name = [NSString stringWithFormat:@"%s%@", SEQ_APP_PREFIX, bid];
        notify_register_dispatch(name.UTF8String, &gTokApp, gQ, ^(int t) { pullState(); });
    }
    pullState();

    MSHookFunction((void *)AudioUnitInitialize, (void *)hook_Init, (void **)&orig_Init);
    MSHookFunction((void *)AudioOutputUnitStart, (void *)hook_Start, (void **)&orig_Start);
    MSHookFunction((void *)AudioComponentInstanceDispose, (void *)hook_Dispose, (void **)&orig_Dispose);
    %init;
}
