/* GoW2 boot host API (boot_macos.cpp), shared by the macOS main() and the iOS
 * app. macOS: gow2_boot_prepare -> gow2_boot_run_guest -> gow2_boot_shutdown.
 * gow2_boot_prepare is gow2_boot_prepare_guest then gow2_boot_prepare_display
 * (the order the Mac has always used); the iOS home screen (P2) needs the
 * display before, and without, the guest. */
#ifndef GOW2_BOOT_H
#define GOW2_BOOT_H

#ifdef __cplusplus
extern "C" {
#endif

/* gow2_boot_prepare_guest, gow2_boot_prepare_display, then the movie-object
 * sampler (the macOS order). 0 ok; nonzero after logging a FATAL line. Main thread. */
int gow2_boot_prepare(const char* elf_path);

/* RSX backend (window, Metal layer) and overlay. Main thread. Idempotent: a
 * second call returns 0 and does nothing. Needs no guest. */
int gow2_boot_prepare_display(void);

/* SPU registration from the environment, guest memory, ELF, HLE. Touches no
 * display. 0 ok. */
int gow2_boot_prepare_guest(const char* elf_path);

/* Runs the guest on the calling thread until it returns; its rc. */
int gow2_boot_run_guest(void);

/* Orderly exit: overlay (saves settings), backend, guest memory. */
void gow2_boot_shutdown(void);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_BOOT_H */
