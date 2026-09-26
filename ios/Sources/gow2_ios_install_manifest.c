/* GoW2 iOS install manifest check; see gow2_ios_install_manifest.h. */
#include "gow2_ios_install_manifest.h"

#include <CommonCrypto/CommonDigest.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define MAX_FILES 4096

static void say(char* why, size_t cap, const char* fmt, ...)
{
    if (why == NULL || cap == 0)
        return;
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(why, cap, fmt, ap);
    va_end(ap);
}

/* Relative; no empty, "." or ".." component; no backslash. */
static int rel_ok(const char* p)
{
    if (p[0] == '\0' || p[0] == '/' || strchr(p, '\\') != NULL)
        return 0;
    const char* s = p;
    for (;;) {
        const char* e = strchr(s, '/');
        const size_t n = e ? (size_t)(e - s) : strlen(s);
        if (n == 0 || (n == 1 && s[0] == '.') || (n == 2 && s[0] == '.' && s[1] == '.'))
            return 0;
        if (e == NULL)
            return 1;
        s = e + 1;
    }
}

static int is_hex64(const char* s)
{
    for (int i = 0; i < 64; i++)
        if (!((s[i] >= '0' && s[i] <= '9') || (s[i] >= 'a' && s[i] <= 'f')))
            return 0;
    return 1;
}

gow2_install_state gow2_ios_install_state(const char* docs, char* why, size_t cap)
{
    char path[2048], line[1400], prev[1400] = "", set_hex[65] = "";
    struct stat st;
    say(why, cap, "%s", "");
    if (docs == NULL) {
        say(why, cap, "no Documents directory");
        return GOW2_INSTALL_MISSING;
    }
    if (snprintf(path, sizeof path, "%s/%s", docs, GOW2_INSTALL_MANIFEST_NAME) >= (int)sizeof path) {
        say(why, cap, "Documents path too long");
        return GOW2_INSTALL_MISSING;
    }
    FILE* f = fopen(path, "rb");
    if (f == NULL) {
        snprintf(path, sizeof path, "%s/EBOOT.ELF", docs);
        if (stat(path, &st) == 0) {
            say(why, cap, "no %s (data copied without the launcher)", GOW2_INSTALL_MANIFEST_NAME);
            return GOW2_INSTALL_INCOMPLETE;
        }
        say(why, cap, "not installed");
        return GOW2_INSTALL_MISSING;
    }
    int header = 0, have_set = 0, ended = 0, files = 0, have_eboot = 0, have_usrdir = 0;
    CC_SHA256_CTX digest;
    CC_SHA256_Init(&digest);
    gow2_install_state state = GOW2_INSTALL_OK;
    while (state == GOW2_INSTALL_OK && fgets(line, sizeof line, f) != NULL) {
        size_t len = strlen(line);
        if (len == 0 || line[len - 1] != '\n') {
            say(why, cap, "manifest: truncated or overlong line");
            state = GOW2_INSTALL_INCOMPLETE;
            break;
        }
        line[--len] = '\0';
        if (ended) {
            say(why, cap, "manifest: data after the end line");
            state = GOW2_INSTALL_INCOMPLETE;
        } else if (!header) {
            if (strcmp(line, "gow2-install 1") != 0) {
                say(why, cap, "manifest: unknown header");
                state = GOW2_INSTALL_INCOMPLETE;
            }
            header = 1;
        } else if (strncmp(line, "set ", 4) == 0) {
            if (have_set || files > 0 || len != 68 || !is_hex64(line + 4)) {
                say(why, cap, "manifest: set line repeated, misplaced or malformed");
                state = GOW2_INSTALL_INCOMPLETE;
            }
            memcpy(set_hex, line + 4, 64);
            set_hex[64] = '\0';
            have_set = 1;
        } else if (strncmp(line, "file ", 5) == 0) {
            char* end = NULL;
            const long long size = strtoll(line + 5, &end, 10);
            if (!have_set || end == line + 5 || size < 0 || *end != ' ' || strlen(end + 1) < 66 || !is_hex64(end + 1) ||
                end[65] != ' ') {
                say(why, cap, "manifest: malformed file line (or no set line before it)");
                state = GOW2_INSTALL_INCOMPLETE;
                break;
            }
            const char* rel = end + 66;
            if (!rel_ok(rel) || ++files > MAX_FILES ||
                snprintf(path, sizeof path, "%s/%s", docs, rel) >= (int)sizeof path) {
                say(why, cap, "manifest: unsafe or too many paths");
                state = GOW2_INSTALL_INCOMPLETE;
                break;
            }
            if (files > 1 && strcmp(prev, rel) >= 0) {
                say(why, cap, "manifest: paths not strictly sorted (duplicate %s?)", rel);
                state = GOW2_INSTALL_INCOMPLETE;
                break;
            }
            snprintf(prev, sizeof prev, "%s", rel);
            CC_SHA256_Update(&digest, line + 5, (CC_LONG)(len - 5));
            CC_SHA256_Update(&digest, "\n", 1);
            if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) {
                say(why, cap, "%s: missing", rel);
                state = GOW2_INSTALL_INCOMPLETE;
            } else if ((long long)st.st_size != size) {
                say(why, cap, "%s: %lld bytes, manifest says %lld", rel, (long long)st.st_size, size);
                state = GOW2_INSTALL_INCOMPLETE;
            }
            if (strcmp(rel, "EBOOT.ELF") == 0)
                have_eboot = 1;
            if (strncmp(rel, "USRDIR/", 7) == 0)
                have_usrdir = 1;
        } else if (strncmp(line, "end ", 4) == 0) {
            char* end = NULL;
            const long n = strtol(line + 4, &end, 10);
            if (end == line + 4 || *end != '\0' || n != files) {
                say(why, cap, "manifest: end count %ld != %d files", n, files);
                state = GOW2_INSTALL_INCOMPLETE;
            }
            ended = 1;
        } else {
            say(why, cap, "manifest: unexpected line (copy in progress or interrupted)");
            state = GOW2_INSTALL_INCOMPLETE;
        }
    }
    fclose(f);
    if (state != GOW2_INSTALL_OK)
        return state;
    if (!ended) {
        say(why, cap, "manifest: no end line (copy in progress or interrupted)");
        return GOW2_INSTALL_INCOMPLETE;
    }
    if (!have_set) {
        say(why, cap, "manifest: no set line");
        return GOW2_INSTALL_INCOMPLETE;
    }
    unsigned char d[CC_SHA256_DIGEST_LENGTH];
    char hex[65];
    CC_SHA256_Final(d, &digest);
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        snprintf(hex + 2 * i, 3, "%02x", d[i]);
    if (strcmp(hex, set_hex) != 0) {
        say(why, cap, "manifest: set digest does not match the file list");
        return GOW2_INSTALL_INCOMPLETE;
    }
    if (!have_eboot || !have_usrdir) {
        say(why, cap, "manifest: lists no EBOOT.ELF or no USRDIR file");
        return GOW2_INSTALL_INCOMPLETE;
    }
    return GOW2_INSTALL_OK;
}

int gow2_ios_game_data_present(const char* docs)
{
    return gow2_ios_install_state(docs, NULL, 0) == GOW2_INSTALL_OK;
}
