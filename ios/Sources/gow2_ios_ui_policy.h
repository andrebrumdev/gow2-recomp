/* GoW2 iOS host policies for the P2 mobile UI, pure C so the Mac tests them:
 * the thermal fps cap, the re-sign expiry from the embedded provisioning
 * profile, the last save time for the home screen and the memory ceiling for
 * the Desenvolvedor panel. */
#ifndef GOW2_IOS_UI_POLICY_H
#define GOW2_IOS_UI_POLICY_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* fps cap for NSProcessInfoThermalState (0 nominal, 1 fair, 2 serious, 3
 * critical): serious -> 20, critical -> 15 (both under the P1 gameplay p50 of
 * 22 fps, so they bind); 0 = no cap. `override` is PS3_IOS_THERMAL_CAP: "0"
 * disables the cap, "S:C" (e.g. "24:18", 1..60) sets both; NULL, "" or
 * anything else keeps the defaults. */
unsigned gow2_ios_thermal_fps_cap(int thermal_state, const char* override);

/* ExpirationDate of an embedded.mobileprovision (a CMS blob with a plist
 * inside): <key>ExpirationDate</key> then <date>YYYY-MM-DDTHH:MM:SSZ</date>.
 * Unix time, or 0 when absent or malformed. */
long long gow2_ios_provision_expiry(const char* bytes, size_t n);

/* Newest modification time of a regular file one level down
 * (savedata_root/<save dir>/<file>); 0 when there is none. */
long long gow2_ios_latest_save_mtime(const char* savedata_root);

/* phys_footprint + os_proc_available_memory, in MB: the jetsam ceiling the
 * process runs under (4096 with the increased-memory-limit entitlement). */
unsigned gow2_ios_memory_ceiling_mb(unsigned long long footprint_bytes, unsigned long long available_bytes);

#ifdef __cplusplus
}
#endif
#endif /* GOW2_IOS_UI_POLICY_H */
