#include "EQShared.h"
#include <math.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <notify.h>

const float kSEQFreqs[SEQ_BANDS] = { 60.f, 230.f, 910.f, 3600.f, 14000.f };

static SEQSettings gSet;
static volatile int gVer = 1;

/* ---------- préférences (utilisées par SpringBoard / overlay) ---------- */
void SEQLoadSettings(SEQSettings *s) {
    memset(s, 0, sizeof(*s));
    CFPreferencesAppSynchronize(SEQ_PREFS_DOMAIN);
    CFPropertyListRef en = CFPreferencesCopyAppValue(CFSTR("enabled"), SEQ_PREFS_DOMAIN);
    s->enabled = (en && CFGetTypeID(en) == CFBooleanGetTypeID()) ? CFBooleanGetValue(en) : false;
    if (en) CFRelease(en);
    CFPropertyListRef p = CFPreferencesCopyAppValue(CFSTR("pre"), SEQ_PREFS_DOMAIN);
    double d = 0; if (p) { CFNumberGetValue(p, kCFNumberDoubleType, &d); CFRelease(p); }
    s->pre = (float)d;
    for (int i = 0; i < SEQ_BANDS; i++) {
        CFStringRef k = CFStringCreateWithFormat(NULL, NULL, CFSTR("band%d"), i);
        CFPropertyListRef v = CFPreferencesCopyAppValue(k, SEQ_PREFS_DOMAIN);
        double g = 0; if (v) { CFNumberGetValue(v, kCFNumberDoubleType, &g); CFRelease(v); }
        s->gains[i] = (float)g;
        CFRelease(k);
    }
}

void SEQSaveSettings(const SEQSettings *s) {
    CFPreferencesSetAppValue(CFSTR("enabled"), s->enabled ? kCFBooleanTrue : kCFBooleanFalse, SEQ_PREFS_DOMAIN);
    double d = s->pre;
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberDoubleType, &d);
    CFPreferencesSetAppValue(CFSTR("pre"), n, SEQ_PREFS_DOMAIN); CFRelease(n);
    for (int i = 0; i < SEQ_BANDS; i++) {
        CFStringRef k = CFStringCreateWithFormat(NULL, NULL, CFSTR("band%d"), i);
        double g = s->gains[i];
        CFNumberRef v = CFNumberCreate(NULL, kCFNumberDoubleType, &g);
        CFPreferencesSetAppValue(k, v, SEQ_PREFS_DOMAIN);
        CFRelease(v); CFRelease(k);
    }
    CFPreferencesAppSynchronize(SEQ_PREFS_DOMAIN);
    notify_post(SEQ_PREFS_NOTIFY);
}

/* ---------- état compact diffusé via notifyd (64 bits) ----------
   bit0 = activé, bit1 = mode (0 = toutes sauf liste, 1 = seulement liste)
   bits 8..15 = préampli (demi-dB, int8), bits 16.. = 5 bandes (demi-dB, int8) */
uint64_t SEQPack(const SEQSettings *s) {
    uint64_t v = s->enabled ? 1ull : 0ull;
    v |= (uint64_t)(uint8_t)(int8_t)lrintf(s->pre * 2.f) << 8;
    for (int i = 0; i < SEQ_BANDS; i++)
        v |= (uint64_t)(uint8_t)(int8_t)lrintf(s->gains[i] * 2.f) << (16 + 8 * i);
    return v;
}

void SEQApplyState(uint64_t st, bool listed) {
    SEQSettings s;
    memset(&s, 0, sizeof(s));
    s.pre = (float)(int8_t)((st >> 8) & 0xff) / 2.f;
    for (int i = 0; i < SEQ_BANDS; i++)
        s.gains[i] = (float)(int8_t)((st >> (16 + 8 * i)) & 0xff) / 2.f;
    bool on = (st & 1ull) != 0;
    bool includeOnly = (st & 2ull) != 0;
    s.enabled = on && (includeOnly ? listed : !listed);
    gSet = s;
    gVer++;
}

/* ---------- DSP ---------- */
static void calcCoef(SEQCoef *c, float f, float dB, float fs) {
    if (f >= fs * 0.45f) { c->b0 = 1; c->b1 = c->b2 = c->a1 = c->a2 = 0; return; }
    float A = powf(10.f, dB / 40.f);
    float w0 = 2.f * (float)M_PI * f / fs;
    float al = sinf(w0) / 2.f; // Q = 1
    float cs = cosf(w0);
    float a0 = 1.f + al / A;
    c->b0 = (1.f + al * A) / a0;
    c->b1 = (-2.f * cs) / a0;
    c->b2 = (1.f - al * A) / a0;
    c->a1 = (-2.f * cs) / a0;
    c->a2 = (1.f - al / A) / a0;
}

