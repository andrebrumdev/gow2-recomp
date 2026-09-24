/* GoW2 iOS host: KEY=VALUE configuration files exported with setenv() before
 * any guest code runs (spec 2026-09-24 iOS, resolution 1). */
#ifndef GOW2_ENV_FILE_H
#define GOW2_ENV_FILE_H

#ifdef __cplusplus
extern "C" {
#endif

/* '#' comments (leading blanks before the '#' are allowed) and blank/
 * whitespace-only lines are skipped, CRLF is accepted, keys must match
 * [A-Z_][A-Z0-9_]* starting at column 0 (a leading space/tab before the key
 * itself is a malformed line, not a comment), the value is the rest of the
 * line (may be empty).
 *
 * Duplicate keys within the same call: with overwrite == 0 the FIRST value
 * assigned during this call wins -- once a key is set (by an earlier line in
 * this text, or already present in the launch environment), later lines for
 * the same key are silently skipped (neither applied nor rejected). With
 * overwrite == 1 every line unconditionally re-applies, so the LAST value in
 * the text wins.
 *
 * *applied = variables set by this call; *rejected = malformed lines.
 * 0 = parsed; -1 = NULL text. */
int gow2_env_apply_text(const char* text, int overwrite, int* applied, int* rejected);

/* Same over a file. -1 when it cannot be read, is larger than 64 KB, hits a
 * read error partway through (e.g. path names a directory), or contains an
 * embedded NUL byte (rejected outright -- never silently truncated at it). */
int gow2_env_apply_file(const char* path, int overwrite, int* applied, int* rejected);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_ENV_FILE_H */
