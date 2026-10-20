#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <stdbool.h>
#include <stdint.h>

#define SEQ_BANDS 5
#define SEQ_MAXCH 8
#define SEQ_PREFS_DOMAIN CFSTR("com.example.syseq")
#define SEQ_PREFS_NOTIFY  "com.example.syseq/prefschanged"
#define SEQ_STATE_NOTIFY  "com.example.syseq/state"
#define SEQ_ACTIVE_NOTIFY "com.example.syseq/active"
#define SEQ_APP_PREFIX    "com.example.syseq/app."

extern const float kSEQFreqs[SEQ_BANDS];

typedef struct {
    bool  enabled;
    float pre;                 // dB
    float gains[SEQ_BANDS];    // dB, -12..+12
} SEQSettings;

typedef struct { float b0,b1,b2,a1,a2; } SEQCoef;

typedef struct {
    AudioUnit unit;
    UInt32 bus;
    bool fmtOK;
    bool announced;
    int bad;
    AudioStreamBasicDescription fmt;
    int ver;
    SEQSettings set;
    SEQCoef coef[SEQ_BANDS];
    float z[SEQ_MAXCH][SEQ_BANDS][2];
} SEQCtx;

#ifdef __cplusplus
extern "C" {
#endif
void SEQLoadSettings(SEQSettings *s);
void SEQSaveSettings(const SEQSettings *s);
uint64_t SEQPack(const SEQSettings *s);
void SEQApplyState(uint64_t st, bool listed);
void SEQProcess(SEQCtx *c, AudioBufferList *io, UInt32 frames);
void SEQAnnounceActive(void);   /* défini dans Tweak.xm */
#ifdef __cplusplus
}
#endif

#ifdef __OBJC__
@interface SEQOverlay : NSObject
+ (void)show;
+ (void)setVisible:(BOOL)v;
+ (void)setStatus:(NSString *)s;
@end

@interface SEQHub : NSObject
+ (void)start;
@end
#endif
