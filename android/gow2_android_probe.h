/* GoW2 Android probe routines (spec §5.4 ops 6/7/9/11/12, the P3 restore check and the
 * rollback drill's app side). Run instead of the game when the launch has --probe=...; they
 * write only under <root>/probe/ (realpath-checked), read saves through stdio (what
 * cellSaveData uses) and data through open(2) (what ppu_fs uses), and log one line per file:
 *   [PROBE] run=<id> op=<n> file=<rel> sha256=<hex>   [RESTORECHK] run=<id> <rel> <hex>
 *   [RESTORECHK] run=<id> count=<n>   [PROBE] run=<id> done op=<op> rc=<0|1>
 * Pure POSIX C: tested on the Mac with temp dirs. */
#ifndef GOW2_ANDROID_PROBE_H
#define GOW2_ANDROID_PROBE_H

#include <stdio.h>
#include "gow2_android_config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 1 when `path` (existing or not) resolves -- through every existing symlink of its parent
 * chain -- to <root>/probe/<something>; 0 otherwise ("..", "probex", symlink escapes). */
int gow2_probe_path_ok(const char* root, const char* path);

/* Deterministic bytes (xorshift64*) -- the app side of op 6/9/11's files. */
void gow2_probe_fill(unsigned char* buf, size_t n, unsigned long long seed);

/* Runs a->probe. `root` = the candidate dir for transport (--root), p = resolved paths for
 * restore_check / drill. Returns 0 when every step ran (hash comparison happens on the Mac). */
int gow2_probe_run(const gow2_android_args* a, const char* root, const gow2_android_paths* p, FILE* log);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_ANDROID_PROBE_H */
