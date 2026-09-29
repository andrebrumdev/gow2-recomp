/* GoW2 Android probe routines; see gow2_android_probe.h. */
#include "gow2_android_probe.h"
#include "gow2_ios_install_manifest.h"
#include "gow2_sha256.h"

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
#define MAXF 4096

int gow2_probe_path_ok(const char* root, const char* path)
{
    char base[PATH_MAX], rroot[PATH_MAX], cur[PATH_MAX], rest[PATH_MAX] = "";
    if (!root || !path || strstr(path, "/../") || strstr(path, "/./")) return 0;
    size_t L = strlen(path);
    if (L >= 3 && !strcmp(path + L - 3, "/..")) return 0;
    snprintf(base, sizeof base, "%s/probe", root);
    if (!realpath(base, rroot)) return 0;
    snprintf(cur, sizeof cur, "%s", path);
    for (;;) {                                   /* longest existing prefix, like realpath -m */
        char res[PATH_MAX];
        if (realpath(cur, res)) {
            char full[PATH_MAX * 2];
            snprintf(full, sizeof full, "%s%s", res, rest);
            size_t n = strlen(rroot);
            return strncmp(full, rroot, n) == 0 && full[n] == '/' && full[n + 1] != 0;
        }
        char* s = strrchr(cur, '/');
        if (!s || s == cur) return 0;
        char tmp[PATH_MAX];
        snprintf(tmp, sizeof tmp, "%s%s", s, rest);
        snprintf(rest, sizeof rest, "%s", tmp);
        *s = 0;
    }
}

void gow2_probe_fill(unsigned char* buf, size_t n, unsigned long long seed)
{
    unsigned long long x = seed * 0x9E3779B97F4A7C15ull + 1;
    for (size_t i = 0; i < n; i++) {
        x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
        buf[i] = (unsigned char)((x * 0x2545F4914F6CDD1Dull) >> 56);
    }
}

static int mkdirs(const char* path)          /* mkdir -p of path's directories */
{
    char t[PATH_MAX];
    snprintf(t, sizeof t, "%s", path);
    for (char* s = t + 1; *s; s++)
        if (*s == '/') { *s = 0; if (mkdir(t, 0775) != 0 && errno != EEXIST) return -1; *s = '/'; }
    return 0;
}

static int write_seeded(const char* root, const char* path, size_t n, unsigned long long seed, char hex[65])
{
    if (!gow2_probe_path_ok(root, path) || mkdirs(path) != 0) return -1;
    unsigned char* b = (unsigned char*)malloc(n);
    if (!b) return -1;
    gow2_probe_fill(b, n, seed);
    FILE* f = fopen(path, "wb");                 /* the stdio path cellSaveData writes through */
    int ok = f && fwrite(b, 1, n, f) == n;
    if (f && fclose(f) != 0) ok = 0;
    free(b);
    return ok && gow2_sha256_file(path, hex) == 0 ? 0 : -1;
}

static int sha_stdio(const char* path, char hex[65])     /* read back through fopen/fread */
{
    FILE* f = fopen(path, "rb");
    if (!f) return -1;
    gow2_sha256_ctx c; gow2_sha256_init(&c);
    unsigned char buf[65536]; size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) gow2_sha256_update(&c, buf, n);
    int err = ferror(f); fclose(f);
    if (err) return -1;
    unsigned char d[32]; gow2_sha256_final(&c, d); gow2_sha256_hex(d, hex);
    return 0;
}

typedef struct { char* v[MAXF]; int n; } flist;
static int cmpstr(const void* a, const void* b) { return strcmp(*(char* const*)a, *(char* const*)b); }
static void walk(const char* base, const char* rel, flist* l)
{
    char dir[PATH_MAX];
    snprintf(dir, sizeof dir, "%s%s%s", base, *rel ? "/" : "", rel);
    DIR* d = opendir(dir);
    if (!d) return;
    struct dirent* e;
    while ((e = readdir(d)) != NULL && l->n < MAXF) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        char r[PATH_MAX], full[PATH_MAX * 2];
        snprintf(r, sizeof r, "%s%s%s", rel, *rel ? "/" : "", e->d_name);
        snprintf(full, sizeof full, "%s/%s", base, r);
        struct stat st;
        if (lstat(full, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) walk(base, r, l);
        else if (S_ISREG(st.st_mode)) l->v[l->n++] = strdup(r);
    }
    closedir(d);
}
static void list_sorted(const char* base, flist* l) { l->n = 0; walk(base, "", l); qsort(l->v, (size_t)l->n, sizeof l->v[0], cmpstr); }
static void list_free(flist* l) { for (int i = 0; i < l->n; i++) free(l->v[i]); l->n = 0; }

static int op_write(const gow2_android_args* a, const char* root, unsigned long long s1, unsigned long long s2, FILE* log)
{
    static const char* rel[2] = {"DATA.BIN", "nested/ICON0.PNG"};
    const size_t size[2] = {256 * 1024, 4096};
    const unsigned long long seed[2] = {s1, s2};
    int rc = 0;
    for (int i = 0; i < 2; i++) {
        char path[PATH_MAX], hex[65];
        snprintf(path, sizeof path, "%s/probe/app_save/%s", root, rel[i]);
        if (write_seeded(root, path, size[i], seed[i], hex) != 0) { fprintf(log, "[PROBE] run=%s op=%d file=%s error=%d\n", a->run, a->op, rel[i], errno); rc = 1; continue; }
        fprintf(log, "[PROBE] run=%s op=%d file=%s sha256=%s\n", a->run, a->op, rel[i], hex);
    }
    fprintf(log, "[PROBE] run=%s op=%d count=2\n", a->run, a->op);
    return rc;
}

