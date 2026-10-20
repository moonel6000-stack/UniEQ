#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#include <notify.h>
#include <substrate.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <os/lock.h>
#include "EQShared.h"

static dispatch_queue_t gQ;

/* ---------- rendu : on s'accroche en "post-render" sur l'unité de sortie ---------- */
static OSStatus eqNotify(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *io) {
    if ((*flags & kAudioUnitRenderAction_PostRender) && io) {
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
    return orig_Start(u);
}
static OSStatus (*orig_Dispose)(AudioComponentInstance);
static OSStatus hook_Dispose(AudioComponentInstance u) {
    forgetUnit(u);
    return orig_Dispose(u);
}

/* ---------- état reçu depuis SpringBoard (via notifyd, sans accès fichier) ---------- */
static int gTokState = -1;
static int gTokApp = -1;

static void pullState(void) {
    uint64_t st = 0, a = 0;
    if (gTokState >= 0) notify_get_state(gTokState, &st);
    if (gTokApp >= 0) notify_get_state(gTokApp, &a);
    SEQApplyState(st, a != 0);
}

extern "C" void SEQAnnounceActive(void) {
    dispatch_async(gQ, ^{
        static int t = -1;
        if (t < 0) notify_register_check(SEQ_ACTIVE_NOTIFY, &t);
        if (t >= 0) notify_set_state(t, (uint64_t)getpid());
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
        NSString *name = [NSString stringWithFormat:@"%s%@", SEQ_APP_PREFIX, bid];
        notify_register_dispatch(name.UTF8String, &gTokApp, gQ, ^(int t) { pullState(); });
    }
    pullState();

    MSHookFunction((void *)AudioUnitInitialize, (void *)hook_Init, (void **)&orig_Init);
    MSHookFunction((void *)AudioOutputUnitStart, (void *)hook_Start, (void **)&orig_Start);
    MSHookFunction((void *)AudioComponentInstanceDispose, (void *)hook_Dispose, (void **)&orig_Dispose);
    %init;
}
