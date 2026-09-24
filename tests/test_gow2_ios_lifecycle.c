/* iOS host policies: lifecycle transitions, QoS names, partial installs. */
#include "gow2_ios_lifecycle.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <sys/qos.h>
#endif

static int g_fail;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); g_fail++; } } while (0)

static char g_ev[256];
static void ev(const char* s) { strncat(g_ev, s, sizeof g_ev - strlen(g_ev) - 1); }
static void r_set(int on) { ev(on ? "R1 " : "R0 "); }
static void a_set(int on) { ev(on ? "A1 " : "A0 "); }
static void i_set(int on) { ev(on ? "I1 " : "I0 "); }
static void trim(void) { ev("T "); }
static const gow2_lifecycle_ops k_ops = { r_set, a_set, i_set, trim };
static void start(void) { gow2_lifecycle_init(&k_ops); g_ev[0] = 0; }

static void test_resign_and_resume(void)
{
    start();
    CHECK(g_ev[0] == 0);
    gow2_lifecycle_will_resign_active();
    CHECK(strcmp(g_ev, "R1 A1 I0 ") == 0);
    gow2_lifecycle_will_resign_active();                 /* repeated: no calls */
    CHECK(strcmp(g_ev, "R1 A1 I0 ") == 0);
    g_ev[0] = 0;
    gow2_lifecycle_did_become_active();
    CHECK(strcmp(g_ev, "R0 A0 I1 ") == 0);
}

static void test_interruption_while_active(void)
{
    start();
    gow2_lifecycle_audio_interruption(1);
    CHECK(strcmp(g_ev, "A1 ") == 0);
    gow2_lifecycle_audio_interruption(0);
    CHECK(strcmp(g_ev, "A1 A0 ") == 0);
}

static void test_interruption_ends_while_inactive(void)
{
    start();
    gow2_lifecycle_audio_interruption(1);                /* Siri */
    gow2_lifecycle_will_resign_active();                 /* then Control Center */
    CHECK(strcmp(g_ev, "A1 R1 I0 ") == 0);
    g_ev[0] = 0;
    gow2_lifecycle_audio_interruption(0);                /* Siri ends while inactive */
    CHECK(g_ev[0] == 0);                                 /* audio stays off, render stays off */
    gow2_lifecycle_state s = gow2_lifecycle_get();
    CHECK(s.audio_suspended == 1 && s.render_suspended == 1 && s.interrupted == 0);
    gow2_lifecycle_did_become_active();
    CHECK(strcmp(g_ev, "R0 A0 I1 ") == 0);
}

static void test_active_while_still_interrupted(void)
{
    start();
    gow2_lifecycle_will_resign_active();
    gow2_lifecycle_audio_interruption(1);
    g_ev[0] = 0;
    gow2_lifecycle_did_become_active();
    CHECK(strcmp(g_ev, "R0 I1 ") == 0);                  /* audio waits for the interruption end */
    gow2_lifecycle_audio_interruption(0);
    CHECK(strcmp(g_ev, "R0 I1 A0 ") == 0);
}

static void test_memory_warning(void)
{
    start();
    gow2_lifecycle_memory_warning();
    CHECK(strcmp(g_ev, "T ") == 0);
    gow2_lifecycle_init(NULL);                           /* no ops: nothing to call, no crash */
    gow2_lifecycle_will_resign_active();
    gow2_lifecycle_memory_warning();
}

static void test_qos_names(void)
{
    int q = -1;
    CHECK(gow2_ios_qos_from_string(NULL, &q) == 0);
    CHECK(gow2_ios_qos_from_string("", &q) == 0);
    CHECK(gow2_ios_qos_from_string("inherit", &q) == 0);
    CHECK(gow2_ios_qos_from_string("bogus", &q) == 0);
#if defined(__APPLE__)
    CHECK(gow2_ios_qos_from_string("interactive", &q) == 1 && q == (int)QOS_CLASS_USER_INTERACTIVE);
    CHECK(gow2_ios_qos_from_string("initiated", &q) == 1 && q == (int)QOS_CLASS_USER_INITIATED);
    CHECK(gow2_ios_qos_from_string("default", &q) == 1 && q == (int)QOS_CLASS_DEFAULT);
    CHECK(gow2_ios_qos_from_string("utility", &q) == 1 && q == (int)QOS_CLASS_UTILITY);
#endif
}

static void write_file(const char* p, const char* body)
{
    FILE* f = fopen(p, "wb");
    if (f) { fputs(body, f); fclose(f); }
}

static void test_game_data_present_rejects_partial_installs(void)
{
    char root[] = "/tmp/g2t_dataXXXXXX";
    CHECK(mkdtemp(root) != NULL);
    char eboot[512], usr[512], psarc[512];
    snprintf(eboot, sizeof eboot, "%s/EBOOT.ELF", root);
    snprintf(usr, sizeof usr, "%s/USRDIR", root);
    snprintf(psarc, sizeof psarc, "%s/gow2.psarc", usr);
    CHECK(gow2_ios_game_data_present(eboot, usr) == 0);          /* nothing */
    write_file(eboot, "");
    mkdir(usr, 0755);
    CHECK(gow2_ios_game_data_present(eboot, usr) == 0);          /* EBOOT empty, USRDIR empty */
    write_file(eboot, "ELF");
    CHECK(gow2_ios_game_data_present(eboot, usr) == 0);          /* USRDIR still empty */
    write_file(psarc, "PSAR");
    CHECK(gow2_ios_game_data_present(eboot, usr) == 1);
    unlink(eboot);
    CHECK(gow2_ios_game_data_present(eboot, usr) == 0);          /* EBOOT missing */
    mkdir(eboot, 0755);
    CHECK(gow2_ios_game_data_present(eboot, usr) == 0);          /* EBOOT is a directory */
    CHECK(gow2_ios_game_data_present(NULL, usr) == 0);
    rmdir(eboot); unlink(psarc); rmdir(usr); rmdir(root);
}

int main(void)
{
    test_resign_and_resume();
    test_interruption_while_active();
    test_interruption_ends_while_inactive();
    test_active_while_still_interrupted();
    test_memory_warning();
    test_qos_names();
    test_game_data_present_rejects_partial_installs();
    printf(g_fail ? "test_gow2_ios_lifecycle: FAIL %d\n" : "test_gow2_ios_lifecycle: PASS\n", g_fail);
    return g_fail ? 1 : 0;
}
