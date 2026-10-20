#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <stdbool.h>

#define SEQ_BANDS 5
#define SEQ_NOTIFY "com.example.syseq/changed"
#define SEQ_MAXCH 8

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
    AURenderCallback orig;
    void *origRefCon;
    bool fmtOK;
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
void SEQReloadGlobal(void);
void SEQProcess(SEQCtx *c, AudioBufferList *io, UInt32 frames);
#ifdef __cplusplus
}
#endif
