/* gow2_env_file: the iOS host's configuration file (bundled gow2.env and the
 * optional Documents/gow2.override.env). */
#include "gow2_env_file.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int g_fail;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); g_fail++; } } while (0)
static int eq(const char* k, const char* v) { const char* g = getenv(k); return g && strcmp(g, v) == 0; }

static void test_env_text_odd_lines(void)
{
    static const char* keys[] = { "G2T_A", "G2T_B", "G2T_EMPTY", "G2T_SPACE", "G2T_KEEP", "G2T_LAST", "G2T_LEAD" };
    for (size_t i = 0; i < sizeof keys / sizeof keys[0]; i++) unsetenv(keys[i]);
    setenv("G2T_KEEP", "launch", 1);
    const char* text =
        "# comment\n"
        "\n"
        "G2T_A=1\n"
        "G2T_B=auto\r\n"
        "G2T_EMPTY=\n"
        "G2T_SPACE=a b\n"
        "bad line\n"
        " G2T_LEAD=1\n"
        "g2t_lower=1\n"
        "=novalue\n"
        "G2T_KEEP=file\n"
        "G2T_LAST=no-newline";
    int a = -1, r = -1;
    CHECK(gow2_env_apply_text(text, 0, &a, &r) == 0);
    CHECK(eq("G2T_A", "1"));
    CHECK(eq("G2T_B", "auto"));
    CHECK(eq("G2T_EMPTY", ""));
    CHECK(eq("G2T_SPACE", "a b"));
    CHECK(eq("G2T_KEEP", "launch"));        /* the launch environment wins */
    CHECK(eq("G2T_LAST", "no-newline"));
    CHECK(getenv("G2T_LEAD") == NULL);
    CHECK(a == 5);
    CHECK(r == 4);
}

static void test_overwrite(void)
{
    int a = -1, r = -1;
    setenv("G2T_KEEP", "launch", 1);
    CHECK(gow2_env_apply_text("G2T_KEEP=file\n", 1, &a, &r) == 0);
    CHECK(eq("G2T_KEEP", "file") && a == 1 && r == 0);
    CHECK(gow2_env_apply_text(NULL, 0, &a, &r) == -1);
}

static void test_file(void)
{
    char path[] = "/tmp/g2t_envXXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    const char body[] = "G2T_FILE=ok\n";
    CHECK(write(fd, body, sizeof body - 1) == (ssize_t)(sizeof body - 1));
    close(fd);
    int a = -1, r = -1;
    unsetenv("G2T_FILE");
    CHECK(gow2_env_apply_file(path, 0, &a, &r) == 0 && eq("G2T_FILE", "ok") && a == 1);
    unlink(path);
    CHECK(gow2_env_apply_file("/nonexistent/g2t.env", 0, &a, &r) == -1 && a == 0 && r == 0);

    char big[] = "/tmp/g2t_bigXXXXXX";
    fd = mkstemp(big);
    char line[1024];
    memset(line, 'x', sizeof line);
    for (int i = 0; i < 70; i++) CHECK(write(fd, line, sizeof line) == (ssize_t)sizeof line);
    close(fd);
    CHECK(gow2_env_apply_file(big, 0, &a, &r) == -1);   /* > 64 KB is not a config file */
    unlink(big);
}

int main(void)
{
    test_env_text_odd_lines();
    test_overwrite();
    test_file();
    printf(g_fail ? "test_gow2_env_file: FAIL %d\n" : "test_gow2_env_file: PASS\n", g_fail);
    return g_fail ? 1 : 0;
}
