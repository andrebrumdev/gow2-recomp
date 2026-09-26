/* GoW2 iOS: is the game installed? The Mac launcher ("Instalar no iPhone",
 * P3) copies EBOOT.ELF, USRDIR/ and movie_cache/ into the container's
 * Documents, verifies every file (size + mtime on the phone; small files also
 * by downloading and hashing them; large files through the Mac's pushed-hash
 * record) and writes Documents/gow2-install.manifest LAST; while a copy runs
 * the manifest is an "incomplete" marker. The game starts only when the
 * manifest is complete, internally consistent and every listed file exists
 * with its listed size, so a torn or interrupted copy reads as not
 * installed. The app does not re-hash 7 GB. Pure C: tested on the Mac. */
#ifndef GOW2_IOS_INSTALL_MANIFEST_H
#define GOW2_IOS_INSTALL_MANIFEST_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define GOW2_INSTALL_MANIFEST_NAME "gow2-install.manifest"

typedef enum gow2_install_state {
    GOW2_INSTALL_MISSING = 0,    /* no manifest and no EBOOT.ELF: never installed */
    GOW2_INSTALL_OK = 1,
    GOW2_INSTALL_INCOMPLETE = 2  /* data without a complete manifest, a malformed manifest,
                                    or a listed file missing / wrong size */
} gow2_install_state;

/* Format (IOSInstallManifest.swift writes it), every line ending in '\n':
 *   gow2-install 1
 *   set <64 hex>     exactly once, before any file line: SHA-256 of the
 *                    "<size> <sha256> <path>\n" parts of the file lines, in order
 *   file <size> <64 hex sha256> <path relative to Documents>
 *                    paths strictly ascending in byte order (so no duplicates)
 *   end <number of file lines>
 * It must list EBOOT.ELF and at least one USRDIR/ file. `why` (optional)
 * receives one log line when the state is not OK, "" when it is. */
gow2_install_state gow2_ios_install_state(const char* docs, char* why, size_t why_cap);

/* 1 when gow2_ios_install_state(docs, NULL, 0) == GOW2_INSTALL_OK. */
int gow2_ios_game_data_present(const char* docs);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_IOS_INSTALL_MANIFEST_H */
