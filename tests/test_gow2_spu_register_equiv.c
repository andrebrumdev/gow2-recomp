/* gow2_spu_register: the explicit registration (config from env, then
 * gow2_register_spu_workloads(&cfg)) registers EXACTLY the images the old
 * static constructor registered, for every combination of the switches.
 *
 * The oracle is the old body of gow2_register_spu_workloads(void), copied
 * verbatim (only renamed to old_register) from gow2-recomp 488df7a -- the last
 * version with the constructor. Each of the 8 variables takes one of 5 values
 * (unset, "", "0", "1", "x"): 5^8 = 390625 environments, each compared on the
 * ordered list of workload registrations (name, fingerprint, entry, LS base,
 * image id) and on the ordered list of spu_begin_image / spuN_spu_recomp_register
 * calls. */
#include "gow2_spu_register.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct spu_context spu_context;
typedef void (*spu_lifted_entry_fn)(spu_context*);

#define MAXEV 64
typedef struct { char ev[MAXEV][96]; int n; } trace;
static trace* g_cur;

static void rec(const char* s)
{
    if (g_cur->n < MAXEV) snprintf(g_cur->ev[g_cur->n++], sizeof g_cur->ev[0], "%s", s);
}

void spu_begin_image(int id) { char b[96]; snprintf(b, sizeof b, "begin %d", id); rec(b); }
void spu_workload_register_image(uint64_t fp, spu_lifted_entry_fn fn, const char* name, int id)
{
    char b[96];
    snprintf(b, sizeof b, "img %s %016llx %p %d", name, (unsigned long long)fp, (void*)fn, id);
    rec(b);
}
void spu_workload_register_raw_image(uint64_t fp, spu_lifted_entry_fn fn, const char* name,
                                     uint32_t base, int id)
{
    char b[96];
    snprintf(b, sizeof b, "raw %s %016llx %p %x %d", name, (unsigned long long)fp, (void*)fn, base, id);
    rec(b);
}
#define STUB(n) void spu##n##_spu_recomp_register(void) { rec("recomp " #n); }
STUB(0) STUB(1) STUB(2) STUB(3) STUB(4) STUB(5) STUB(6)
void spu0_spu_func_00003070(spu_context* c) { (void)c; }
void spu1_spu_func_00003050(spu_context* c) { (void)c; }
void spu2_spu_func_00004080(spu_context* c) { (void)c; }
void spu3_spu_func_00004080(spu_context* c) { (void)c; }
void spu4_spu_func_00003050(spu_context* c) { (void)c; }
void spu5_spu_func_00003070(spu_context* c) { (void)c; }
void spu6_spu_func_00000A00(spu_context* c) { (void)c; }

/* ---- oracle: old gow2_register_spu_workloads(void), comments trimmed ---- */
static void old_register(void)
{
    spu_begin_image(1); spu0_spu_recomp_register();
    spu_begin_image(2); spu1_spu_recomp_register();
    spu_begin_image(3); spu2_spu_recomp_register();
    spu_begin_image(4); spu3_spu_recomp_register();
    spu_begin_image(5); spu4_spu_recomp_register();
    spu_begin_image(6); spu5_spu_recomp_register();
    spu_begin_image(7); spu6_spu_recomp_register();
    spu2_spu_recomp_register();
    spu_begin_image(0);
    if (!(getenv("PS3_SPU0") && getenv("PS3_SPU0")[0] == '0'))
        spu_workload_register_image(0xDE6DC3A5EA2BE487ull, spu0_spu_func_00003070, "gow2_spu0", 1);
    if (getenv("PS3_SPU_ALL") || getenv("PS3_SPU1"))
        spu_workload_register_image(0x2A5C4E67A14505B8ull, spu1_spu_func_00003050, "gow2_spu1", 2);
    if (getenv("PS3_SPU_ALL") || getenv("PS3_SPU2"))
        spu_workload_register_image(0xABCD0BA4D18DED49ull, spu2_spu_func_00004080, "gow2_spu2", 3);
    if (getenv("PS3_SPU_ALL") || getenv("PS3_SPU3"))
        spu_workload_register_image(0xED6A0C318DEB46C6ull, spu3_spu_func_00004080, "gow2_spu3", 4);
    if (getenv("PS3_SPU_ALL") || getenv("PS3_SPU4"))
        spu_workload_register_image(0x9527C889B1945669ull, spu4_spu_func_00003050, "gow2_spu4", 5);
    if (getenv("PS3_SPU_ALL") || getenv("PS3_SPU5"))
        spu_workload_register_image(0x3512A7E99D34E0FFull, spu5_spu_func_00003070, "gow2_spu5", 6);
    {
        const char* e = getenv("PS3_SPU6");
        int on = getenv("PS3_SPU_ALL") || !e || (e[0] && e[0] != '0');
        if (on)
            spu_workload_register_raw_image(0xCEDB9A67A0C3A305ull, spu6_spu_func_00000A00,
                                            "gow2_spu6", 0xA00, 7);
    }
}

int main(void)
{
    static const char* keys[8] = { "PS3_SPU0", "PS3_SPU1", "PS3_SPU2", "PS3_SPU3",
                                   "PS3_SPU4", "PS3_SPU5", "PS3_SPU6", "PS3_SPU_ALL" };
    static const char* vals[5] = { NULL, "", "0", "1", "x" };
    static trace told, tnew;
    long combos = 0, bad = 0, workloads_seen[8] = { 0 };

    for (long m = 0; m < 390625; m++) {           /* 5^8 */
        long r = m;
        for (int k = 0; k < 8; k++, r /= 5) {
            const char* v = vals[r % 5];
            if (v) setenv(keys[k], v, 1); else unsetenv(keys[k]);
        }
        told.n = 0; g_cur = &told; old_register();
        gow2_spu_config cfg;
        tnew.n = 0; g_cur = &tnew;
        gow2_spu_config_from_env(&cfg);
        gow2_register_spu_workloads(&cfg);
        combos++;
        int same = told.n == tnew.n;
        for (int i = 0; same && i < told.n; i++) same = !strcmp(told.ev[i], tnew.ev[i]);
        if (!same) {
            if (bad++ < 5) {
                printf("FAIL env combo %ld:", m);
                for (int k = 0; k < 8; k++) { const char* v = getenv(keys[k]); printf(" %s=%s", keys[k], v ? v : "(unset)"); }
                printf("\n");
            }
        }
        int nw = 0;
        for (int i = 0; i < told.n; i++) if (!strncmp(told.ev[i], "img", 3) || !strncmp(told.ev[i], "raw", 3)) nw++;
        workloads_seen[nw]++;
    }
    /* The matrix must actually exercise every count of enabled workloads 0..7. */
    for (int i = 0; i < 8; i++) if (!workloads_seen[i]) { printf("FAIL: no combo with %d workloads\n", i); bad++; }
    printf("test_gow2_spu_register_equiv: %ld env combos, %ld mismatches -> %s\n",
           combos, bad, bad ? "FAIL" : "PASS");
    return bad ? 1 : 0;
}
