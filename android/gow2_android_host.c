/* GoW2 Android host glue: perf log and the guest thread; see gow2_android_host.h. */
#include "gow2_android_host.h"
#include "gow2_android_sigtest.h"
#include "gcm_rsxt.h"   /* gcm_rsx_consumer_stop (PS3_RSX_THREAD) */
#include "gow2_boot.h"
#include "gow2_android_perf.h"

#include <dlfcn.h>
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
extern void host_profiler_start(void);       /* runtime/host_profiler.c (PS3_HOST_PROFILE=1) */

/* AThermal_* is API 30; resolved at run time so the app still starts (and reports thermal_src=none) below it.
 * Also read by the home screen's host status (gow2_android_home.c). */
static void* s_thermal_mgr;
static int (*s_thermal_get)(void*);
static pthread_once_t s_thermal_once = PTHREAD_ONCE_INIT;

static void thermal_init(void)
{
    void* h = dlopen("libandroid.so", RTLD_NOW);
    void* (*acq)(void) = h ? (void* (*)(void))dlsym(h, "AThermal_acquireManager") : NULL;
    s_thermal_get = h ? (int (*)(void*))dlsym(h, "AThermal_getCurrentThermalStatus") : NULL;
    if (acq && s_thermal_get) s_thermal_mgr = acq();
}

int gow2_android_thermal_status(int* have)   /* the SDL main thread (home) and the perf thread: one-time init */
{
    pthread_once(&s_thermal_once, thermal_init);
    /* a manager whose status call fails (ATHERMAL_STATUS_ERROR = -1) is "no data", not a cool reading */
    const int st = s_thermal_mgr ? s_thermal_get(s_thermal_mgr) : -1;
    *have = st >= 0;
    return st;
}

/* Current frequency of cpu0..7 in MHz, "-1" where sysfs is not readable by the app. */
static void read_cpu_mhz(char* out, size_t cap)
{
    size_t n = 0;
    out[0] = 0;
    for (int c = 0; c < 8 && n + 8 < cap; c++) {
        char p[96];
        snprintf(p, sizeof p, "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_cur_freq", c);
        long khz = -1;
        FILE* f = fopen(p, "r");
        if (f) { if (fscanf(f, "%ld", &khz) != 1) khz = -1; fclose(f); }
        n += (size_t)snprintf(out + n, cap - n, "%s%ld", c ? "," : "", khz > 0 ? khz / 1000 : -1L);
    }
}

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
        char mi[4096] = "";
        FILE* mf = fopen("/proc/meminfo", "r");
        if (mf) { size_t n = fread(mi, 1, sizeof mi - 1, mf); mi[n] = 0; fclose(mf); }
        int have = 0;
        const int ts = gow2_android_thermal_status(&have);
        char mhz[96], line[320];
        read_cpu_mhz(mhz, sizeof mhz);
        gow2_android_format_perf_line(line, sizeof line, (double)(mono_ms() - t0) / 1000.0,
                                      gow2_android_thermal_level(ts), have ? "athermal" : "none", rss_kb / 1024,
                                      gow2_android_meminfo_available_mb(mi), f, f - last, mhz);
        fprintf(stderr, "%s\n", line);
        last = f;
    }
    return NULL;
}

void gow2_android_perf_start(void)
{
    host_profiler_start();                       /* PS3_HOST_PROFILE=1 (OFF): SIGPROF sampler, [HPROF] lines every 10 s */
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

static pthread_t s_guest;
static volatile int s_guest_done, s_guest_rc;

static void* guest_thread(void* arg)
{
    void* rc = guest_main(arg);
    s_guest_rc = (int)(intptr_t)rc;
    __atomic_store_n(&s_guest_done, 1, __ATOMIC_RELEASE);
    return rc;
}

int gow2_android_start_guest(const char* eboot, const char* scratch)
{
    static guest_args g;
    g.eboot = eboot; g.scratch = scratch;
    pthread_attr_t a;
    pthread_attr_init(&a);
    const int ss = pthread_attr_setstacksize(&a, (size_t)64 << 20);   /* the SDL_main thread has ~1 MB */
    if (ss != 0) {
        pthread_attr_destroy(&a);
        fprintf(stderr, "[android] FATAL: guest stack size 64 MB refused (%s)\n", strerror(ss));
        return ss;
    }
    const int rc = pthread_create(&s_guest, &a, guest_thread, &g);
    pthread_attr_destroy(&a);
    fprintf(stderr, "[android] guest thread %s (64 MB stack)\n", rc == 0 ? "started" : "FAILED");
    return rc;
}

int gow2_android_guest_exited(int* rc)
{
    if (!__atomic_load_n(&s_guest_done, __ATOMIC_ACQUIRE)) return 0;
    if (rc) *rc = s_guest_rc;
    return 1;
}

int gow2_android_run_guest(const char* eboot, const char* scratch_dir)   /* blocks, _exit()s */
{
    const int rc = gow2_android_start_guest(eboot, scratch_dir);
    if (rc != 0) return rc;
    void* ret = NULL;
    pthread_join(s_guest, &ret);
    if (gcm_rsx_consumer_stop(250000000ull) == 0) {   /* PS3_RSX_THREAD: drained + stopped, else touch nothing */
        fprintf(stderr, "[android] guest returned rc=%d -- exiting\n", (int)(intptr_t)ret);
        gow2_android_log_flush();
    }
    _exit((int)(intptr_t)ret == 0 ? 0 : 1);
}
