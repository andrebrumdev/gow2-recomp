/* GoW2 iOS host glue; see gow2_ios_host.h. */
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Metal/Metal.h>
#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <os/proc.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/qos.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <SDL2/SDL.h>

#include "gow2_boot.h"
#include "gow2_env_file.h"
#include "gow2_ios_host.h"
#include "gow2_ios_lifecycle.h"
#include "rsx_gpu_gate.h"
#include "rsx_metal_backend.h"
#include "cellAudio.h"
#include "cellpad_gamecontroller.h"

static char s_docs[1024];
static int s_log_fd = -1, s_orig_stdout = -1, s_pipe_r = -1;

const char* gow2_ios_documents(void) { return s_docs; }

static void* tee_thread(void* arg)
{
    const int rfd = (int)(intptr_t)arg;
    char buf[65536];
    for (;;) {
        const ssize_t n = read(rfd, buf, sizeof buf);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            if (n < 0 && errno == EAGAIN) {   /* flush_log_for_exit made the pipe non-blocking */
                struct pollfd pf = { .fd = rfd, .events = POLLIN, .revents = 0 };
                const int pr = poll(&pf, 1, -1);
                if (pr < 0 && errno == EINTR) continue;
                if (pr < 0 || ((pf.revents & (POLLERR | POLLNVAL)) && !(pf.revents & POLLIN))) break;
                continue;
            }
            break;
        }
        if (s_log_fd >= 0) (void)!write(s_log_fd, buf, (size_t)n);
        if (s_orig_stdout >= 0) (void)!write(s_orig_stdout, buf, (size_t)n);   /* devicectl --console */
    }
    return NULL;
}

/* A line straight to the log file (never the original stdout, which may
 * block); async-signal-safe: only write(). */
static void log_fd_write(const char* msg, size_t n)
{
    if (s_log_fd >= 0) (void)!write(s_log_fd, msg, n);
}

static uint64_t mono_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000u + (uint64_t)t.tv_nsec / 1000000u;
}

/* Before _exit / on willTerminate: move what is still in the tee pipe into
 * the log file. The read end is made non-blocking (the tee thread copes with
 * EAGAIN), so neither side can park here; the whole drain has one ~300 ms
 * deadline. No stdio flush: stdout/stderr lead to the pipe, which may be full. */
static void flush_log_for_exit(void)
{
    if (s_pipe_r < 0) return;
    const int fl = fcntl(s_pipe_r, F_GETFL);
    if (fl >= 0) (void)fcntl(s_pipe_r, F_SETFL, fl | O_NONBLOCK);
    const uint64_t deadline = mono_ms() + 300;
    char buf[4096];
    while (mono_ms() < deadline) {
        const ssize_t n = read(s_pipe_r, buf, sizeof buf);
        if (n > 0) {
            log_fd_write(buf, (size_t)n);
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        break;   /* EAGAIN = empty (the tee may hold the last chunk: it writes it itself), or EOF/error */
    }
}

static const int k_fatal_sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP };

/* Installed before gow2_boot_prepare, so the runtime's own SIGSEGV/SIGBUS
 * handlers (SPU jobs, OPD) are installed on top and chain here when they do
 * not handle the fault. Only one fixed line is written straight to the log
 * file (no pipe drain: the tee thread could race it and block the handler),
 * then the default action is restored and the signal re-raised. */
static void fatal_signal_handler(int sig, siginfo_t* si, void* uc)
{
    (void)si;
    (void)uc;
    char line[] = "[ios] fatal signal NN\n";
    line[sizeof line - 4] = (char)('0' + (sig / 10) % 10);
    line[sizeof line - 3] = (char)('0' + sig % 10);
    log_fd_write(line, sizeof line - 1);
    struct sigaction dfl;
    memset(&dfl, 0, sizeof dfl);
    dfl.sa_handler = SIG_DFL;
    sigemptyset(&dfl.sa_mask);
    sigaction(sig, &dfl, NULL);
    raise(sig);
}

