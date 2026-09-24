/* GoW2 iOS host policies, pure C so the Mac tests them: the app lifecycle
 * state machine (spec 2026-09-24 iOS, resolution 9), the guest thread's QoS
 * name, and whether the game data is installed.
 *
 * Rules: render suspended <=> inactive; audio suspended <=> inactive OR
 * interrupted; input active <=> active. An op is called only when its value
 * changes, in the order render, audio, input -- so on resign the GPU gate is
 * closed before audio and input are suspended, and on resume it reopens first.
 *
 * Host contract (the iOS app, Task 13, must honour all of it):
 *   - Main thread only. Every gow2_lifecycle_* call comes from the main queue;
 *     the state has no lock. UIKit lifecycle notifications already arrive on
 *     the main queue, but AVAudioSessionInterruptionNotification may be posted
 *     on another thread: the host marshals it (dispatch_async to the main
 *     queue) before calling gow2_lifecycle_audio_interruption. This also makes
 *     ps3_audio_host_set_suspended run from one serial context, which it
 *     requires. Debug builds on Apple assert pthread_main_np().
 *   - set_render_suspended(1) = rsx_gpu_gate_set_closed(1) = close(2000): it
 *     BLOCKS the main thread for up to 2 s while in-flight GPU sections drain.
 *     A present may be parked at the gate holding the giant lock, so after the
 *     close nothing on the main thread may take the giant lock or call guest
 *     or backend code (audio/input suspension below must not either; today's
 *     ps3_audio_host_set_suspended and cpgc_set_app_active do not).
 *   - After the close, the host calls waitUntilScheduled on the last committed
 *     command buffer (Apple background guidance) -- a backend/host concern,
 *     not this module's.
 *   - willTerminate must not join the guest thread: it may be blocked at the
 *     closed gate forever. Exit without joining.
 *
 * Ops the host wires (all exist, signatures match):
 *   set_render_suspended  rsx_gpu_gate_set_closed      (libs/video/rsx_gpu_gate.h)
 *   set_audio_suspended   ps3_audio_host_set_suspended (libs/audio/cellAudio.h)
 *   set_input_active      cpgc_set_app_active          (libs/input/cellpad_gamecontroller.h)
 *   trim_caches           rsx_metal_backend_trim_caches (libs/video/rsx_metal_backend.h)
 */
#ifndef GOW2_IOS_LIFECYCLE_H
#define GOW2_IOS_LIFECYCLE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct gow2_lifecycle_ops {
    void (*set_render_suspended)(int on);   /* rsx_gpu_gate_set_closed (blocks <= 2 s on close) */
    void (*set_audio_suspended)(int on);    /* ps3_audio_host_set_suspended */
    void (*set_input_active)(int on);       /* cpgc_set_app_active */
    void (*trim_caches)(void);              /* rsx_metal_backend_trim_caches */
} gow2_lifecycle_ops;

typedef struct gow2_lifecycle_state {
    int active, interrupted, render_suspended, audio_suspended, input_active;
} gow2_lifecycle_state;

/* Active, nothing suspended; calls nothing. NULL ops = observe only. */
void gow2_lifecycle_init(const gow2_lifecycle_ops* ops);
void gow2_lifecycle_will_resign_active(void);
void gow2_lifecycle_did_become_active(void);
/* Main thread only: marshal AVAudioSession interruptions to the main queue. */
void gow2_lifecycle_audio_interruption(int began);
void gow2_lifecycle_memory_warning(void);
gow2_lifecycle_state gow2_lifecycle_get(void);

/* "interactive" | "initiated" | "default" | "utility" -> 1 and *qos_out (a
 * qos_class_t); NULL, "", "inherit" or an unknown name -> 0 (inherit). */
int gow2_ios_qos_from_string(const char* s, int* qos_out);

/* 1 when eboot is a non-empty regular file and usrdir holds at least one
 * non-empty regular file. A torn copy of one big file is not detected here
 * (P3's install manifest covers that). */
int gow2_ios_game_data_present(const char* eboot, const char* usrdir);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_IOS_LIFECYCLE_H */
