#ifndef GOW2_ANDROID_PERF_H
#define GOW2_ANDROID_PERF_H
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif
/* AThermalStatus (NDK) -> perf_report.py's 0..3 scale: NONE 0, LIGHT 1, MODERATE 2, SEVERE and worse 3.
 * A negative status (no thermal manager) gives 0; the line's thermal_src=none says it is not a measurement. */
int gow2_android_thermal_level(int athermal_status);
/* MemAvailable of a /proc/meminfo text, in MB; -1 if absent. */
long gow2_android_meminfo_available_mb(const char* text);
/* One [ANDPERF] line, no newline. thermal_src NULL prints "none". */
int gow2_android_format_perf_line(char* buf, size_t cap, double t_s, int thermal, const char* thermal_src,
                                  long rss_mb, long avail_mb, unsigned flips, unsigned fps, const char* cpu_mhz);
#ifdef __cplusplus
}
#endif
#endif