static void install_fatal_signal_log(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = fatal_signal_handler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    for (size_t i = 0; i < sizeof k_fatal_sigs / sizeof k_fatal_sigs[0]; i++)
        sigaction(k_fatal_sigs[i], &sa, NULL);
}

/* Logged once: the A15 is expected to report NO (the backend then decodes BC
 * to RGBA8 on the GPU, "[RSX metal] BC textures: decode to RGBA8"). */
static void log_gpu_bc_support(void)
{
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    int bc = -1;   /* -1 = API unavailable before iOS 16.4 */
    if (@available(macOS 11.0, iOS 16.4, *)) bc = d.supportsBCTextureCompression ? 1 : 0;
    fprintf(stderr, "[ios] MTLDevice %s supportsBCTextureCompression=%d\n",
            d ? d.name.UTF8String : "(none)", bc);
}

void gow2_ios_host_early(void)
{
    NSString* d = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    snprintf(s_docs, sizeof s_docs, "%s", d.fileSystemRepresentation);
    if (chdir(s_docs) != 0) fprintf(stderr, "[ios] chdir %s: %s\n", s_docs, strerror(errno));
    char lp[1100];
    snprintf(lp, sizeof lp, "%s/gow2.log", s_docs);
    s_log_fd = open(lp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    s_orig_stdout = dup(1);
    int p[2];
    if (s_log_fd >= 0 && pipe(p) == 0) {
        dup2(p[1], 1);
        dup2(p[1], 2);
        close(p[1]);
        s_pipe_r = p[0];
        pthread_t t;
        if (pthread_create(&t, NULL, tee_thread, (void*)(intptr_t)p[0]) == 0) pthread_detach(t);
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    fprintf(stderr, "[ios] documents=%s pid=%d available_mb=%zu\n", s_docs, getpid(),
            os_proc_available_memory() >> 20);
    install_fatal_signal_log();
    log_gpu_bc_support();
}

static void apply_config_file(const char* path, int required, int* rc)
{
    int applied = 0, rejected = 0;
    if (gow2_env_apply_file(path, 0, &applied, &rejected) != 0) {
        const int err = errno;
        struct stat st;
        if (stat(path, &st) == 0)   /* present but refused: unreadable, > 64 KB, NUL byte, read error */
            fprintf(stderr, "[ios] config %s: WARNING: file present but rejected (not applied; errno=%d %s)\n",
                    path, err, strerror(err));
        if (required) *rc = -1;
        return;   /* the override file is optional; absent = silent */
    }
    fprintf(stderr, "[ios] config %s: %d set, %d rejected%s\n", path, applied, rejected,
            rejected > 0 ? " -- WARNING: malformed lines ignored" : "");
}

int gow2_ios_host_load_config(void)
{
    char path[1100];
    int rc = 0;
    /* overwrite = 0 everywhere: the launch environment wins over the override
     * file, which wins over the bundled recipe. */
    snprintf(path, sizeof path, "%s/gow2.override.env", s_docs);
    apply_config_file(path, 0, &rc);
    NSString* b = [[NSBundle mainBundle] pathForResource:@"gow2" ofType:@"env"];
    if (b == nil) rc = -1;
    else apply_config_file(b.fileSystemRepresentation, 1, &rc);
    static const struct { const char* key; const char* rel; } k_paths[] = {
        { "GOW2_EBOOT", "EBOOT.ELF" }, { "PS3_VFS_ROOT", "USRDIR" },
        { "PS3_MOVIE_CACHE", "movie_cache" }, { "PS3_SAVEDATA_ROOT", "savedata" },
    };
    for (size_t i = 0; i < sizeof k_paths / sizeof k_paths[0]; i++) {
        snprintf(path, sizeof path, "%s/%s", s_docs, k_paths[i].rel);
        setenv(k_paths[i].key, path, 0);
    }
    mkdir(getenv("PS3_SAVEDATA_ROOT"), 0755);
    return rc;
}

static void* perf_thread(void* arg)
{
    (void)arg;
    pthread_setname_np("ios-perf");
    struct timespec t0, t;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (;;) {
        /* phys_footprint is what jetsam counts (RSS hides compressed pages). */
        task_vm_info_data_t vi;
        mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
        const uint64_t fp = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vi, &n) == KERN_SUCCESS
                                ? vi.phys_footprint : 0;
        clock_gettime(CLOCK_MONOTONIC, &t);
        const double s = (double)(t.tv_sec - t0.tv_sec) + (double)(t.tv_nsec - t0.tv_nsec) / 1e9;
        fprintf(stderr, "[IOSPERF] t=%.1f thermal=%d footprint_mb=%llu available_mb=%zu\n", s,
                (int)[NSProcessInfo processInfo].thermalState, (unsigned long long)(fp >> 20),
                os_proc_available_memory() >> 20);
        sleep(1);
    }
    return NULL;
}

void gow2_ios_host_start_perf_log(void)
{
    const char* e = getenv("PS3_IOS_PERF_LOG");
    if (!(e && e[0] == '1')) return;
    pthread_t t;
    if (pthread_create(&t, NULL, perf_thread, NULL) == 0) pthread_detach(t);
}

static void audio_session_activate(const char* why)
{
    NSError* err = nil;
    if (![[AVAudioSession sharedInstance] setActive:YES error:&err])
        fprintf(stderr, "[ios] audio session activate (%s): %s\n", why, err.localizedDescription.UTF8String);
}

void gow2_ios_host_audio_session_begin(void)
{
    AVAudioSession* s = [AVAudioSession sharedInstance];
    NSError* err = nil;
    /* Playback, not SoloAmbient: SoloAmbient is silenced by the ring/silent switch
     * (measured 2026-09-25: no sound on the iPhone 14); a console game plays regardless. */
    if (![s setCategory:AVAudioSessionCategoryPlayback error:&err])
        fprintf(stderr, "[ios] audio session category: %s\n", err.localizedDescription.UTF8String);
    audio_session_activate("launch");
}

/* Host contract (gow2_ios_lifecycle.h): every gow2_lifecycle_* call happens on
 * the main queue (all observers below use queue:mainQueue, which also
 * marshals AVAudioSession interruptions posted on other threads).
 * After will_resign_active closed the GPU gate, the main thread only logs:
 * a present may be parked at the gate holding the giant lock, so nothing here
 * takes that lock or calls guest/backend code. Apple's background guidance
 * also asks for waitUntilScheduled on the last committed command buffer; the
 * backend does not expose that buffer (commits go through rsx_gpu_commit in
 * rsx_gpu_gate_metal.h, which keeps no "last" reference), so it is not called
 * -- the gate's close already guarantees no commit follows until reopen.
 * willTerminate never joins the guest thread: it may be blocked at the closed
 * gate forever, so the process just exits. */
void gow2_ios_host_install_lifecycle(void)
{
    static const gow2_lifecycle_ops ops = {
        .set_render_suspended = rsx_gpu_gate_set_closed,
        .set_audio_suspended = ps3_audio_host_set_suspended,
        .set_input_active = cpgc_set_app_active,
        .trim_caches = rsx_metal_backend_trim_caches,
    };
    gow2_lifecycle_init(&ops);
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    NSOperationQueue* mq = [NSOperationQueue mainQueue];
    [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:mq
                usingBlock:^(NSNotification* n) {
        (void)n;
        gow2_lifecycle_will_resign_active();
        fprintf(stderr, "[ios] will resign active -> paused (gate in flight=%u waiters=%u)\n",
                rsx_gpu_gate_in_flight(), rsx_gpu_gate_waiters());
    }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:mq
                usingBlock:^(NSNotification* n) {
        (void)n;
        audio_session_activate("did become active");
        gow2_lifecycle_did_become_active();
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        fprintf(stderr, "[ios] did become active -> resumed (gate commits=%lu drops=%lu)\n",
                rsx_gpu_gate_commits(), rsx_gpu_gate_drops());
    }];
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:mq
                usingBlock:^(NSNotification* n) {
        (void)n;
        fprintf(stderr, "[ios] did enter background\n");
    }];
    [nc addObserverForName:UIApplicationWillTerminateNotification object:nil queue:mq
                usingBlock:^(NSNotification* n) {
        (void)n;
        /* Stop GPU submission (gate close is bounded to 2 s) and audio; never
         * join the guest thread -- it may be parked at the closed gate. */
        gow2_lifecycle_will_resign_active();
        fprintf(stderr, "[ios] will terminate -> paused (guest thread not joined)\n");
        flush_log_for_exit();
    }];
    [nc addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:mq
                usingBlock:^(NSNotification* n) {
        (void)n;
        fprintf(stderr, "[ios] memory warning (available_mb=%zu)\n", os_proc_available_memory() >> 20);
        gow2_lifecycle_memory_warning();
    }];
    [nc addObserverForName:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]
                     queue:mq usingBlock:^(NSNotification* n) {
        const NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
        const NSUInteger opts = [n.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        const int began = type == AVAudioSessionInterruptionTypeBegan;
        const int should_resume = !began && (opts & AVAudioSessionInterruptionOptionShouldResume) != 0;
        if (should_resume) audio_session_activate("interruption ended");
        gow2_lifecycle_audio_interruption(began, should_resume);
        fprintf(stderr, "[ios] audio interruption %s%s\n", began ? "began" : "ended",
                began ? "" : (should_resume ? " (should resume)" : " (no resume: held until active)"));
    }];
    [nc addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:mq
                usingBlock:^(NSNotification* n) {
        (void)n;
        fprintf(stderr, "[ios] thermal state -> %d\n", (int)[NSProcessInfo processInfo].thermalState);
    }];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    /* The observers only see transitions: if the app is already inactive
     * (e.g. launched while the screen was locked), start paused. */
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        gow2_lifecycle_will_resign_active();
        fprintf(stderr, "[ios] launched while not active (state=%d) -> paused\n",
                (int)[UIApplication sharedApplication].applicationState);
    }
}

