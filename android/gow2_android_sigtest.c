/* PS3_ANDROID_SIGTEST; see gow2_android_sigtest.h. */
#include "gow2_android_sigtest.h"
#include "spu_workload.h"
#include "spu_context.h"

#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define SIGTEST_ADDR 0x7E57D00D0000ull
static volatile const uint8_t* s_map;
static size_t s_off;                 /* two host pages past the file's end: always a whole unbacked page */
static volatile int s_after_a, s_after_b, s_clean;
static uint8_t s_img_a[64], s_img_b[64], s_img_c[64];

static void job_a(spu_context* ctx) { (void)ctx; (void)*(volatile const uint8_t*)(uintptr_t)SIGTEST_ADDR; s_after_a = 1; }
static void job_b(spu_context* ctx) { (void)ctx; (void)s_map[s_off]; s_after_b = 1; }
static void job_c(spu_context* ctx) { (void)ctx; s_clean = 1; }

static int addr_mapped(unsigned long long a)
{
#if defined(__linux__)
    FILE* m = fopen("/proc/self/maps", "r");
    char line[512];
    int hit = 0;
    if (!m) return 0;
    while (!hit && fgets(line, sizeof line, m)) {
        unsigned long long lo, hi;
        if (sscanf(line, "%llx-%llx", &lo, &hi) == 2 && lo <= a && a < hi) hit = 1;
    }
    fclose(m);
    return hit;
#else
    (void)a;
    return 0;
#endif
}

int gow2_android_sigtest_run(const char* scratch_dir)
{
    int sig = 0, ok = 1;
    uint64_t fault = 0;
    fprintf(stderr, "[SIGTEST] begin pid=%d\n", (int)getpid());
    for (int i = 0; i < 64; i++) { s_img_a[i] = (uint8_t)(0xA0 + i); s_img_b[i] = (uint8_t)(0xB0 + i); s_img_c[i] = (uint8_t)(0xC0 + i); }
    spu_workload_register(spu_workload_fingerprint(s_img_a, sizeof s_img_a), job_a, "sigtest_a");
    spu_workload_register(spu_workload_fingerprint(s_img_b, sizeof s_img_b), job_b, "sigtest_b");
    spu_workload_register(spu_workload_fingerprint(s_img_c, sizeof s_img_c), job_c, "sigtest_c");

    if (addr_mapped(SIGTEST_ADDR)) { fprintf(stderr, "[SIGTEST] fail: 0x%llx is mapped in this process\n", SIGTEST_ADDR); return 1; }
    spu_workload_dispatch(s_img_a, sizeof s_img_a, 0);
    const int got_a = spu_workload_take_last_fault(&sig, &fault);
    fprintf(stderr, "[SIGTEST] job=A recovered sig=%d fault=0x%llx returned=1\n", got_a ? sig : 0, (unsigned long long)fault);
    ok &= got_a && sig == SIGSEGV && fault == SIGTEST_ADDR && !s_after_a;

    char path[1024];
    snprintf(path, sizeof path, "%s/sigtest.bin", scratch_dir);
    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
    uint8_t page[4096];
    memset(page, 0x5A, sizeof page);
    if (fd < 0 || write(fd, page, sizeof page) != (ssize_t)sizeof page) { fprintf(stderr, "[SIGTEST] fail: cannot write %s\n", path); return 1; }
    void* m = mmap(NULL, 65536, PROT_READ, MAP_SHARED, fd, 0);
    close(fd);
    if (m == MAP_FAILED) { fprintf(stderr, "[SIGTEST] fail: mmap\n"); return 1; }
    s_map = (volatile const uint8_t*)m;
    s_off = (size_t)sysconf(_SC_PAGESIZE) * 2;   /* 8 KB on the 4 KB-page phone, 32 KB on a 16 KB Mac */
    sig = 0; fault = 0;
    spu_workload_dispatch(s_img_b, sizeof s_img_b, 0);
    const int got_b = spu_workload_take_last_fault(&sig, &fault);
    const int in_range = fault >= (uint64_t)(uintptr_t)m + 4096 && fault < (uint64_t)(uintptr_t)m + 65536;
    fprintf(stderr, "[SIGTEST] job=B recovered sig=%d fault=0x%llx in_range=%d returned=1\n", got_b ? sig : 0,
            (unsigned long long)fault, in_range);
    ok &= got_b && sig == SIGBUS && in_range && !s_after_b;
    munmap(m, 65536);
    unlink(path);

    spu_workload_dispatch(s_img_c, sizeof s_img_c, 0);
    ok &= s_clean && !spu_workload_take_last_fault(&sig, &fault);
    fprintf(stderr, "[SIGTEST] job=C clean %s\n", s_clean ? "ok" : "FAIL");
    fprintf(stderr, ok ? "[SIGTEST] pass\n" : "[SIGTEST] fail\n");
    return ok ? 0 : 1;
}
