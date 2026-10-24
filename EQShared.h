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
    UInt32 sinceAnn;
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
uint64_t SEQHashString(const char *s);
#define SEQ_NPROBE 10
extern const char *kSEQProbeNames[SEQ_NPROBE];
void SEQProbeInit(const char *proc);
void SEQResetAppSelection(void);
void SEQSetRoute(int route);    /* 1=HP 2=filaire 4=Bluetooth 8=AirPlay 16=autre 0=inconnu */
bool SEQGetPrefBool(const char *key, bool def);
int  SEQGetPrefInt(const char *key, int def);
void SEQSetPrefBool(const char *key, bool v);
void SEQSetPrefInt(const char *key, int v);
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
+ (NSString *)probeReport;   /* diagnostic mediaserverd / audiomxd */
+ (NSArray<NSDictionary *> *)activeApps;   /* apps qui produisent du son (bid, name) */
@end
#endif