static int op_read(const gow2_android_args* a, const char* root, FILE* log)
{
    static const char* rel[2] = {"a/b/f1m.bin", "a/b/f64m.bin"};
    int rc = 0;
    for (int i = 0; i < 2; i++) {
        char path[PATH_MAX], hex[65];
        snprintf(path, sizeof path, "%s/probe/%s", root, rel[i]);
        if (gow2_sha256_file(path, hex) != 0) { fprintf(log, "[PROBE] run=%s op=%d file=%s missing\n", a->run, a->op, rel[i]); rc = 1; continue; }
        fprintf(log, "[PROBE] run=%s op=%d file=%s sha256=%s\n", a->run, a->op, rel[i], hex);
    }
    if (a->op == 12) {
        char tree[PATH_MAX]; flist l;
        snprintf(tree, sizeof tree, "%s/probe/tree", root);
        list_sorted(tree, &l);
        for (int i = 0; i < l.n; i++) {
            char path[PATH_MAX * 2], hex[65];
            snprintf(path, sizeof path, "%s/%s", tree, l.v[i]);
            if (gow2_sha256_file(path, hex) != 0) { rc = 1; continue; }
            fprintf(log, "[PROBE] run=%s op=12 file=tree/%s sha256=%s\n", a->run, l.v[i], hex);
        }
        list_free(&l);
    }
    return rc;
}

static int restore_check(const gow2_android_args* a, const char* base, int write_beside, const char* root, FILE* log)
{
    flist l; int rc = 0, count = 0;
    list_sorted(base, &l);
    for (int i = 0; i < l.n; i++) {
        if (!strcmp(l.v[i], "APPWRITE.BIN")) continue;
        char path[PATH_MAX * 2], hex[65];
        snprintf(path, sizeof path, "%s/%s", base, l.v[i]);
        if (sha_stdio(path, hex) != 0) { fprintf(log, "[RESTORECHK] run=%s %s unreadable errno=%d\n", a->run, l.v[i], errno); rc = 1; continue; }
        fprintf(log, "[RESTORECHK] run=%s %s %s\n", a->run, l.v[i], hex);
        count++;
    }
    list_free(&l);
    fprintf(log, "[RESTORECHK] run=%s count=%d\n", a->run, count);
    if (write_beside) {
        char path[PATH_MAX], hex[65];
        snprintf(path, sizeof path, "%s/APPWRITE.BIN", base);
        if (write_seeded(root, path, 4096, 11, hex) != 0) { fprintf(log, "[PROBE] run=%s appwrite failed errno=%d\n", a->run, errno); rc = 1; }
        else fprintf(log, "[PROBE] run=%s appwrite APPWRITE.BIN %s\n", a->run, hex);
    }
    return rc;
}

int gow2_probe_run(const gow2_android_args* a, const char* root, const gow2_android_paths* p, FILE* log)
{
    int rc = 1;
    char op[16];
    if (!strcmp(a->probe, "transport")) {
        snprintf(op, sizeof op, "%d", a->op);
        switch (a->op) {
            case 6: rc = op_write(a, root, 6, 60, log); break;
            case 9: rc = op_write(a, root, 9, 90, log); break;
            case 7: case 12: rc = op_read(a, root, log); break;
            default: fprintf(log, "[PROBE] run=%s op=%d is Mac-side only\n", a->run, a->op); rc = 1; break;
        }
    } else if (!strcmp(a->probe, "restore_check")) {
        snprintf(op, sizeof op, "restore_check");
        char base[PATH_MAX];
        const int live = !strcmp(a->dir, "live");
        if (live) snprintf(base, sizeof base, "%s", p->savedata);
        else snprintf(base, sizeof base, "%s/probe/restore_check/%s", p->save_parent, a->dir);
        /* the scratch dir must be ours; the live dir is read-only here */
        if (!live && !gow2_probe_path_ok(p->save_parent, base)) { fprintf(log, "[PROBE] run=%s refused %s\n", a->run, base); rc = 1; }
        else rc = restore_check(a, base, !live, p->save_parent, log);
    } else if (!strcmp(a->probe, "drill")) {
        snprintf(op, sizeof op, "drill");
        char why[256];
        gow2_install_state st = gow2_ios_install_state(p->data, why, sizeof why);
        fprintf(log, "[PROBE] run=%s drill manifest %s%s%s\n", a->run, st == GOW2_INSTALL_OK ? "OK" : "INCOMPLETE",
                why[0] ? " " : "", why);
        rc = restore_check(a, p->savedata, 0, p->save_parent, log);
    } else {
        snprintf(op, sizeof op, "none");
    }
    fprintf(log, "[PROBE] run=%s done op=%s rc=%d\n", a->run, op, rc);
    fflush(log);
    return rc;
}
