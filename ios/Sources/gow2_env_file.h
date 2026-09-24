/* GoW2 iOS host: KEY=VALUE configuration files exported with setenv() before
 * any guest code runs (spec 2026-09-24 iOS, resolution 1). */
#ifndef GOW2_ENV_FILE_H
#define GOW2_ENV_FILE_H

#ifdef __cplusplus
extern "C" {
#endif

/* '#' comments and blank lines are skipped, CRLF is accepted, keys must match
 * [A-Z_][A-Z0-9_]*, the value is the rest of the line (may be empty). With
 * overwrite == 0 a variable that is already set keeps its value and is not
 * counted. *applied = variables set by this call; *rejected = malformed lines.
 * 0 = parsed; -1 = NULL text. */
int gow2_env_apply_text(const char* text, int overwrite, int* applied, int* rejected);

/* Same over a file. -1 when it cannot be read or is larger than 64 KB. */
int gow2_env_apply_file(const char* path, int overwrite, int* applied, int* rejected);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_ENV_FILE_H */
