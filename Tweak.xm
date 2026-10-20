#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#include <notify.h>
#include <stdlib.h>
#include "EQShared.h"

@interface SEQOverlay : NSObject
+ (void)show;
@end

static OSStatus wrappedRender(void *refCon, AudioUnitRenderActionFlags *flags,
                              const AudioTimeStamp *ts, UInt32 bus, UInt32 frames,
                              AudioBufferList *io) {
    SEQCtx *c = (SEQCtx *)refCon;
    OSStatus s = c->orig(c->origRefCon, flags, ts, bus, frames, io);
    if (s == noErr && io && !(*flags & kAudioUnitRenderAction_OutputIsSilence))
        SEQProcess(c, io, frames);
    return s;
}

static bool isOutputUnit(AudioUnit unit) {
    AudioComponent comp = AudioComponentInstanceGetComponent(unit);
    if (!comp) return false;
    AudioComponentDescription d;
    if (AudioComponentGetDescription(comp, &d) != noErr) return false;
    return d.componentType == kAudioUnitType_Output &&
           (d.componentSubType == kAudioUnitSubType_RemoteIO ||
            d.componentSubType == kAudioUnitSubType_VoiceProcessingIO);
}

%group Audio
%hookf(OSStatus, AudioUnitSetProperty, AudioUnit unit, AudioUnitPropertyID pid,
       AudioUnitScope scope, AudioUnitElement elem, const void *data, UInt32 size) {
    if (pid == kAudioUnitProperty_SetRenderCallback && scope == kAudioUnitScope_Input &&
        data && size >= sizeof(AURenderCallbackStruct) && isOutputUnit(unit)) {
        const AURenderCallbackStruct *in = (const AURenderCallbackStruct *)data;
        if (in->inputProc && in->inputProc != wrappedRender) {
            SEQCtx *c = (SEQCtx *)calloc(1, sizeof(SEQCtx)); // fuite volontaire (petite)
            c->unit = unit; c->bus = elem;
            c->orig = in->inputProc; c->origRefCon = in->inputProcRefCon;
            AURenderCallbackStruct n = { wrappedRender, c };
            return %orig(unit, pid, scope, elem, &n, sizeof(n));
        }
    }
    return %orig;
}
%end

%group SB
%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{ [SEQOverlay show]; });
}
%end
%end

%ctor {
    @autoreleasepool {
        SEQReloadGlobal();
        int tok;
        notify_register_dispatch(SEQ_NOTIFY, &tok, dispatch_get_main_queue(), ^(int t){ SEQReloadGlobal(); });
        %init(Audio);
        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"])
            %init(SB);
    }
}
