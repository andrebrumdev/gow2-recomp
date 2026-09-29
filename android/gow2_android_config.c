/* GoW2 Android host configuration; see gow2_android_config.h. */
#include "gow2_android_config.h"
#include "gow2_env_file.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int kind_ok(const char* k) { return strcmp(k, "external") == 0 || strcmp(k, "internal") == 0; }

static int name_ok(const char* s)   /* [A-Za-z0-9._-]+, not "." or ".." */
{
    if (!*s || strcmp(s, ".") == 0 || strcmp(s, "..") == 0) return 0;
    for (; *s; s++)
        if (!((*s >= 'A' && *s <= 'Z') || (*s >= 'a' && *s <= 'z') || (*s >= '0' && *s <= '9') ||
              *s == '.' || *s == '_' || *s == '-')) return 0;
    return 1;
}

static int env_ok(const char* kv)   /* KEY=VALUE with KEY = [A-Z_][A-Z0-9_]* */
{
    const char* eq = strchr(kv, '=');
    if (!eq || eq == kv || !((kv[0] >= 'A' && kv[0] <= 'Z') || kv[0] == '_')) return 0;
    for (const char* s = kv; s < eq; s++)
        if (!((*s >= 'A' && *s <= 'Z') || (*s >= '0' && *s <= '9') || *s == '_')) return 0;
    return 1;
}

#define COPY(dst, src) snprintf((dst), sizeof(dst), "%s", (src))
#define BAD(...) do { snprintf(a->err, sizeof a->err, __VA_ARGS__); return -1; } while (0)

int gow2_android_args_parse(int argc, char** argv, gow2_android_args* a)
{
    memset(a, 0, sizeof *a);
    COPY(a->run, "-");
    for (int i = 1; i < argc; i++) {
        const char* s = argv[i];
        if (!s || !*s) continue;
        if (!strncmp(s, "--run=", 6)) { if (!name_ok(s + 6) || strlen(s + 6) >= sizeof a->run) BAD("bad --run"); COPY(a->run, s + 6); }
        else if (!strncmp(s, "--probe=", 8)) {
            if (strcmp(s + 8, "transport") && strcmp(s + 8, "restore_check") && strcmp(s + 8, "drill")) BAD("bad --probe");
            COPY(a->probe, s + 8);
        }
        else if (!strncmp(s, "--op=", 5)) { a->op = atoi(s + 5); if (a->op < 1 || a->op > 12) BAD("bad --op"); }
        else if (!strncmp(s, "--root=", 7)) { if (!kind_ok(s + 7)) BAD("bad --root"); COPY(a->root, s + 7); }
        else if (!strncmp(s, "--data-root=", 12)) { if (!kind_ok(s + 12)) BAD("bad --data-root"); COPY(a->data_root, s + 12); }
        else if (!strncmp(s, "--save-root=", 12)) { if (!kind_ok(s + 12)) BAD("bad --save-root"); COPY(a->save_root, s + 12); }
        else if (!strncmp(s, "--dir=", 6)) { if (!name_ok(s + 6) || strlen(s + 6) >= sizeof a->dir) BAD("bad --dir"); COPY(a->dir, s + 6); }
        else if (!strcmp(s, "--txnroot=drill")) a->txn_drill = 1;
        else if (!strncmp(s, "--env=", 6)) {
            if (a->n_env >= GOW2_ANDROID_MAX_ENV || !env_ok(s + 6) || strlen(s + 6) >= sizeof a->env[0]) BAD("bad --env");
            COPY(a->env[a->n_env], s + 6); a->n_env++;
        }
        else BAD("unknown argument %.60s", s);
    }
    if (!strcmp(a->probe, "transport") && (!a->op || !a->root[0])) BAD("--probe=transport needs --op and --root");
    if (!strcmp(a->probe, "restore_check") && !a->dir[0]) BAD("--probe=restore_check needs --dir");
    return 0;
}

int gow2_android_env_apply(const gow2_android_args* a, const char* override_path, const char* asset_text,
                           int* applied)
{
    int n = 0, ap = 0, rej = 0;
    for (int i = 0; i < a->n_env; i++) {
        char kv[256];
        COPY(kv, a->env[i]);
        char* eq = strchr(kv, '=');
        *eq = 0;
        if (setenv(kv, eq + 1, 1) == 0) n++;
    }
    if (override_path && gow2_env_apply_file(override_path, 0, &ap, &rej) == 0) n += ap;
    if (!asset_text) { if (applied) *applied = n; return -1; }
    ap = 0;
    gow2_env_apply_text(asset_text, 0, &ap, &rej);
    n += ap;
    if (applied) *applied = n;
    return 0;
}

static const char* pick_kind(const char* arg, const char* env_name)
{
    if (arg && *arg) return arg;
    const char* e = getenv(env_name);
    return (e && *e) ? e : "external";
}

int gow2_android_paths_resolve(const gow2_android_args* a, const char* ext, const char* internal,
                               gow2_android_paths* p)
{
    memset(p, 0, sizeof *p);
    const char* dk = pick_kind(a->data_root, "GOW2_ANDROID_DATA_ROOT");
    const char* sk = pick_kind(a->save_root[0] ? a->save_root : a->root, "GOW2_ANDROID_SAVE_ROOT");
    if (!kind_ok(dk) || !kind_ok(sk) || !internal) return -1;
    const char* dr = strcmp(dk, "internal") == 0 ? internal : ext;
    const char* sr = strcmp(sk, "internal") == 0 ? internal : ext;
    if (!dr || !sr) return -1;
    if (a->txn_drill) {
        snprintf(p->data, sizeof p->data, "%s/probe/drill/data", dr);
        snprintf(p->save_parent, sizeof p->save_parent, "%s/probe/drill", sr);
    } else {
        snprintf(p->data, sizeof p->data, "%s", dr);
        snprintf(p->save_parent, sizeof p->save_parent, "%s", sr);
    }
    snprintf(p->savedata, sizeof p->savedata, "%s/savedata", p->save_parent);
    snprintf(p->eboot, sizeof p->eboot, "%s/EBOOT.ELF", p->data);
    snprintf(p->usrdir, sizeof p->usrdir, "%s/USRDIR", p->data);
    snprintf(p->movie_cache, sizeof p->movie_cache, "%s/movie_cache", p->data);
    snprintf(p->log, sizeof p->log, "%s/gow2.log", p->data);
    snprintf(p->vkcache, sizeof p->vkcache, "%s/vkcache", internal);
    snprintf(p->internal, sizeof p->internal, "%s", internal);
    return 0;
}

void gow2_android_paths_export(const gow2_android_paths* p)
{
    if (!getenv("HOME")) setenv("HOME", p->internal, 0);
    if (!getenv("TMPDIR")) setenv("TMPDIR", p->internal, 0);
    setenv("GOW2_EBOOT", p->eboot, 1);
    setenv("PS3_VFS_ROOT", p->usrdir, 1);
    setenv("PS3_MOVIE_CACHE", p->movie_cache, 1);
    setenv("PS3_SAVEDATA_ROOT", p->savedata, 1);
    setenv("PS3_VK_CACHE_DIR", p->vkcache, 1);
}
