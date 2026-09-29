/* GoW2 Android host glue: perf log and the guest thread; see gow2_android_host.h. */
#include "gow2_android_host.h"
#include "gow2_android_sigtest.h"
#include "gow2_boot.h"

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static uint64_t mono_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000u + (uint64_t)t.tv_nsec / 1000000u;
}

extern uint32_t ps3_gcm_flip_count(void);   /* libs/video/cellGcmSys.c */

static void* perf_thread(void* arg)
{
    (void)arg;
    pthread_setname_np(pthread_self(), "gow2-perf");
    const uint64_t t0 = mono_ms();
    uint32_t last = ps3_gcm_flip_count();
    for (;;) {
        sleep(1);
        const uint32_t f = ps3_gcm_flip_count();
        long rss_kb = 0;
        FILE* st = fopen("/proc/self/status", "r");
        if (st) { char l[256]; while (fgets(l, sizeof l, st)) if (!strncmp(l, "VmRSS:", 6)) rss_kb = atol(l + 6); fclose(st); }
        fprintf(stderr, "[ANDPERF] t=%.1f flips=%u fps=%u rss_mb=%ld\n", (double)(mono_ms() - t0) / 1000.0, f, f - last, rss_kb / 1024);
        last = f;
    }
    return NULL;
}

void gow2_android_perf_start(void)
{
    const char* e = getenv("PS3_ANDROID_PERF_LOG");
    if (!(e && e[0] == '1')) return;
    pthread_t t;
    if (pthread_create(&t, NULL, perf_thread, NULL) == 0) pthread_detach(t);
}

typedef struct { const char* eboot; const char* scratch; } guest_args;

static void* guest_main(void* arg)
{
    const guest_args* g = (const guest_args*)arg;
    pthread_setname_np(pthread_self(), "guest-main");
    if (gow2_boot_prepare_guest(g->eboot) != 0) {
        fprintf(stderr, "[android] FATAL: guest preparation failed\n");
        return (void*)(intptr_t)1;
    }
    const char* st = getenv("PS3_ANDROID_SIGTEST");
    if (st && st[0] == '1') (void)gow2_android_sigtest_run(g->scratch);
    return (void*)(intptr_t)gow2_boot_run_guest();
}

int gow2_android_run_guest(const char* eboot, const char* scratch_dir)
{
    static guest_args g;
    g.eboot = eboot; g.scratch = scratch_dir;
    pthread_attr_t a;
    pthread_attr_init(&a);
    const int ss = pthread_attr_setstacksize(&a, (size_t)64 << 20);   /* the SDL_main thread has ~1 MB */
    if (ss != 0) { fprintf(stderr, "[android] FATAL: guest stack size 64 MB refused (%s)\n", strerror(ss)); return ss; }
    pthread_t t;
    const int rc = pthread_create(&t, &a, guest_main, &g);
    pthread_attr_destroy(&a);
    fprintf(stderr, "[android] guest thread %s (64 MB stack)\n", rc == 0 ? "started" : "FAILED");
    if (rc != 0) return rc;
    void* ret = NULL;
    pthread_join(t, &ret);
    fprintf(stderr, "[android] guest returned rc=%d -- exiting\n", (int)(intptr_t)ret);
    gow2_android_log_flush();
    _exit((int)(intptr_t)ret == 0 ? 0 : 1);
}
