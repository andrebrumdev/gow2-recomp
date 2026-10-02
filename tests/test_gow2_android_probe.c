/* gow2_android_probe on the Mac: the probe/ path guard (.., probex, symlink escape), ops 6/7/9/12,
 * the restore check (scratch: hashes, count, APPWRITE beside; live: read-only) and the drill's
 * manifest line, all against shasum-independent recomputation in the test. */
#include "gow2_android_probe.h"
#include "gow2_sha256.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int g_fail;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); g_fail++; } } while (0)
static char g_log[1 << 16];
static FILE* logf_open(void) { memset(g_log, 0, sizeof g_log); return fmemopen(g_log, sizeof g_log - 1, "w"); }
static void put(const char* path, const char* s) { FILE* f = fopen(path, "wb"); fputs(s, f); fclose(f); }
static void mk(const char* p) { char c[1024]; snprintf(c, sizeof c, "mkdir -p '%s'", p); if (system(c)) {} }

int main(void)
{
    char root[] = "/tmp/g2probeXXXXXX"; if (!mkdtemp(root)) return 1;
    char rr[1024]; realpath(root, rr);
    char p[2048], q[2048], hex[65], line[512];
    snprintf(p, sizeof p, "%s/probe", rr); mk(p);
    snprintf(p, sizeof p, "%s/savedata", rr); mk(p);
    /* guard */
    snprintf(p, sizeof p, "%s/probe/a/b/new.bin", rr); CHECK(gow2_probe_path_ok(rr, p) == 1);
    snprintf(p, sizeof p, "%s/probe/../savedata/x", rr); CHECK(gow2_probe_path_ok(rr, p) == 0);
    snprintf(p, sizeof p, "%s/probex/x", rr); CHECK(gow2_probe_path_ok(rr, p) == 0);
    snprintf(p, sizeof p, "%s/probe", rr); CHECK(gow2_probe_path_ok(rr, p) == 0);
    snprintf(p, sizeof p, "%s/probe/lnk", rr); snprintf(q, sizeof q, "%s/savedata", rr); CHECK(symlink(q, p) == 0);
    snprintf(p, sizeof p, "%s/probe/lnk/x", rr); CHECK(gow2_probe_path_ok(rr, p) == 0);
    /* op 6 then 9: files written, logged hashes equal the files */
    gow2_android_args a; memset(&a, 0, sizeof a); strcpy(a.run, "t1"); strcpy(a.probe, "transport"); strcpy(a.root, "external");
    gow2_android_paths paths; memset(&paths, 0, sizeof paths);
    FILE* L = logf_open(); a.op = 6; CHECK(gow2_probe_run(&a, rr, &paths, L) == 0); fclose(L);
    snprintf(p, sizeof p, "%s/probe/app_save/DATA.BIN", rr); CHECK(gow2_sha256_file(p, hex) == 0);
    snprintf(line, sizeof line, "[PROBE] run=t1 op=6 file=DATA.BIN sha256=%s\n", hex); CHECK(strstr(g_log, line) != NULL);
    struct stat st; CHECK(stat(p, &st) == 0 && st.st_size == 256 * 1024);
    CHECK(strstr(g_log, "[PROBE] run=t1 op=6 count=2\n") && strstr(g_log, "[PROBE] run=t1 done op=6 rc=0\n"));
    char h6[65]; strcpy(h6, hex);
    L = logf_open(); a.op = 9; CHECK(gow2_probe_run(&a, rr, &paths, L) == 0); fclose(L);
    CHECK(gow2_sha256_file(p, hex) == 0 && strcmp(hex, h6) != 0);
    /* op 7 / 12 read shell-written files */
    snprintf(p, sizeof p, "%s/probe/a/b", rr); mk(p);
    snprintf(p, sizeof p, "%s/probe/a/b/f1m.bin", rr); put(p, "one"); gow2_sha256_file(p, h6);
    snprintf(p, sizeof p, "%s/probe/a/b/f64m.bin", rr); put(p, "sixtyfour");
    snprintf(p, sizeof p, "%s/probe/tree/l1_0/l2_0/l3_0", rr); mk(p);
    snprintf(p, sizeof p, "%s/probe/tree/l1_0/l2_0/l3_0/f.bin", rr); put(p, "leaf");
    L = logf_open(); a.op = 12; CHECK(gow2_probe_run(&a, rr, &paths, L) == 0); fclose(L);
    snprintf(line, sizeof line, "[PROBE] run=t1 op=12 file=a/b/f1m.bin sha256=%s\n", h6); CHECK(strstr(g_log, line) != NULL);
    CHECK(strstr(g_log, "op=12 file=tree/l1_0/l2_0/l3_0/f.bin sha256=") != NULL);
    /* restore check: scratch dir */
    snprintf(paths.save_parent, sizeof paths.save_parent, "%s", rr);
    snprintf(paths.savedata, sizeof paths.savedata, "%s/savedata", rr);
    snprintf(p, sizeof p, "%s/probe/restore_check/s1/SAVE0", rr); mk(p);
    snprintf(p, sizeof p, "%s/probe/restore_check/s1/SAVE0/DATA.BIN", rr); put(p, "save"); gow2_sha256_file(p, h6);
    memset(&a, 0, sizeof a); strcpy(a.run, "t2"); strcpy(a.probe, "restore_check"); strcpy(a.dir, "s1");
    L = logf_open(); CHECK(gow2_probe_run(&a, NULL, &paths, L) == 0); fclose(L);
    snprintf(line, sizeof line, "[RESTORECHK] run=t2 SAVE0/DATA.BIN %s\n", h6); CHECK(strstr(g_log, line) != NULL);
    CHECK(strstr(g_log, "[RESTORECHK] run=t2 count=1\n") && strstr(g_log, "[PROBE] run=t2 appwrite APPWRITE.BIN "));
    snprintf(p, sizeof p, "%s/probe/restore_check/s1/APPWRITE.BIN", rr); CHECK(access(p, F_OK) == 0);
    /* restore check: live is read-only (nothing written beside) */
    snprintf(p, sizeof p, "%s/savedata/S/DATA.BIN", rr); snprintf(q, sizeof q, "%s/savedata/S", rr); mk(q); put(p, "live");
    strcpy(a.dir, "live"); L = logf_open(); CHECK(gow2_probe_run(&a, NULL, &paths, L) == 0); fclose(L);
    CHECK(strstr(g_log, "[RESTORECHK] run=t2 count=1\n") && !strstr(g_log, "appwrite"));
    snprintf(p, sizeof p, "%s/savedata/APPWRITE.BIN", rr); CHECK(access(p, F_OK) != 0);
    /* drill: no manifest -> INCOMPLETE line, done rc=0 */
    snprintf(paths.data, sizeof paths.data, "%s/probe/drill/data", rr);
    memset(&a, 0, sizeof a); strcpy(a.run, "t3"); strcpy(a.probe, "drill");
    L = logf_open(); gow2_probe_run(&a, NULL, &paths, L); fclose(L);
    CHECK(strstr(g_log, "[PROBE] run=t3 drill manifest INCOMPLETE") != NULL && strstr(g_log, "[PROBE] run=t3 done op=drill rc=0"));
    char cmd[1100]; snprintf(cmd, sizeof cmd, "rm -rf '%s'", rr); if (system(cmd)) {}
    printf(g_fail ? "test_gow2_android_probe: FAIL\n" : "test_gow2_android_probe: PASS\n");
    return g_fail ? 1 : 0;
}