static void* guest_main(void* arg)
{
    (void)arg;
    pthread_setname_np("guest-main");
    const int rc = gow2_boot_run_guest();
    flush_log_for_exit();
    char line[96];
    const int n = snprintf(line, sizeof line, "[ios] guest returned rc=%d -- exiting\n", rc);
    if (n > 0) log_fd_write(line, (size_t)(n < (int)sizeof line ? n : (int)sizeof line - 1));
    _exit(rc == 0 ? 0 : 1);
    return NULL;
}

void gow2_ios_host_wait_for_game_data(void)
{
    while (!gow2_ios_game_data_present(getenv("GOW2_EBOOT"), getenv("PS3_VFS_ROOT"))) {
        fprintf(stderr, "[ios] game data missing or incomplete in %s (EBOOT.ELF, USRDIR) -- "
                        "install it from the Mac: games/gow2/ios/install_ios.sh --data\n", s_docs);
        /* Main thread, blocking (UIAlertController run modally by SDL); checks
         * again after each dismissal, so data copied meanwhile starts the game. */
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "God of War II",
                                 "Jogo não instalado — conecte ao Mac e use Instalar no iPhone.", NULL);
    }
}

int gow2_ios_start_game(void)
{
    pthread_attr_t a;
    pthread_attr_init(&a);
    /* the macOS host links a 32 MB main stack; iOS cannot */
    const int ss = pthread_attr_setstacksize(&a, (size_t)64 << 20);
    if (ss != 0) {
        fprintf(stderr, "[ios] FATAL: guest stack size 64 MB refused (%s)\n", strerror(ss));
        pthread_attr_destroy(&a);
        return ss;
    }
    const char* qn = getenv("PS3_IOS_GUEST_QOS");
    int q = 0;
    if (gow2_ios_qos_from_string(qn, &q)) pthread_attr_set_qos_class_np(&a, (qos_class_t)q, 0);
    pthread_t t;
    const int rc = pthread_create(&t, &a, guest_main, NULL);
    pthread_attr_destroy(&a);
    if (rc == 0) pthread_detach(t);
    fprintf(stderr, "[ios] guest thread %s (qos=%s)\n", rc == 0 ? "started" : "FAILED",
            (qn && *qn) ? qn : "inherit");
    return rc;
}
