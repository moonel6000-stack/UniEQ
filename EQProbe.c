/* Sonde PASSIVE pour mediaserverd / audiomxd : ne modifie jamais le son.
   Elle note quelles fonctions audio existent dans le processus et lesquelles sont appelées. */
#include "EQShared.h"
#include <substrate.h>
#include <dlfcn.h>
#include <notify.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dispatch/dispatch.h>

static volatile uint64_t gProbe = 0;
static int gProbeTok = -1;
static dispatch_queue_t gPQ;

static void probeMark(uint64_t bits) {
    uint64_t old = __atomic_fetch_or(&gProbe, bits, __ATOMIC_RELAXED);
    if ((old | bits) != old && gPQ) {
        dispatch_async(gPQ, ^{ if (gProbeTok >= 0) notify_set_state(gProbeTok, gProbe); });
    }
}

typedef long (*gfn)(long, long, long, long, long, long, long, long);
static gfn gOrig[SEQ_NPROBE];

#define SEQ_HOOK(N) \
    static long hook##N(long a, long b, long c, long d, long e, long f, long g, long h) { \
        probeMark(1ull << (16 + N)); \
        return gOrig[N](a, b, c, d, e, f, g, h); \
    }
SEQ_HOOK(0) SEQ_HOOK(1) SEQ_HOOK(2) SEQ_HOOK(3) SEQ_HOOK(4)
SEQ_HOOK(5) SEQ_HOOK(6) SEQ_HOOK(7) SEQ_HOOK(8) SEQ_HOOK(9)

static void *kHooks[SEQ_NPROBE] = {
    (void *)hook0, (void *)hook1, (void *)hook2, (void *)hook3, (void *)hook4,
    (void *)hook5, (void *)hook6, (void *)hook7, (void *)hook8, (void *)hook9
};

void SEQProbeInit(const char *proc) {
    char name[96];
    snprintf(name, sizeof(name), "com.example.syseq/probe.%s", proc);
    gPQ = dispatch_queue_create("com.example.syseq.probe", DISPATCH_QUEUE_SERIAL);
    notify_register_check(name, &gProbeTok);

    uint64_t present = 0;
    for (int i = 0; i < SEQ_NPROBE; i++) {
        void *sym = dlsym(RTLD_DEFAULT, kSEQProbeNames[i]);
        if (sym) {
            present |= (1ull << i);
            MSHookFunction(sym, kHooks[i], (void **)&gOrig[i]);
        }
    }
    probeMark(present | (1ull << 63));   /* bit 63 = sonde chargée */
}

/* Cette bibliothèque est un tweak SÉPARÉ (SysEQProbe) : elle ne se charge que dans mediaserverd / audiomxd,
   sans UIKit, et s'initialise toute seule. */
__attribute__((constructor)) static void SEQProbeAutoInit(void) {
    const char *pn = getprogname();
    if (pn && (strcmp(pn, "mediaserverd") == 0 || strcmp(pn, "audiomxd") == 0)) SEQProbeInit(pn);
}
