#include "gow2_android_perf.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int gow2_android_thermal_level(int s)
{
    if (s < 0) return 0;
    return s >= 3 ? 3 : s;
}

long gow2_android_meminfo_available_mb(const char* text)
{
    const char* p = text ? strstr(text, "MemAvailable:") : NULL;
    if (!p) return -1;
    const long kb = strtol(p + 13, NULL, 10);
    return kb > 0 ? kb / 1024 : -1;
}

int gow2_android_format_perf_line(char* buf, size_t cap, double t_s, int thermal, const char* thermal_src,
                                  long rss_mb, long avail_mb, unsigned flips, unsigned fps, const char* cpu_mhz)
{
    return snprintf(buf, cap,
                    "[ANDPERF] t=%.1f thermal=%d footprint_mb=%ld available_mb=%ld thermal_src=%s "
                    "flips=%u fps=%u cpu_mhz=%s",
                    t_s, thermal, rss_mb, avail_mb < 0 ? 0L : avail_mb, thermal_src ? thermal_src : "none",
                    flips, fps, cpu_mhz ? cpu_mhz : "");
}
