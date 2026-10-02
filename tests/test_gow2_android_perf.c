/* gow2_android_perf.c: the pure parts of the Android perf sampler (host-testable). */
#include <stdio.h>
#include <string.h>
#include "gow2_android_perf.h"

static int fails;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); fails++; } } while (0)

int main(void)
{
    /* AThermalStatus: NONE 0, LIGHT 1, MODERATE 2, SEVERE 3 .. SHUTDOWN 6 -> 0..3 (SEVERE+ is "critical") */
    CHECK(gow2_android_thermal_level(0) == 0, "none -> 0");
    CHECK(gow2_android_thermal_level(1) == 1, "light -> 1");
    CHECK(gow2_android_thermal_level(2) == 2, "moderate -> 2");
    CHECK(gow2_android_thermal_level(3) == 3, "severe -> 3");
    CHECK(gow2_android_thermal_level(6) == 3, "shutdown -> 3");
    CHECK(gow2_android_thermal_level(-1) == 0, "unavailable -> 0 (thermal_src=none carries the truth)");

    const char* mi = "MemTotal:        7900000 kB\nMemFree:          100000 kB\nMemAvailable:    3145728 kB\nBuffers: 1 kB\n";
    CHECK(gow2_android_meminfo_available_mb(mi) == 3072, "MemAvailable 3145728 kB = 3072 MB");
    CHECK(gow2_android_meminfo_available_mb("MemTotal: 1 kB\n") == -1, "no MemAvailable -> -1");
    CHECK(gow2_android_meminfo_available_mb(NULL) == -1, "NULL -> -1");

    char b[256];
    gow2_android_format_perf_line(b, sizeof b, 12.0, 2, "athermal", 900, 3072, 100, 30, "2400,2400");
    CHECK(!strcmp(b, "[ANDPERF] t=12.0 thermal=2 footprint_mb=900 available_mb=3072 thermal_src=athermal "
                     "flips=100 fps=30 cpu_mhz=2400,2400"), b);
    /* API < 30: no thermal manager; unknown memory must still print digits perf_report.py can parse */
    gow2_android_format_perf_line(b, sizeof b, 1.0, 0, NULL, 500, -1, 0, 0, NULL);
    CHECK(!strcmp(b, "[ANDPERF] t=1.0 thermal=0 footprint_mb=500 available_mb=0 thermal_src=none flips=0 fps=0 cpu_mhz="), b);

    puts(fails ? "test_gow2_android_perf: FAIL" : "test_gow2_android_perf: PASS");
    return fails ? 1 : 0;
}
