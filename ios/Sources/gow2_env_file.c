/* GoW2 iOS host: configuration files; see gow2_env_file.h. */
#include "gow2_env_file.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GOW2_ENV_MAX_BYTES (64 * 1024)

static int key_ok(const char* k, size_t n)
{
    if (n == 0 || !((k[0] >= 'A' && k[0] <= 'Z') || k[0] == '_')) return 0;
    for (size_t i = 1; i < n; i++)
        if (!((k[i] >= 'A' && k[i] <= 'Z') || (k[i] >= '0' && k[i] <= '9') || k[i] == '_')) return 0;
    return 1;
}

int gow2_env_apply_text(const char* text, int overwrite, int* applied, int* rejected)
{
    int a = 0, r = 0;
    if (applied) *applied = 0;
    if (rejected) *rejected = 0;
    if (!text) return -1;
    const char* p = text;
    while (*p) {
        const char* eol = strchr(p, '\n');
        const size_t len = eol ? (size_t)(eol - p) : strlen(p);
        size_t n = len;
        if (n && p[n - 1] == '\r') n--;
        /* An indented '#' is still a comment; leading blanks alone are still a
         * blank line. Neither is counted as rejected. A key must start at
         * column 0 -- an indented KEY=VALUE stays rejected (key_ok fails on
         * the leading space/tab below), matching the plan's " G2T_LEAD=1". */
        size_t skip = 0;
        while (skip < n && (p[skip] == ' ' || p[skip] == '\t')) skip++;
        const int is_comment_or_blank = (skip == n) || (p[skip] == '#');
        if (n && !is_comment_or_blank) {
            const char* eq = memchr(p, '=', n);
            char key[128], val[4096];
            const size_t kn = eq ? (size_t)(eq - p) : 0;
            const size_t vn = eq ? n - kn - 1 : 0;
            if (!eq || kn >= sizeof key || vn >= sizeof val || !key_ok(p, kn)) {
                r++;
            } else {
                memcpy(key, p, kn);
                key[kn] = 0;
                memcpy(val, eq + 1, vn);
                val[vn] = 0;
                if ((overwrite || !getenv(key)) && setenv(key, val, 1) == 0) a++;
            }
        }
        p += len + (eol ? 1 : 0);
    }
    if (applied) *applied = a;
    if (rejected) *rejected = r;
    return 0;
}

int gow2_env_apply_file(const char* path, int overwrite, int* applied, int* rejected)
{
    if (applied) *applied = 0;
    if (rejected) *rejected = 0;
    FILE* f = path ? fopen(path, "rb") : NULL;
    if (!f) return -1;
    char* buf = (char*)malloc(GOW2_ENV_MAX_BYTES + 1);
    const size_t n = buf ? fread(buf, 1, GOW2_ENV_MAX_BYTES + 1, f) : 0;
    const int had_error = ferror(f);   /* e.g. path names a directory (EISDIR) */
    fclose(f);
    if (!buf || had_error || n > GOW2_ENV_MAX_BYTES) {
        free(buf);
        return -1;
    }
    if (memchr(buf, 0, n)) {
        /* Embedded NUL: not text. Reject outright instead of silently
         * applying only the prefix up to the NUL. */
        free(buf);
        return -1;
    }
    buf[n] = 0;
    const int rc = gow2_env_apply_text(buf, overwrite, applied, rejected);
    free(buf);
    return rc;
}
