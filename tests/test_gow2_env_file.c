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
    CHECK(getenv("G2T_LEAD") == NULL);      /* indented ASSIGNMENT: still rejected */
    CHECK(a == 5);
    CHECK(r == 4);
}

static void test_indented_comment(void)
{
    /* An indented '#' is still a comment (skipped, not counted as rejected);
     * only an indented KEY=VALUE is rejected (test_env_text_odd_lines' " G2T_LEAD=1"). */
    unsetenv("G2T_IC");
    const char* text =
        "  # indented comment\n"
        "\t# tab-indented comment\n"
        "   \n"                 /* whitespace-only line: also skipped, not rejected */
        "G2T_IC=1\n";
    int a = -1, r = -1;
    CHECK(gow2_env_apply_text(text, 0, &a, &r) == 0);
    CHECK(eq("G2T_IC", "1"));
    CHECK(a == 1);
    CHECK(r == 0);
}

static void test_duplicate_keys(void)
{
    /* overwrite == 0: the first value assigned during this call wins. */
    unsetenv("G2T_DUP");
    int a = -1, r = -1;
    CHECK(gow2_env_apply_text("G2T_DUP=first\nG2T_DUP=second\n", 0, &a, &r) == 0);
    CHECK(eq("G2T_DUP", "first"));
    CHECK(a == 1 && r == 0);        /* the 2nd line is neither applied nor rejected */

    /* overwrite == 1: the last value in the text wins. */
    unsetenv("G2T_DUP");
    a = -1; r = -1;
    CHECK(gow2_env_apply_text("G2T_DUP=first\nG2T_DUP=second\n", 1, &a, &r) == 0);
    CHECK(eq("G2T_DUP", "second"));
    CHECK(a == 2 && r == 0);
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

static void test_file_nul_byte(void)
{
    /* An embedded NUL is not text -- reject outright rather than silently
     * truncating the config at the NUL (a hand-edited/corrupted file must
     * fail loudly, not apply a prefix of what the user wrote). */
    char path[] = "/tmp/g2t_nulXXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    const char body[] = "G2T_NUL_A=1\n\0G2T_NUL_B=2\n";
    CHECK(write(fd, body, sizeof body - 1) == (ssize_t)(sizeof body - 1));
    close(fd);
    unsetenv("G2T_NUL_A");
    unsetenv("G2T_NUL_B");
    int a = -1, r = -1;
    CHECK(gow2_env_apply_file(path, 0, &a, &r) == -1);
    CHECK(getenv("G2T_NUL_A") == NULL);     /* nothing applied, not even the prefix */
    unlink(path);
}

static void test_file_read_error(void)
{
    /* fopen() succeeds on a directory (at least on Darwin/Linux) but fread()
     * fails with EISDIR; that must surface as -1, not as a 0-byte "empty
     * config" success. */
    char dir[] = "/tmp/g2t_dirXXXXXX";
    CHECK(mkdtemp(dir) != NULL);
    int a = -1, r = -1;
    CHECK(gow2_env_apply_file(dir, 0, &a, &r) == -1);
    rmdir(dir);
}

static void test_file_oversize_line(void)
{
    /* One line whose value is >= 4096 bytes, inside a file well under the
     * 64 KB cap: that single line is rejected, the others still apply. */
    char path[] = "/tmp/g2t_ovlXXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    char huge_val[5000];
    memset(huge_val, 'x', sizeof huge_val);
    char before[] = "G2T_OVL_BEFORE=1\n";
    char after[] = "\nG2T_OVL_AFTER=2\n";
    CHECK(write(fd, before, sizeof before - 1) == (ssize_t)(sizeof before - 1));
    CHECK(write(fd, "G2T_OVL_BIG=", 12) == 12);
    CHECK(write(fd, huge_val, sizeof huge_val) == (ssize_t)sizeof huge_val);
    CHECK(write(fd, after, sizeof after - 1) == (ssize_t)(sizeof after - 1));
    close(fd);
    unsetenv("G2T_OVL_BEFORE");
    unsetenv("G2T_OVL_BIG");
    unsetenv("G2T_OVL_AFTER");
    int a = -1, r = -1;
    CHECK(gow2_env_apply_file(path, 0, &a, &r) == 0);
    CHECK(eq("G2T_OVL_BEFORE", "1"));
    CHECK(eq("G2T_OVL_AFTER", "2"));
    CHECK(getenv("G2T_OVL_BIG") == NULL);
    CHECK(a == 2 && r == 1);
    unlink(path);
}

int main(void)
{
    test_env_text_odd_lines();
    test_indented_comment();
    test_duplicate_keys();
    test_overwrite();
    test_file();
    test_file_nul_byte();
    test_file_read_error();
    test_file_oversize_line();
    printf(g_fail ? "test_gow2_env_file: FAIL %d\n" : "test_gow2_env_file: PASS\n", g_fail);
    return g_fail ? 1 : 0;
}
