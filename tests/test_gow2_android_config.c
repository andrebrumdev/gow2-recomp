/* gow2_android_config: argv from the launch intent, env precedence (intent > override file >
 * bundled asset), path resolution (external/internal, drill layout) and export. */
#include "gow2_android_config.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_fail;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); g_fail++; } } while (0)
static int eq(const char* k, const char* v) { const char* g = getenv(k); return g && strcmp(g, v) == 0; }
static int parse(gow2_android_args* a, const char* const* v, int n) { return gow2_android_args_parse(n, (char**)v, a); }

int main(void)
{
    gow2_android_args a;
    { const char* v[] = {"app"}; CHECK(parse(&a, v, 1) == 0 && strcmp(a.run, "-") == 0 && a.probe[0] == 0); }
    { const char* v[] = {"app", "--run=p6ext1", "--probe=transport", "--op=6", "--root=internal"};
      CHECK(parse(&a, v, 5) == 0 && a.op == 6 && strcmp(a.root, "internal") == 0 && strcmp(a.run, "p6ext1") == 0); }
    { const char* v[] = {"app", "--probe=transport", "--op=6"}; CHECK(parse(&a, v, 3) == -1); }          /* no --root */
    { const char* v[] = {"app", "--probe=transport", "--op=13", "--root=external"}; CHECK(parse(&a, v, 4) == -1); }
    { const char* v[] = {"app", "--probe=restore_check", "--dir=../x"}; CHECK(parse(&a, v, 3) == -1); }
    { const char* v[] = {"app", "--probe=restore_check", "--dir=live", "--txnroot=drill", "--save-root=internal"};
      CHECK(parse(&a, v, 5) == 0 && a.txn_drill == 1 && strcmp(a.dir, "live") == 0); }
    { const char* v[] = {"app", "--root=sdcard"}; CHECK(parse(&a, v, 2) == -1); }
    { const char* v[] = {"app", "--bogus"}; CHECK(parse(&a, v, 2) == -1 && strstr(a.err, "unknown") != NULL); }
    { const char* v[] = {"app", "--env=lower=1"}; CHECK(parse(&a, v, 2) == -1); }
    /* env precedence */
    unsetenv("G2A_X"); unsetenv("G2A_Y"); unsetenv("G2A_Z");
    char ov[] = "/tmp/g2aovXXXXXX"; int fd = mkstemp(ov); FILE* f = fdopen(fd, "w");
    fputs("G2A_X=override\nG2A_Y=override\n", f); fclose(f);
    { const char* v[] = {"app", "--env=G2A_X=intent"}; CHECK(parse(&a, v, 2) == 0); }
    int n = 0;
    CHECK(gow2_android_env_apply(&a, ov, "G2A_X=asset\nG2A_Y=asset\nG2A_Z=asset\n", &n) == 0);
    CHECK(eq("G2A_X", "intent") && eq("G2A_Y", "override") && eq("G2A_Z", "asset"));
    CHECK(gow2_android_env_apply(&a, "/nonexistent/override.env", NULL, &n) == -1);
    remove(ov);
    /* paths */
    gow2_android_paths p;
    { const char* v[] = {"app"}; parse(&a, v, 1); }
    unsetenv("GOW2_ANDROID_DATA_ROOT"); unsetenv("GOW2_ANDROID_SAVE_ROOT");
    CHECK(gow2_android_paths_resolve(&a, "/ext/files", "/int/files", &p) == 0);
    CHECK(strcmp(p.data, "/ext/files") == 0 && strcmp(p.savedata, "/ext/files/savedata") == 0);
    CHECK(strcmp(p.usrdir, "/ext/files/USRDIR") == 0 && strcmp(p.vkcache, "/int/files/vkcache") == 0);
    setenv("GOW2_ANDROID_DATA_ROOT", "internal", 1); setenv("GOW2_ANDROID_SAVE_ROOT", "external", 1);
    CHECK(gow2_android_paths_resolve(&a, "/ext/files", "/int/files", &p) == 0);
    CHECK(strcmp(p.eboot, "/int/files/EBOOT.ELF") == 0 && strcmp(p.savedata, "/ext/files/savedata") == 0);
    { const char* v[] = {"app", "--txnroot=drill", "--data-root=external", "--save-root=internal"}; parse(&a, v, 4); }
    CHECK(gow2_android_paths_resolve(&a, "/ext/files", "/int/files", &p) == 0);
    CHECK(strcmp(p.data, "/ext/files/probe/drill/data") == 0 && strcmp(p.savedata, "/int/files/probe/drill/savedata") == 0);
    CHECK(gow2_android_paths_resolve(&a, NULL, "/int/files", &p) == -1);          /* external storage absent */
    setenv("GOW2_ANDROID_DATA_ROOT", "cloud", 1); { const char* v[] = {"app"}; parse(&a, v, 1); }
    CHECK(gow2_android_paths_resolve(&a, "/ext/files", "/int/files", &p) == -1);
    setenv("GOW2_ANDROID_DATA_ROOT", "external", 1);
    CHECK(gow2_android_paths_resolve(&a, "/ext/files", "/int/files", &p) == 0);
    unsetenv("HOME"); setenv("PS3_VFS_ROOT", "/elsewhere", 1);
    gow2_android_paths_export(&p);
    CHECK(eq("PS3_VFS_ROOT", "/ext/files/USRDIR") && eq("HOME", "/int/files") && eq("GOW2_EBOOT", "/ext/files/EBOOT.ELF"));
    printf(g_fail ? "test_gow2_android_config: FAIL\n" : "test_gow2_android_config: PASS\n");
    return g_fail ? 1 : 0;
}
