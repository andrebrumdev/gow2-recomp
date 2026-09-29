/* PS3_ANDROID_SIGTEST=1 (OFF by default, spec §3.6/§7 D0): proves the SPU-job fault recovery
 * (runtime/spu/spu_workload.c: sigaction + siglongjmp) works inside the ART process through
 * libsigchain. Three synthetic raw-LS-image jobs through the real spu_workload_dispatch:
 * A reads the unmapped 0x7E57D00D0000 (SIGSEGV), B reads past the end of a 4 KB file mapped
 * with a 64 KB length (SIGBUS), C is clean. Logs "[SIGTEST] ..." lines; 0 = pass. */
#ifndef GOW2_ANDROID_SIGTEST_H
#define GOW2_ANDROID_SIGTEST_H

#ifdef __cplusplus
extern "C" {
#endif

/* scratch_dir: an app-owned writable dir (the internal files dir) for B's 4 KB file. */
int gow2_android_sigtest_run(const char* scratch_dir);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_ANDROID_SIGTEST_H */
