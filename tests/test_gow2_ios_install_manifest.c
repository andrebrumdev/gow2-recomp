/* iOS install manifest (P3): the app plays only on a complete, internally
 * consistent manifest whose files all exist with their listed sizes. */
#include "gow2_ios_install_manifest.h"

#include <CommonCrypto/CommonDigest.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int g_fail;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); g_fail++; } } while (0)

static const char* H = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
static char g_docs[64];

static void put(const char* rel, const char* body, const char* mode)
{
    char p[512];
    snprintf(p, sizeof p, "%s/%s", g_docs, rel);
    for (char* s = p + strlen(g_docs) + 1; (s = strchr(s, '/')) != NULL; s++) {
        *s = '\0';
        mkdir(p, 0755);
        *s = '/';
    }
    FILE* f = fopen(p, mode);
    if (f) { fputs(body, f); fclose(f); }
}

static gow2_install_state state(char* why, size_t cap) { return gow2_ios_install_state(g_docs, why, cap); }

/* Entry text "<size> <H> <path>" (the part after "file "). */
static void entry(char* out, size_t cap, int size, const char* path) { snprintf(out, cap, "%d %s %s", size, H, path); }

static void digest_of(const char* const* e, int n, char hex[65])
{
    CC_SHA256_CTX c;
    unsigned char d[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Init(&c);
    for (int i = 0; i < n; i++) {
        CC_SHA256_Update(&c, e[i], (CC_LONG)strlen(e[i]));
        CC_SHA256_Update(&c, "\n", 1);
    }
    CC_SHA256_Final(d, &c);
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        snprintf(hex + 2 * i, 3, "%02x", d[i]);
}

/* A manifest over entries e[0..n): set = digest of `digest_e` (NULL: e itself), end = n. */
static void manifest_of(const char* const* e, int n, const char* const* digest_e, int digest_n)
{
    char m[4096], hex[65];
    digest_of(digest_e ? digest_e : e, digest_e ? digest_n : n, hex);
    int k = snprintf(m, sizeof m, "gow2-install 1\nset %s\n", hex);
    for (int i = 0; i < n; i++)
        k += snprintf(m + k, sizeof m - (size_t)k, "file %s\n", e[i]);
    snprintf(m + k, sizeof m - (size_t)k, "end %d\n", n);
    put(GOW2_INSTALL_MANIFEST_NAME, m, "wb");
}

static void manifest(const char* text) { put(GOW2_INSTALL_MANIFEST_NAME, text, "wb"); }

int main(void)
{
    char why[256], m[4096], p[512], hex[65];
    char eb[128], ps[128], mc[128];
    snprintf(g_docs, sizeof g_docs, "/tmp/g2t_manifestXXXXXX");
    if (mkdtemp(g_docs) == NULL) { printf("mkdtemp failed\n"); return 1; }
    entry(eb, sizeof eb, 4, "EBOOT.ELF");
    entry(ps, sizeof ps, 5, "USRDIR/gow2.psarc");
    entry(mc, sizeof mc, 1, "movie_cache/a.m2v");
    const char* good[] = { eb, ps, mc };

    CHECK(state(why, sizeof why) == GOW2_INSTALL_MISSING);                       /* fresh container */
    CHECK(gow2_ios_game_data_present(g_docs) == 0);
    CHECK(gow2_ios_install_state(NULL, why, sizeof why) == GOW2_INSTALL_MISSING);
    CHECK(gow2_ios_game_data_present(NULL) == 0);

    put("EBOOT.ELF", "ELF!", "wb");                                              /* P1's install_ios.sh --data */
    put("USRDIR/gow2.psarc", "PSARC", "wb");
    put("movie_cache/a.m2v", "M", "wb");
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE && strstr(why, GOW2_INSTALL_MANIFEST_NAME) != NULL);

    manifest("gow2-install 1\nincomplete\n");                                    /* the launcher's copy in progress */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);

    manifest_of(good, 3, NULL, 0);
    CHECK(state(why, sizeof why) == GOW2_INSTALL_OK && why[0] == '\0');
    CHECK(gow2_ios_game_data_present(g_docs) == 1);
    CHECK(state(NULL, 0) == GOW2_INSTALL_OK);                                     /* why is optional */

    put("USRDIR/gow2.psarc", "PSA", "wb");                                        /* torn copy of the big file */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE && strstr(why, "USRDIR/gow2.psarc") != NULL);
    put("USRDIR/gow2.psarc", "PSARC", "wb");
    CHECK(state(why, sizeof why) == GOW2_INSTALL_OK);

    snprintf(p, sizeof p, "%s/movie_cache/a.m2v", g_docs);
    unlink(p);                                                                    /* listed file missing */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE && strstr(why, "movie_cache/a.m2v") != NULL);
    put("movie_cache/a.m2v", "M", "wb");

    /* Consistency of the manifest itself (Codex review 7). */
    digest_of(good, 3, hex);
    snprintf(m, sizeof m, "gow2-install 1\nfile %s\nfile %s\nfile %s\nend 3\n", eb, ps, mc);
    manifest(m);                                                                  /* no set line */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    snprintf(m, sizeof m, "gow2-install 1\nset %s\nset %s\nfile %s\nfile %s\nfile %s\nend 3\n", hex, hex, eb, ps, mc);
    manifest(m);                                                                  /* two set lines */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE && strstr(why, "set line") != NULL);
    snprintf(m, sizeof m, "gow2-install 1\nfile %s\nset %s\nfile %s\nfile %s\nend 3\n", eb, hex, ps, mc);
    manifest(m);                                                                  /* set after a file */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    const char* other[] = { eb, ps };
    manifest_of(good, 3, other, 2);                                               /* set of another list */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE && strstr(why, "digest") != NULL);
    const char* dup[] = { eb, ps, ps, mc };
    manifest_of(dup, 4, NULL, 0);                                                 /* duplicate path, digest consistent */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE && strstr(why, "sorted") != NULL);
    const char* unsorted[] = { ps, eb, mc };
    manifest_of(unsorted, 3, NULL, 0);                                            /* unsorted */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    snprintf(m, sizeof m, "gow2-install 1\nset %s\nfile %s\nfile %s\nfile %s\nend 3\n", H, eb, ps, mc);
    manifest(m);                                                                  /* set that is not the digest */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE && strstr(why, "digest") != NULL);

    /* Structure. */
    snprintf(m, sizeof m, "gow2-install 1\nset %s\nfile %s\nfile %s\nfile %s\n", hex, eb, ps, mc);
    manifest(m);                                                                  /* no end line */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    snprintf(m, sizeof m, "gow2-install 1\nset %s\nfile %s\nfile %s\nfile %s\nend 4\n", hex, eb, ps, mc);
    manifest(m);                                                                  /* count mismatch */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    char bad[128];
    entry(bad, sizeof bad, 5, "USRDIR/../gow2.psarc");
    const char* unsafe[] = { eb, bad };
    manifest_of(unsafe, 2, NULL, 0);                                              /* unsafe path */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    entry(bad, sizeof bad, 4, "/EBOOT.ELF");
    const char* absolute[] = { bad, ps };
    manifest_of(absolute, 2, NULL, 0);                                            /* absolute path */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    const char* no_eboot[] = { ps };
    manifest_of(no_eboot, 1, NULL, 0);                                            /* no EBOOT listed */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE && strstr(why, "EBOOT") != NULL);
    const char* no_usrdir[] = { eb };
    manifest_of(no_usrdir, 1, NULL, 0);                                           /* no USRDIR file listed */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE && strstr(why, "USRDIR") != NULL);
    snprintf(m, sizeof m, "gow2-install 1\nset %s\nfile 4 XYZ EBOOT.ELF\nend 1\n", hex);
    manifest(m);                                                                  /* bad hash */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    manifest("gow2-install 2\nend 0\n");                                          /* unknown version */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    manifest("");                                                                 /* empty file */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    manifest_of(good, 3, NULL, 0);
    snprintf(m, sizeof m, "file %s\n", mc);
    put(GOW2_INSTALL_MANIFEST_NAME, m, "ab");                                     /* data after end */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);
    snprintf(m, sizeof m, "gow2-install 1\nset %s\nfile %s\nfile %s\nfile %s\nend 3", hex, eb, ps, mc);
    manifest(m);                                                                  /* last line cut short */
    CHECK(state(why, sizeof why) == GOW2_INSTALL_INCOMPLETE);

    char cmd[128];
    snprintf(cmd, sizeof cmd, "rm -rf '%s'", g_docs);
    (void)system(cmd);
    printf(g_fail ? "test_gow2_ios_install_manifest: FAIL %d\n" : "test_gow2_ios_install_manifest: PASS\n", g_fail);
    return g_fail ? 1 : 0;
}
