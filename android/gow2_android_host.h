/* GoW2 Android host glue (Android-only): log tee to a file + logcat, the fatal-signal line,
 * the guest thread, the gated perf/VM/SIG tests. The iOS counterpart is ios/Sources/gow2_ios_host.m. */
#ifndef GOW2_ANDROID_HOST_H
#define GOW2_ANDROID_HOST_H

#ifdef __cplusplus
extern "C" {
#endif

/* stdout/stderr -> a pipe drained by a thread into log_path (truncated unless append) and
 * logcat (tag "gow2", one entry per line). Installs the fatal-signal line. */
void gow2_android_log_begin(const char* log_path, int append);
/* Move what is still in the pipe into the file (bounded ~300 ms); before _exit. */
void gow2_android_log_flush(void);
/* PS3_ANDROID_PERF_LOG=1: "[ANDPERF] t=<s> flips=<n> fps=<f> rss_mb=<m>" every second. */
void gow2_android_perf_start(void);
/* The guest on a 64 MB pthread: prepare (SPU, VM, ELF, HLE), SIGTEST if gated, run. Never
 * returns to the caller's flow: joins, flushes the log and _exit()s with the guest's rc. */
int gow2_android_run_guest(const char* eboot, const char* scratch_dir);
/* The same guest thread without the join: returns right after pthread_create (0, or the error). The SDL main
 * thread keeps pumping; gow2_android_guest_exited polls for the end. */
int gow2_android_start_guest(const char* eboot, const char* scratch_dir);
/* 1 once the guest thread started by gow2_android_start_guest returned (its rc in *rc); 0 while it runs. */
int gow2_android_guest_exited(int* rc);
/* AThermal status (NONE 0 .. SHUTDOWN 6) resolved at run time (API 30); *have = 0 when there is no manager or the
 * call failed (ATHERMAL_STATUS_ERROR): "no data", never a cool reading. */
int gow2_android_thermal_status(int* have);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_ANDROID_HOST_H */
