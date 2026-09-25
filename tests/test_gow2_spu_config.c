/* gow2_spu_register: nothing registers before main() (no static constructor),
 * and the env -> config -> registration semantics stay exactly the ones the
 * constructor had. */
#include "gow2_spu_register.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct spu_context spu_context;
static int g_recomp[7];
static char g_names[16][32];
static int g_nnames, g_begin;
static int g_fail;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); g_fail++; } } while (0)

void spu_begin_image(int id) { (void)id; g_begin++; }
void spu_workload_register_image(uint64_t fp, void (*fn)(spu_context*), const char* name, int id)
{ (void)fp; (void)fn; (void)id; snprintf(g_names[g_nnames++], sizeof g_names[0], "%s", name); }
void spu_workload_register_raw_image(uint64_t fp, void (*fn)(spu_context*), const char* name,
                                     uint32_t base, int id)
{ (void)fp; (void)fn; (void)base; (void)id; snprintf(g_names[g_nnames++], sizeof g_names[0], "%s", name); }
#define STUB(n) void spu##n##_spu_recomp_register(void) { g_recomp[n]++; }
STUB(0) STUB(1) STUB(2) STUB(3) STUB(4) STUB(5) STUB(6)
void spu0_spu_func_00003070(spu_context* c) { (void)c; }
void spu1_spu_func_00003050(spu_context* c) { (void)c; }
void spu2_spu_func_00004080(spu_context* c) { (void)c; }
void spu3_spu_func_00004080(spu_context* c) { (void)c; }
void spu4_spu_func_00003050(spu_context* c) { (void)c; }
void spu5_spu_func_00003070(spu_context* c) { (void)c; }
void spu6_spu_func_00000A00(spu_context* c) { (void)c; }

static void clear_env(void)
{
    static const char* k[] = { "PS3_SPU0", "PS3_SPU1", "PS3_SPU2", "PS3_SPU3", "PS3_SPU4",
                               "PS3_SPU5", "PS3_SPU6", "PS3_SPU_ALL" };
    for (size_t i = 0; i < sizeof k / sizeof k[0]; i++) unsetenv(k[i]);
}
static void reset(void) { memset(g_recomp, 0, sizeof g_recomp); g_nnames = 0; g_begin = 0; }
static int has(const char* n) { for (int i = 0; i < g_nnames; i++) if (!strcmp(g_names[i], n)) return 1; return 0; }

int main(void)
{
    gow2_spu_config c;
    CHECK(g_nnames == 0 && g_recomp[0] == 0 && g_begin == 0);   /* no constructor ran */

    clear_env();
    gow2_spu_config_from_env(&c);
    CHECK(c.spu0 == 1 && c.spu1 == 0 && c.spu2 == 0 && c.spu3 == 0 && c.spu4 == 0 && c.spu5 == 0 && c.spu6 == 1);
    gow2_register_spu_workloads(&c);
    CHECK(g_nnames == 2 && has("gow2_spu0") && has("gow2_spu6"));
    CHECK(g_recomp[0] == 1 && g_recomp[1] == 1 && g_recomp[2] == 2 && g_recomp[6] == 1);  /* spu2 also under image 7 */

    reset(); clear_env();
    setenv("PS3_SPU1", "1", 1); setenv("PS3_SPU6", "1", 1);          /* the play recipe */
    gow2_spu_config_from_env(&c);
    gow2_register_spu_workloads(&c);
    CHECK(g_nnames == 3 && has("gow2_spu1"));

    clear_env(); setenv("PS3_SPU1", "0", 1);                          /* presence semantics kept */
    gow2_spu_config_from_env(&c);
    CHECK(c.spu1 == 1);
    clear_env(); setenv("PS3_SPU0", "0", 1); setenv("PS3_SPU6", "0", 1);
    gow2_spu_config_from_env(&c);
    CHECK(c.spu0 == 0 && c.spu6 == 0);
    clear_env(); setenv("PS3_SPU6", "", 1);
    gow2_spu_config_from_env(&c);
    CHECK(c.spu6 == 0);
    clear_env(); setenv("PS3_SPU_ALL", "1", 1); setenv("PS3_SPU6", "0", 1);
    gow2_spu_config_from_env(&c);
    CHECK(c.spu0 && c.spu1 && c.spu2 && c.spu3 && c.spu4 && c.spu5 && c.spu6);

    reset();
    gow2_register_spu_workloads(NULL);
    CHECK(g_nnames == 0 && g_recomp[0] == 0);

    printf(g_fail ? "test_gow2_spu_config: FAIL %d\n" : "test_gow2_spu_config: PASS\n", g_fail);
    return g_fail ? 1 : 0;
}
