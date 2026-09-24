/* GoW2 iOS host policies; see gow2_ios_lifecycle.h. */
#include "gow2_ios_lifecycle.h"
#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#if defined(__APPLE__)
#include <sys/qos.h>
#endif

/* The lifecycle is main-thread only (header: host contract). Debug builds on
 * Apple check it; release builds and other platforms compile it away. */
#if defined(__APPLE__) && !defined(NDEBUG)
#include <assert.h>
#include <pthread.h>
#define LC_ASSERT_MAIN() assert(pthread_main_np() != 0)
#else
#define LC_ASSERT_MAIN() ((void)0)
#endif

static gow2_lifecycle_ops s_ops;
static gow2_lifecycle_state s_st = { 1, 0, 0, 0, 1 };

/* Order matters: render first, so the GPU gate is closed (resign) / reopened
 * (resume) before audio and input change. */
static void apply(void)
{
    const int render = !s_st.active;
    const int audio = !s_st.active || s_st.interrupted;
    if (render != s_st.render_suspended) {
        s_st.render_suspended = render;
        if (s_ops.set_render_suspended) s_ops.set_render_suspended(render);
    }
    if (audio != s_st.audio_suspended) {
        s_st.audio_suspended = audio;
        if (s_ops.set_audio_suspended) s_ops.set_audio_suspended(audio);
    }
    if (s_st.active != s_st.input_active) {
        s_st.input_active = s_st.active;
        if (s_ops.set_input_active) s_ops.set_input_active(s_st.active);
    }
}

void gow2_lifecycle_init(const gow2_lifecycle_ops* ops)
{
    LC_ASSERT_MAIN();
    memset(&s_ops, 0, sizeof s_ops);
    if (ops) s_ops = *ops;
    s_st.active = 1;
    s_st.interrupted = 0;
    s_st.render_suspended = 0;
    s_st.audio_suspended = 0;
    s_st.input_active = 1;
}

void gow2_lifecycle_will_resign_active(void) { LC_ASSERT_MAIN(); s_st.active = 0; apply(); }
void gow2_lifecycle_did_become_active(void) { LC_ASSERT_MAIN(); s_st.active = 1; apply(); }
void gow2_lifecycle_audio_interruption(int began)
{
    LC_ASSERT_MAIN();
    s_st.interrupted = began ? 1 : 0;
    apply();
}
void gow2_lifecycle_memory_warning(void) { LC_ASSERT_MAIN(); if (s_ops.trim_caches) s_ops.trim_caches(); }
gow2_lifecycle_state gow2_lifecycle_get(void) { return s_st; }

int gow2_ios_qos_from_string(const char* s, int* qos_out)
{
#if defined(__APPLE__)
    static const struct { const char* name; qos_class_t q; } k[] = {
        { "interactive", QOS_CLASS_USER_INTERACTIVE },
        { "initiated", QOS_CLASS_USER_INITIATED },
        { "default", QOS_CLASS_DEFAULT },
        { "utility", QOS_CLASS_UTILITY },
    };
    if (s && qos_out)
        for (size_t i = 0; i < sizeof k / sizeof k[0]; i++)
            if (strcmp(s, k[i].name) == 0) { *qos_out = (int)k[i].q; return 1; }
#else
    (void)s; (void)qos_out;
#endif
    return 0;
}

int gow2_ios_game_data_present(const char* eboot, const char* usrdir)
{
    struct stat st;
    if (!eboot || !usrdir || stat(eboot, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size == 0) return 0;
    DIR* d = opendir(usrdir);
    if (!d) return 0;
    int ok = 0;
    char p[2048];
    struct dirent* e;
    while (!ok && (e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(p, sizeof p, "%s/%s", usrdir, e->d_name);
        if (stat(p, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0) ok = 1;
    }
    closedir(d);
    return ok;
}
