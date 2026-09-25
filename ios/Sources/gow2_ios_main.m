/* GoW2 iOS app entry. SDL_main runs on the main thread from UIKit's launch;
 * SDL2 keeps the UIKit run loop alive after it returns. */
#include <SDL2/SDL.h>
#include <SDL2/SDL_main.h>
#include <stdio.h>
#include <stdlib.h>

#include "gow2_boot.h"
#include "gow2_ios_host.h"
#include "gow2_ios_lifecycle.h"

int main(int argc, char** argv)
{
    (void)argc;
    (void)argv;
    gow2_ios_host_early();
    /* Config before gow2_boot_prepare: SPU registration and every env reader run there. */
    if (gow2_ios_host_load_config() != 0)
        fprintf(stderr, "[ios] bundled gow2.env missing -- running on the launch environment only\n");
    gow2_ios_host_start_perf_log();
    gow2_ios_host_wait_for_game_data();   /* P2: the home screen takes this over */
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    SDL_SetHint(SDL_HINT_IDLE_TIMER_DISABLED, "1");
    gow2_ios_host_audio_session_begin();
    if (gow2_boot_prepare(getenv("GOW2_EBOOT")) != 0) {
        fprintf(stderr, "[ios] boot preparation failed\n");
        return 1;
    }
    gow2_ios_host_install_lifecycle();
    /* Why SDL_PollEvent on the guest thread is safe -- keep in sync with
     * rsx_metal_backend_pump_messages (libs/video/rsx_metal_backend.m).
     * The guest's flip calls SDL_PollEvent (cellGcmSetFlipCommand ->
     * rsx_metal_backend_pump_messages) from the guest thread. SDL turns its
     * UIKit run-loop pumping off once SDL_main returns; turn it off now so the
     * guest thread never runs a run loop even before that: SDL_PollEvent then
     * only drains SDL's locked event queue, which UIKit fills on the main thread. */
    SDL_iPhoneSetEventPump(SDL_FALSE);
    if (gow2_ios_start_game() != 0) return 1;
    return 0;
}
