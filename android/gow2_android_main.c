/* GoW2 Android app entry: SDL_main, called by SDLActivity on its own Java thread. */
#include <SDL2/SDL.h>
#include <SDL2/SDL_main.h>
#include <SDL2/SDL_system.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "gow2_android_config.h"
#include "gow2_android_host.h"
#include "gow2_android_probe.h"
#include "gow2_ios_install_manifest.h"
#ifndef GOW2_ANDROID_PROBE_ONLY
#include "gow2_android_home.h"
#include "gow2_boot.h"
#include "vm_selftest.h"
#endif

static char* read_asset(const char* name)
{
    SDL_RWops* rw = SDL_RWFromFile(name, "rb");
    if (!rw) return NULL;
    Sint64 n = SDL_RWsize(rw);
    char* b = (n >= 0 && n < (1 << 20)) ? (char*)malloc((size_t)n + 1) : NULL;
    if (b && SDL_RWread(rw, b, 1, (size_t)n) == (size_t)n) b[n] = 0;
    else { free(b); b = NULL; }
    SDL_RWclose(rw);
    return b;
}

int main(int argc, char** argv)   /* SDL_main.h renames this to SDL_main */
{
    const char* ext = SDL_AndroidGetExternalStoragePath();
    const char* in = SDL_AndroidGetInternalStoragePath();
    gow2_android_args a;
    const int bad = gow2_android_args_parse(argc, argv, &a);
    char* asset = read_asset("gow2.env");
    char override_path[600];
    snprintf(override_path, sizeof override_path, "%s/gow2.override.env", in ? in : ".");
    int applied = 0;
    const int cfg = gow2_android_env_apply(&a, override_path, asset, &applied);
    gow2_android_paths p;
    const int paths_ok = gow2_android_paths_resolve(&a, ext, in, &p) == 0;

    if (a.probe[0]) {
        /* probe mode: everything under <root>/probe/, log beside it and in logcat */
        const char* root = !strcmp(a.root, "internal") ? in : ext;
        char probe_dir[600], logp[640];
        if (!strcmp(a.probe, "transport")) snprintf(probe_dir, sizeof probe_dir, "%s/probe", root ? root : ".");
        else snprintf(probe_dir, sizeof probe_dir, "%s/probe", paths_ok ? p.save_parent : ".");
        mkdir(probe_dir, 0775);
        snprintf(logp, sizeof logp, "%s/probe.log", probe_dir);
        gow2_android_log_begin(logp, 1);
        if (bad || !paths_ok || (!strcmp(a.probe, "transport") && !root)) {
            fprintf(stderr, "[PROBE] run=%s done op=%s rc=1 (%s)\n", a.run, a.probe, bad ? a.err : "storage unavailable");
            gow2_android_log_flush();
            _exit(1);
        }
        const int rc = gow2_probe_run(&a, root, &p, stderr);
        gow2_android_log_flush();
        _exit(rc);
    }
#ifdef GOW2_ANDROID_PROBE_ONLY
    (void)cfg; (void)applied;
    SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_INFORMATION, "God of War II",
                             "Este é o app de sondagem da instalação. Rode a instalação de novo no Mac.", NULL);
    return 0;
#else
    if (!paths_ok) {
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "God of War II",
                                 "Armazenamento do app indisponível — reconecte e rode a instalação de novo no Mac.", NULL);
        return 1;
    }
    gow2_android_log_begin(p.log, 0);
    fprintf(stderr, "[android] run=%s args=%s config: %d set%s, data=%s saves=%s\n", a.run, bad ? a.err : "ok", applied,
            cfg != 0 ? " (bundled gow2.env MISSING)" : "", p.data, p.savedata);
    gow2_android_paths_export(&p);
    {   /* overlay settings (touch layout, shell toggles): persisted best effort; defaults when the file is absent */
        char sp[700];
        snprintf(sp, sizeof sp, "%s/overlay.settings", p.internal);
        setenv("PS3_OVERLAY_SETTINGS", sp, 0);
    }
    mkdir(p.savedata, 0775);
    mkdir(p.vkcache, 0775);
    char why[256];
    const gow2_install_state st = gow2_ios_install_state(p.data, why, sizeof why);
    fprintf(stderr, "[android] run=%s install state %s%s%s\n", a.run,
            st == GOW2_INSTALL_OK ? "OK" : st == GOW2_INSTALL_MISSING ? "MISSING" : "INCOMPLETE", why[0] ? " " : "", why);
    if (st != GOW2_INSTALL_OK) {
        gow2_android_log_flush();
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "God of War II",
                                 "Dados do jogo incompletos — rode a instalação de novo no Mac.", NULL);
        return 0;
    }
    SDL_SetHint(SDL_HINT_ANDROID_TRAP_BACK_BUTTON, "1");
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");   /* landscape only, even with the tablet held upright */
    gow2_android_perf_start();
    if (gow2_boot_prepare_display() != 0) {
        fprintf(stderr, "[android] FATAL: display preparation failed\n");
        gow2_android_log_flush();
        return 1;
    }
    const char* vt = getenv("PS3_ANDROID_VMTEST");
    if (vt && vt[0] == '1') {              /* §3.7 part 1, in the app process, before the guest boot */
        char* text = read_asset("vm_bands.txt");
        vm_band bands[256];
        int bl = 0;
        const int n = text ? vm_selftest_parse_bands(text, bands, 256, &bl) : -1;
        if (n < 0) fprintf(stderr, "[VMTEST] fail n=1 (vm_bands.txt %s, line %d)\n", text ? "malformed" : "missing", bl);
        else (void)vm_selftest_run(bands, n, NULL, stderr);
        free(text);
    }
    /* the home screen owns the screen until "Jogar"; the version is the APK's versionName (build_apk.sh --version-name) */
    return gow2_android_home_loop(p.eboot, p.internal, p.savedata, st == GOW2_INSTALL_OK, "d0");
#endif
}
