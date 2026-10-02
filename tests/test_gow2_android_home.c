/* gow2_android_fill_host_status: the values the Android home screen and the Desenvolvedor panel show. */
#include <stdio.h>
#include <string.h>
#include "gow2_android_home.h"

static int fails;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); fails++; } } while (0)

int main(void)
{
    rsx_overlay_host_status st;
    /* thermal known: AThermal MODERATE(2) -> serious(2); SEVERE(3) and worse -> critical(3) */
    gow2_android_fill_host_status(&st, 1, 2, 812, 1, 1700000000LL, "0.9 (d0)");
    CHECK(st.thermal_state == 2, "moderate -> 2");
    CHECK(st.game_data_present == 1 && st.footprint_mb == 812 && st.last_save_unix == 1700000000LL, "fields copied");
    CHECK(st.fps_cap == 0 && st.memory_ceiling_mb == 0 && st.sign_expiry_unix == 0, "no cap, no ceiling, no expiry badge on Android");
    CHECK(strstr(st.about, "0.9 (d0)") != NULL, "about carries the version");
    gow2_android_fill_host_status(&st, 1, 5, 0, 0, 0, "v");
    CHECK(st.thermal_state == 3 && st.game_data_present == 0, "emergency -> 3; no data");
    /* no thermal manager (API < 30): unknown, not "cool" */
    gow2_android_fill_host_status(&st, 0, -1, 0, 1, 0, "v");
    CHECK(st.thermal_state == -1, "no thermal source -> unknown (-1)");
    /* a long version string never overflows the 96-byte about line */
    char big[400]; memset(big, 'x', sizeof big - 1); big[sizeof big - 1] = 0;
    gow2_android_fill_host_status(&st, 1, 0, 0, 1, 0, big);
    CHECK(strlen(st.about) < sizeof st.about, "about is NUL-terminated inside 96 bytes");
    gow2_android_fill_host_status(&st, 1, 0, 0, 1, 0, NULL);
    CHECK(st.about[0] != 0, "NULL version still prints a line");
    puts(fails ? "test_gow2_android_home: FAIL" : "test_gow2_android_home: PASS");
    return fails ? 1 : 0;
}
