/* GoW2 iOS host (thin UIKit glue around SDL2 and the shared boot). */
#ifndef GOW2_IOS_HOST_H
#define GOW2_IOS_HOST_H

#ifdef __cplusplus
extern "C" {
#endif

/* The container's Documents directory (valid after gow2_ios_host_early). */
const char* gow2_ios_documents(void);
/* chdir to Documents; stdout/stderr teed into Documents/gow2.log; logs the
 * GPU's native BC support once. */
void gow2_ios_host_early(void);
/* Launch env > Documents/gow2.override.env > bundled gow2.env, then the
 * container paths (GOW2_EBOOT, PS3_VFS_ROOT, PS3_MOVIE_CACHE, PS3_SAVEDATA_ROOT).
 * Must run before gow2_boot_prepare (SPU registration reads the environment)
 * and before any guest thread. 0 ok; -1 when the bundled recipe is missing. */
int gow2_ios_host_load_config(void);
/* PS3_IOS_PERF_LOG=1 (OFF): one [IOSPERF] line per second. */
void gow2_ios_host_start_perf_log(void);
/* AVAudioSession category + activation. */
void gow2_ios_host_audio_session_begin(void);
/* UIKit / AVAudioSession / thermal notifications -> gow2_lifecycle; idle timer off. */
void gow2_ios_host_install_lifecycle(void);
/* Starts the guest on a 64 MB-stack thread (QoS from PS3_IOS_GUEST_QOS).
 * P2's home screen calls this from "Jogar". 0 ok. */
int gow2_ios_start_game(void);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_IOS_HOST_H */
