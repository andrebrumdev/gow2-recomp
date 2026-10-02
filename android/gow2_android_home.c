/* GoW2 Android home screen loop (Android host only): see gow2_android_home.h. The SDL main thread owns the window,
 * pumps its events for the whole life of the app and draws the overlay's home screen until "Jogar"; the guest runs
 * on its own 64 MB thread (gow2_android_start_guest) and takes the swapchain over at its first flip. This thread
 * never blocks on the guest. */
#include "gow2_android_home.h"
#include "gow2_android_host.h"
#include "gow2_ios_ui_policy.h"   /* gow2_ios_latest_save_mtime (shared portable C) */
#include "rsx_vulkan_backend.h"
#include "gcm_rsxt.h"            /* gcm_rsx_consumer_stop (PS3_RSX_THREAD) */
#include <SDL2/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static unsigned footprint_mb(void)
{
    long pages = 0, rss = 0;
    FILE* f = fopen("/proc/self/statm", "r");
    if (f) { if (fscanf(f, "%ld %ld", &pages, &rss) != 2) rss = 0; fclose(f); }
    return (unsigned)(((long long)rss * (long long)sysconf(_SC_PAGESIZE)) >> 20);
}

static void publish_status(const char* savedata, int data_present, const char* version, long long* last_save, unsigned* tick)
{
    int have = 0;
    const int ts = gow2_android_thermal_status(&have);
    if ((*tick)++ % 10 == 0) *last_save = gow2_ios_latest_save_mtime(savedata);   /* a directory scan: every 10 s */
    rsx_overlay_host_status st;
    gow2_android_fill_host_status(&st, have, ts, footprint_mb(), data_present, *last_save, version);
    rsx_overlay_publish_host_status(&st);
}

int gow2_android_home_loop(const char* eboot, const char* scratch, const char* savedata, int data_present, const char* version)
{
    /* Nothing can draw a UI (Vulkan failed -> SDL null backend: no window of ours): run the game directly, as before
     * the home existed. A disabled core with a Vulkan window still enters the loop below: it starts the guest at once
     * (rsx_overlay_disabled()) and this thread keeps draining the window's events. NOT `overlay_ready()`: the renderer
     * may still be pending its first present (created lazily under the device lock), which is fine. */
    if (!rsx_vulkan_backend_sdl_window()) {
        fprintf(stderr, "[android] no Vulkan window: starting the game without the home screen\n");
        return gow2_android_run_guest(eboot, scratch);
    }
    if (!rsx_overlay_disabled()) {
        rsx_overlay_set_ui_profile(RSX_OVERLAY_UI_PHONE);   /* no Tela / Sair in the shell, no Configurações at home */
        rsx_overlay_touch_enable(1);
        rsx_overlay_app_enable_home();
        rsx_vulkan_backend_set_host_ui(1);
    } else {
        fprintf(stderr, "[android] overlay disabled: starting the game without the home screen\n");
    }
    long long last_save = 0;
    unsigned tick = 0;
    int started = 0, handed = 0;
    Uint32 last_status = SDL_GetTicks();
    publish_status(savedata, data_present, version, &last_save, &tick);
    if (!rsx_overlay_disabled())
        fprintf(stderr, "[android] home screen up (game data %s)\n", data_present ? "present" : "missing");
    for (;;) {
        if (rsx_vulkan_backend_pump_messages() < 0) {           /* window closed (the pump normally _exit()s itself) */
            if (gcm_rsx_consumer_stop(250000000ull) == 0)        /* PS3_RSX_THREAD: drained + stopped, else touch nothing */
                gow2_android_log_flush();
            _exit(0);
        }
        int rc = 0;
        if (started && gow2_android_guest_exited(&rc)) {
            if (gcm_rsx_consumer_stop(250000000ull) == 0) {      /* PS3_RSX_THREAD: drained + stopped, else touch nothing */
                fprintf(stderr, "[android] guest returned rc=%d -- exiting\n", rc);
                gow2_android_log_flush();
            }
            _exit(rc == 0 ? 0 : 1);
        }
        if (!started && (rsx_overlay_take_start_request() || rsx_overlay_disabled())) {
            /* "Jogar" -- or the UI died during the home (8 atlas failures, a failed lazy renderer create): start the game anyway */
            started = 1;
            fprintf(stderr, rsx_overlay_disabled() ? "[android] overlay disabled during the home: starting the guest\n"
                                                   : "[android] Jogar: starting the guest\n");
            const int src = gow2_android_start_guest(eboot, scratch);
            if (src != 0) {
                gow2_android_log_flush();
                return src;
            }
        }
        if (started && !handed && rsx_vulkan_backend_guest_frames() > 0) {
            handed = 1;
            if (!rsx_overlay_disabled()) rsx_overlay_app_game_started();   /* a disabled core must not be re-armed */
            rsx_vulkan_backend_set_host_ui(0);
            fprintf(stderr, "[android] first guest frame: home screen handed over to the game\n");
        }
        if (!handed) {
            /* The home, then its LOADING sheet while the guest prepares, until the guest's first frame. present_ui draws
             * nothing once the guest began a frame or a flip (re-checked under the device lock) and never waits on the
             * lock; whenever it drew nothing (lock busy, guest started, no swapchain image, app in the background) sleep
             * instead of spinning. With a frame drawn, FIFO paces this loop to the display. */
            if (!rsx_vulkan_backend_present_ui()) SDL_Delay(4);
        } else {
            SDL_Delay(4);                                        /* the guest presents; this thread only pumps */
        }
        const Uint32 now = SDL_GetTicks();
        if (now - last_status >= 1000u) {
            last_status = now;
            publish_status(savedata, data_present, version, &last_save, &tick);
        }
    }
}
