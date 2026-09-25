/* GoW2 boot host API (boot_macos.cpp), shared by the macOS main() and the iOS
 * app. Order: gow2_boot_prepare -> gow2_boot_run_guest -> gow2_boot_shutdown. */
#ifndef GOW2_BOOT_H
#define GOW2_BOOT_H

#ifdef __cplusplus
extern "C" {
#endif

/* SPU registration from the environment, guest memory, ELF, HLE, RSX backend
 * and overlay. 0 ok; nonzero after logging a FATAL line. Main thread. */
int gow2_boot_prepare(const char* elf_path);

/* Runs the guest on the calling thread until it returns; its rc. */
int gow2_boot_run_guest(void);

/* Orderly exit: overlay (saves settings), backend, guest memory. */
void gow2_boot_shutdown(void);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_BOOT_H */
