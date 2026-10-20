#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#include <notify.h>
#include <substrate.h>
#include <stdlib.h>
#include <string.h>
#include "EQShared.h"

@interface SEQOverlay : NSObject
+ (void)show;
@end

static OSStatus wrappedRender(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *io) {
    SEQCtx *c = (SEQCtx *)refCon;
    OSStatus s = c->orig(c->origRefCon, flags, ts, bus, frames, io);
    if (s == noErr && io && !(*flags & kAudioUnitRenderAction_OutputIsSilence)) {
        SEQProcess(c, io, frames);
    }
    return s;
}

static bool isOutputUnit(AudioUnit unit) {
    AudioComponent comp = AudioComponentInstanceGetComponent(unit);
    if (!comp) return false;
    AudioComponentDescription d;
    if (AudioComponentGetDescription(comp, &d) != noErr) return false;
    if (d.componentType != kAudioUnitType_Output) return false;
    return d.componentSubType == kAudioUnitSubType_RemoteIO || d.componentSubType == kAudioUnitSubType_VoiceProcessingIO;
}

static OSStatus (*orig_AudioUnitSetProperty)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);

static OSStatus hook_AudioUnitSetProperty(AudioUnit unit, AudioUnitPropertyID pid, AudioUnitScope scope, AudioUnitElement elem, const void *data, UInt32 size) {
    if (pid == kAudioUnitProperty_SetRenderCallback && scope == kAudioUnitScope_Input && data && size >= sizeof(AURenderCallbackStruct) && isOutputUnit(unit)) {
        const AURenderCallbackStruct *cb = (const AURenderCallbackStruct *)data;
        if (cb->inputProc && (void *)cb->inputProc != (void *)wrappedRender) {
            SEQCtx *c = (SEQCtx *)calloc(1, sizeof(SEQCtx));
            c->unit = unit;
            c->bus = elem;
            c->orig = cb->inputProc;
            c->origRefCon = cb->inputProcRefCon;
            AURenderCallbackStruct n;
            n.inputProc = (AURenderCallback)(void *)wrappedRender;
            n.inputProcRefCon = c;
            return orig_AudioUnitSetProperty(unit, pid, scope, elem, &n, (UInt32)sizeof(n));
        }
    }
    return orig_AudioUnitSetProperty(unit, pid, scope, elem, data, size);
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [SEQOverlay show];
    });
}
%end

%ctor {
    SEQReloadGlobal();
    static int tok;
    notify_register_dispatch(SEQ_NOTIFY, &tok, dispatch_get_main_queue(), ^(int t) {
        SEQReloadGlobal();
    });
    MSHookFunction((void *)AudioUnitSetProperty, (void *)hook_AudioUnitSetProperty, (void **)&orig_AudioUnitSetProperty);
    %init;
}
