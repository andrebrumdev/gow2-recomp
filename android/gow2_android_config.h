/* GoW2 Android host: launch arguments, configuration load order and app paths (pure C,
 * tested on the Mac). GoW2Activity.getArguments() turns the launch intent's "gow2_args"
 * string extra into argv; the app icon passes none. */
#ifndef GOW2_ANDROID_CONFIG_H
#define GOW2_ANDROID_CONFIG_H

#ifdef __cplusplus
extern "C" {
#endif

#define GOW2_ANDROID_MAX_ENV 32

typedef struct gow2_android_args {
    char run[48];            /* --run=ID: echoed in the app's lines ("-" when absent) */
    char probe[16];          /* --probe=transport|restore_check|drill ("" = the game) */
    int  op;                 /* --op=1..12 (transport) */
    char root[12];           /* --root=external|internal (transport candidate) */
    char data_root[12];      /* --data-root=external|internal (default: GOW2_ANDROID_DATA_ROOT) */
    char save_root[12];      /* --save-root=external|internal (default: GOW2_ANDROID_SAVE_ROOT) */
    char dir[64];            /* --dir=NAME|live (restore_check) */
    int  txn_drill;          /* --txnroot=drill */
    int  n_env;
    char env[GOW2_ANDROID_MAX_ENV][256];  /* --env=KEY=VALUE */
    char err[160];
} gow2_android_args;

/* 0 = parsed; -1 = rejected (a->err says why). Unknown flags are rejected, never ignored. */
int gow2_android_args_parse(int argc, char** argv, gow2_android_args* a);

/* Configuration, first value wins (same rule as iOS): the launch --env pairs, then
 * override_path (optional file), then asset_text (the bundled gow2.env). Returns 0, or -1
 * when asset_text is NULL (the APK always ships it). *applied = variables set. */
int gow2_android_env_apply(const gow2_android_args* a, const char* override_path, const char* asset_text,
                           int* applied);

typedef struct gow2_android_paths {
    char data[512];          /* EBOOT.ELF, USRDIR/, movie_cache/, gow2-install.manifest, gow2.log */
    char save_parent[512];   /* its probe/ holds the restore-check scratch dirs */
    char savedata[560];
    char eboot[560], usrdir[560], movie_cache[560], log[560], vkcache[560], internal[512];
} gow2_android_paths;

/* ext/internal = SDL_AndroidGetExternalStoragePath()/GetInternalStoragePath(). Kinds come
 * from args, else GOW2_ANDROID_DATA_ROOT / GOW2_ANDROID_SAVE_ROOT, else "external".
 * txn_drill moves data to <root>/probe/drill/data and saves to <root>/probe/drill/savedata.
 * -1 when a kind is unknown or its directory is NULL. */
int gow2_android_paths_resolve(const gow2_android_args* a, const char* ext, const char* internal,
                               gow2_android_paths* p);

/* setenv(..., 1) of GOW2_EBOOT PS3_VFS_ROOT PS3_MOVIE_CACHE PS3_SAVEDATA_ROOT PS3_VK_CACHE_DIR
 * (last, so they always point into the app's dirs), HOME and TMPDIR (only when unset: an app
 * process has neither). */
void gow2_android_paths_export(const gow2_android_paths* p);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_ANDROID_CONFIG_H */
