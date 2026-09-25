/* GoW2 iOS host policies (P2); see gow2_ios_ui_policy.h. */
#include "gow2_ios_ui_policy.h"

#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

unsigned gow2_ios_thermal_fps_cap(int thermal_state, const char* override)
{
    unsigned serious = 20, critical = 15;
    if (override != NULL && override[0] != '\0') {
        unsigned s = 0, c = 0;
        char tail = 0;
        if (strcmp(override, "0") == 0)
            return 0;
        if (sscanf(override, "%u:%u%c", &s, &c, &tail) == 2 && s >= 1 && s <= 60 && c >= 1 && c <= 60) {
            serious = s;
            critical = c;
        }
    }
    if (thermal_state == 2) return serious;
    if (thermal_state >= 3) return critical;
    return 0;
}

static const char* find(const char* hay, size_t n, const char* needle)
{
    const size_t k = strlen(needle);
    for (size_t i = 0; k <= n && i <= n - k; ++i)
        if (memcmp(hay + i, needle, k) == 0)
            return hay + i;
    return NULL;
}

/* Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant). */
static long long days_from_civil(int y, unsigned m, unsigned d)
{
    y -= m <= 2;
    const long long era = (y >= 0 ? y : y - 399) / 400;
    const unsigned yoe = (unsigned)(y - era * 400);
    const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + (long long)doe - 719468;
}

long long gow2_ios_provision_expiry(const char* bytes, size_t n)
{
    if (bytes == NULL)
        return 0;
    const char* key = find(bytes, n, "<key>ExpirationDate</key>");
    if (key == NULL)
        return 0;
    const size_t rest = n - (size_t)(key - bytes);
    const char* date = find(key, rest, "<date>");
    if (date == NULL || (size_t)(date - bytes) + 6 + 20 > n)
        return 0;
    char text[21];
    memcpy(text, date + 6, 20);
    text[20] = '\0';
    int y, mo, d, h, mi, s;
    char z = 0;
    if (sscanf(text, "%4d-%2d-%2dT%2d:%2d:%2d%c", &y, &mo, &d, &h, &mi, &s, &z) != 7 || z != 'Z' ||
        mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 60 || y < 2000)
        return 0;
    return days_from_civil(y, (unsigned)mo, (unsigned)d) * 86400LL + h * 3600LL + mi * 60LL + s;
}

long long gow2_ios_latest_save_mtime(const char* root)
{
    long long newest = 0;
    char dir[2048], file[4096];
    struct stat st;
    DIR* r = root != NULL ? opendir(root) : NULL;
    if (r == NULL)
        return 0;
    struct dirent* e;
    while ((e = readdir(r)) != NULL) {
        if (e->d_name[0] == '.')
            continue;
        snprintf(dir, sizeof dir, "%s/%s", root, e->d_name);
        if (stat(dir, &st) != 0 || !S_ISDIR(st.st_mode))
            continue;
        DIR* s = opendir(dir);
        if (s == NULL)
            continue;
        struct dirent* f;
        while ((f = readdir(s)) != NULL) {
            if (f->d_name[0] == '.')
                continue;
            snprintf(file, sizeof file, "%s/%s", dir, f->d_name);
            if (stat(file, &st) == 0 && S_ISREG(st.st_mode) && (long long)st.st_mtime > newest)
                newest = (long long)st.st_mtime;
        }
        closedir(s);
    }
    closedir(r);
    return newest;
}

unsigned gow2_ios_memory_ceiling_mb(unsigned long long footprint, unsigned long long available)
{
    return (unsigned)((footprint + available) >> 20);
}