static void applyChunk(SEQCtx *c, int ch, float *x, UInt32 n) {
    if (fabsf(c->set.pre) > 0.01f) {
        float pre = powf(10.f, c->set.pre / 20.f);
        for (UInt32 i = 0; i < n; i++) x[i] *= pre;
    }
    for (int b = 0; b < SEQ_BANDS; b++) {
        if (fabsf(c->set.gains[b]) < 0.05f) continue;
        const SEQCoef k = c->coef[b];
        float z1 = c->z[ch][b][0], z2 = c->z[ch][b][1];
        for (UInt32 i = 0; i < n; i++) {
            float in = x[i];
            float y = k.b0 * in + z1;
            z1 = k.b1 * in - k.a1 * y + z2;
            z2 = k.b2 * in - k.a2 * y;
            x[i] = y;
        }
        c->z[ch][b][0] = z1; c->z[ch][b][1] = z2;
    }
}

static void runChannel(SEQCtx *c, int ch, void *data, UInt32 frames, UInt32 stride, bool isFloat) {
    float tmp[512];
    for (UInt32 done = 0; done < frames; ) {
        UInt32 n = frames - done; if (n > 512) n = 512;
        for (UInt32 i = 0; i < n; i++) {
            UInt32 idx = (done + i) * stride;
            tmp[i] = isFloat ? ((float *)data)[idx] : ((SInt16 *)data)[idx] / 32768.f;
        }
        applyChunk(c, ch, tmp, n);
        for (UInt32 i = 0; i < n; i++) {
            UInt32 idx = (done + i) * stride;
            float v = tmp[i]; if (v > 1.f) v = 1.f; else if (v < -1.f) v = -1.f;
            if (isFloat) ((float *)data)[idx] = v;
            else ((SInt16 *)data)[idx] = (SInt16)lrintf(v * 32767.f);
        }
        done += n;
    }
}

void SEQProcess(SEQCtx *c, AudioBufferList *io, UInt32 frames) {
    if (!c->fmtOK) {
        if (c->bad > 50) return;
        UInt32 sz = sizeof(c->fmt);
        if (AudioUnitGetProperty(c->unit, kAudioUnitProperty_StreamFormat,
                                 kAudioUnitScope_Input, c->bus, &c->fmt, &sz) != noErr) { c->bad++; return; }
        c->fmtOK = true; c->ver = 0;
    }
    int v = gVer;
    if (c->ver != v) {
        c->set = gSet; c->ver = v; c->announced = false;
        float fs = c->fmt.mSampleRate > 0 ? (float)c->fmt.mSampleRate : 48000.f;
        for (int b = 0; b < SEQ_BANDS; b++) calcCoef(&c->coef[b], kSEQFreqs[b], c->set.gains[b], fs);
    }
    if (!c->set.enabled) return;

    const AudioStreamBasicDescription *f = &c->fmt;
    if (f->mFormatID != kAudioFormatLinearPCM || f->mBytesPerFrame == 0) return;
    bool isFloat = (f->mFormatFlags & kAudioFormatFlagIsFloat) && f->mBitsPerChannel == 32;
    bool isS16 = (f->mFormatFlags & kAudioFormatFlagIsSignedInteger) && f->mBitsPerChannel == 16;
    if (!isFloat && !isS16) return;
    bool nonInter = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;

    /* sécurité : le tampon doit correspondre au format lu, sinon on relit le format */
    UInt32 need = frames * f->mBytesPerFrame;
    for (UInt32 i = 0; i < io->mNumberBuffers; i++) {
        if (io->mBuffers[i].mData && io->mBuffers[i].mDataByteSize < need) {
            c->fmtOK = false; c->bad++;
            return;
        }
    }

    if (!c->announced) { c->announced = true; SEQAnnounceActive(); }

    if (nonInter) {
        for (UInt32 i = 0; i < io->mNumberBuffers && i < SEQ_MAXCH; i++)
            if (io->mBuffers[i].mData) runChannel(c, (int)i, io->mBuffers[i].mData, frames, 1, isFloat);
    } else if (io->mNumberBuffers > 0 && io->mBuffers[0].mData) {
        UInt32 nch = io->mBuffers[0].mNumberChannels;
        for (UInt32 ch = 0; ch < nch && ch < SEQ_MAXCH; ch++) {
            void *base = isFloat ? (void *)((float *)io->mBuffers[0].mData + ch)
                                 : (void *)((SInt16 *)io->mBuffers[0].mData + ch);
            runChannel(c, (int)ch, base, frames, nch, isFloat);
        }
    }
}
