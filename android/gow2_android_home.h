/* GoW2 Android home screen: the host status the overlay shows and the SDL-main-thread loop that owns the screen
 * until the first guest frame. The pure status filler lives in gow2_android_home_status.c (Mac-tested); the loop
 * in gow2_android_home.c (Android host only). */
#ifndef GOW2_ANDROID_HOME_H
#define GOW2_ANDROID_HOME_H
#include "rsx_overlay.h"

#ifdef __cplusplus
extern "C" {
#endif
/* The values the home screen and the shell's Desenvolvedor panel show. thermal_have = an AThermal manager gave a status;
 * athermal_status is the raw AThermalStatus (NONE 0 .. SHUTDOWN 6): 0..2 map 1:1 onto nominal/fair/serious, >= 3 to
 * critical; without a source the state is unknown (-1), never "nominal". No fps cap, memory ceiling or re-sign
 * expiry exists on Android (0). */
void gow2_android_fill_host_status(rsx_overlay_host_status* st, int thermal_have, int athermal_status, unsigned footprint_mb,
                                   int data_present, long long last_save_unix, const char* version);
/* The home: pumps events on the calling (SDL main) thread for the whole life of the app, presents the UI until
 * "Jogar", starts the guest thread, hands the screen over at the first guest frame and keeps pumping. Never returns
 * unless the guest thread cannot be created (rc); on the guest's exit it flushes the log and _exit()s. */
int gow2_android_home_loop(const char* eboot, const char* scratch, const char* savedata, int data_present, const char* version);
#ifdef __cplusplus
}
#endif
#endif
