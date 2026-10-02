/* Pure part of the Android home screen: see gow2_android_home.h. */
#include "gow2_android_home.h"
#include <stdio.h>
#include <string.h>

void gow2_android_fill_host_status(rsx_overlay_host_status* st, int thermal_have, int athermal_status, unsigned footprint_mb,
                                   int data_present, long long last_save_unix, const char* version)
{
    memset(st, 0, sizeof *st);
    st->thermal_state = !thermal_have || athermal_status < 0 ? -1 : (athermal_status >= 3 ? 3 : athermal_status);
    st->footprint_mb = footprint_mb;
    st->game_data_present = data_present ? 1 : 0;
    st->last_save_unix = last_save_unix;
    snprintf(st->about, sizeof st->about, "Vers\xC3\xA3o %s", version && version[0] ? version : "?");
}
