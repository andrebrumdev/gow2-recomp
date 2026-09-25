/* iOS host policies (P2): thermal cap, provisioning expiry, last save, memory ceiling. */
#include "gow2_ios_ui_policy.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

static int g_fail;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); g_fail++; } } while (0)

static void test_thermal_cap(void)
{
    CHECK(gow2_ios_thermal_fps_cap(0, NULL) == 0);
    CHECK(gow2_ios_thermal_fps_cap(1, NULL) == 0);
    CHECK(gow2_ios_thermal_fps_cap(2, NULL) == 20);
    CHECK(gow2_ios_thermal_fps_cap(3, NULL) == 15);
    CHECK(gow2_ios_thermal_fps_cap(-1, NULL) == 0);
    CHECK(gow2_ios_thermal_fps_cap(3, "0") == 0);
    CHECK(gow2_ios_thermal_fps_cap(2, "24:18") == 24 && gow2_ios_thermal_fps_cap(3, "24:18") == 18);
    CHECK(gow2_ios_thermal_fps_cap(2, "junk") == 20 && gow2_ios_thermal_fps_cap(2, "99:1") == 20);
    CHECK(gow2_ios_thermal_fps_cap(2, "24:18x") == 20 && gow2_ios_thermal_fps_cap(2, "") == 20);
}

static void test_provision_expiry(void)
{
    static const char blob[] =
        "\x30\x82\x2a\x00junk\0\0<?xml version=\"1.0\"?><plist><dict>"
        "<key>CreationDate</key>\n\t<date>2026-09-25T12:00:00Z</date>"
        "<key>ExpirationDate</key>\n\t<date>2026-10-02T12:00:00Z</date>"
        "</dict></plist>\0\x01\x02";
    CHECK(gow2_ios_provision_expiry(blob, sizeof blob - 1) == 1790942400LL);
    CHECK(gow2_ios_provision_expiry(blob, 40) == 0);                            /* truncated */
    CHECK(gow2_ios_provision_expiry("<key>ExpirationDate</key><date>2026-13-02T12:00:00Z</date>", 58) == 0);
    CHECK(gow2_ios_provision_expiry("<key>Other</key><date>2026-10-02T12:00:00Z</date>", 49) == 0);
    CHECK(gow2_ios_provision_expiry(NULL, 10) == 0);
}

static void touch_file(const char* path, long long mtime)
{
    FILE* f = fopen(path, "wb");
    struct timeval tv[2];
    if (f) { fputs("x", f); fclose(f); }
    tv[0].tv_sec = tv[1].tv_sec = (time_t)mtime;
    tv[0].tv_usec = tv[1].tv_usec = 0;
    utimes(path, tv);
}

static void test_latest_save(void)
{
    char root[] = "/tmp/g2t_saveXXXXXX", a[256], b[256], fa[300], fb[300], top[300];
    CHECK(mkdtemp(root) != NULL);
    CHECK(gow2_ios_latest_save_mtime(root) == 0);                               /* no saves */
    snprintf(a, sizeof a, "%s/BCUS98229_GOW2", root);
    snprintf(b, sizeof b, "%s/BCUS98229_SYS", root);
    mkdir(a, 0755);
    mkdir(b, 0755);
    snprintf(fa, sizeof fa, "%s/SAVE.DAT", a);
    snprintf(fb, sizeof fb, "%s/PARAM.SFO", b);
    snprintf(top, sizeof top, "%s/loose.bin", root);
    touch_file(fa, 1790000000LL);
    touch_file(fb, 1790000500LL);
    touch_file(top, 1799999999LL);                                            /* not a save dir: ignored */
    CHECK(gow2_ios_latest_save_mtime(root) == 1790000500LL);
    CHECK(gow2_ios_latest_save_mtime("/nonexistent/g2") == 0);
    CHECK(gow2_ios_latest_save_mtime(NULL) == 0);
    unlink(fa); unlink(fb); unlink(top); rmdir(a); rmdir(b); rmdir(root);
}

static void test_memory_ceiling(void)
{
    CHECK(gow2_ios_memory_ceiling_mb(733ull << 20, 3363ull << 20) == 4096);
    CHECK(gow2_ios_memory_ceiling_mb(0, 0) == 0);
}

int main(void)
{
    test_thermal_cap();
    test_provision_expiry();
    test_latest_save();
    test_memory_ceiling();
    printf(g_fail ? "test_gow2_ios_ui_policy: FAIL %d\n" : "test_gow2_ios_ui_policy: PASS\n", g_fail);
    return g_fail ? 1 : 0;
}
