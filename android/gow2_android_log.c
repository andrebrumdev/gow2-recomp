/* GoW2 Android log tee + fatal-signal line; see gow2_android_host.h. Shared by the game and
 * the lift-free probe APK. */
#include "gow2_android_host.h"

#include <android/log.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int s_log_fd = -1, s_pipe_r = -1;
static pthread_mutex_t s_emit_mu = PTHREAD_MUTEX_INITIALIZER;
static char s_line[4096];
static size_t s_used;

static void emit_locked(const char* buf, size_t n)
{
    if (s_log_fd >= 0) (void)!write(s_log_fd, buf, n);
    for (size_t i = 0; i < n; i++) {           /* logcat: one entry per line */
        if (buf[i] == '\n' || s_used == sizeof s_line - 1) {
            s_line[s_used] = 0;
            __android_log_write(ANDROID_LOG_INFO, "gow2", s_line);
            s_used = 0;
            if (buf[i] == '\n') continue;
        }
        s_line[s_used++] = buf[i];
    }
}

static void emit(const char* buf, size_t n)
{
    pthread_mutex_lock(&s_emit_mu);
    emit_locked(buf, n);
    pthread_mutex_unlock(&s_emit_mu);
}

static void* tee_thread(void* arg)
{
    const int rfd = (int)(intptr_t)arg;
    char buf[65536];
    pthread_setname_np(pthread_self(), "gow2-logtee");
    for (;;) {
        const ssize_t n = read(rfd, buf, sizeof buf);
        if (n > 0) { emit(buf, (size_t)n); continue; }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && errno == EAGAIN) {
            struct pollfd pf = { .fd = rfd, .events = POLLIN, .revents = 0 };
            if (poll(&pf, 1, -1) < 0 && errno != EINTR) break;
            continue;
        }
        break;
    }
    return NULL;
}

static uint64_t mono_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000u + (uint64_t)t.tv_nsec / 1000000u;
}

/* Before _exit: drain the pipe into the file AND logcat (the scripts wait for the last
 * lines there), bounded at ~300 ms, then push out a partial last line. */
void gow2_android_log_flush(void)
{
    if (s_pipe_r < 0) return;
    const int fl = fcntl(s_pipe_r, F_GETFL);
    if (fl >= 0) (void)fcntl(s_pipe_r, F_SETFL, fl | O_NONBLOCK);
    const uint64_t deadline = mono_ms() + 300;
    char buf[4096];
    while (mono_ms() < deadline) {
        const ssize_t n = read(s_pipe_r, buf, sizeof buf);
        if (n > 0) { emit(buf, (size_t)n); continue; }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && errno == EAGAIN) { usleep(20000); continue; }   /* the tee thread may still be writing */
        break;
    }
    pthread_mutex_lock(&s_emit_mu);
    if (s_used) { s_line[s_used] = 0; __android_log_write(ANDROID_LOG_INFO, "gow2", s_line); s_used = 0; }
    pthread_mutex_unlock(&s_emit_mu);
}

static const int k_fatal_sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP };

/* One fixed line to the log file (write(2) only: async-signal-safe), then the default action.
 * Installed before the runtime's SPU/OPD handlers, which chain here for faults they do not own;
 * ART's libsigchain keeps its own handlers in front of all of ours. */
static void fatal_signal_handler(int sig, siginfo_t* si, void* uc)
{
    (void)si; (void)uc;
    char line[] = "[android] fatal signal NN\n";
    line[sizeof line - 4] = (char)('0' + (sig / 10) % 10);
    line[sizeof line - 3] = (char)('0' + sig % 10);
    if (s_log_fd >= 0) (void)!write(s_log_fd, line, sizeof line - 1);
    struct sigaction dfl;
    memset(&dfl, 0, sizeof dfl);
    dfl.sa_handler = SIG_DFL;
    sigemptyset(&dfl.sa_mask);
    sigaction(sig, &dfl, NULL);
    raise(sig);
}

void gow2_android_log_begin(const char* log_path, int append)
{
    s_log_fd = open(log_path, O_WRONLY | O_CREAT | (append ? O_APPEND : O_TRUNC), 0644);
    int p[2];
    if (pipe(p) == 0) {
        dup2(p[1], 1);
        dup2(p[1], 2);
        close(p[1]);
        s_pipe_r = p[0];
        pthread_t t;
        if (pthread_create(&t, NULL, tee_thread, (void*)(intptr_t)p[0]) == 0) pthread_detach(t);
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = fatal_signal_handler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    for (size_t i = 0; i < sizeof k_fatal_sigs / sizeof k_fatal_sigs[0]; i++) sigaction(k_fatal_sigs[i], &sa, NULL);
    fprintf(stderr, "[android] log=%s pid=%d\n", log_path, (int)getpid());
}
