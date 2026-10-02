#!/bin/bash
# build_android.sh [--probe-only] -- builds build-android/gow2.apk (the game) and
# build-android/gow2-probe.apk (the lift-free probe APK of spec §5.1 B0) on the Mac:
# SDL2, FFmpeg, shaderc (once, stamped), the Android runtime, the game objects
# (build_macos.sh GOW2_TARGET=android), the host shell, libmain.so, the baked recipe and the
# APKs (tools/android/build_apk.sh, which signs with the kit keystore and runs the 16 KB and
# licence checks). --probe-only: only the probe APK (no lift, no runtime).
# Environment (android/local.env, untracked, is sourced when present):
#   GOW2_WORK        the gow2-recomp checkout with the game data, recomp_macos_e435/ and spu_lifted/
#                    (default: ../gow2-recomp next to the engine)
#   PS3_ENGINE_ROOT  the ps3recomp checkout (default: the monorepo this file sits in, else ../ps3recomp)
#   GOW2_ANDROID_BUILD  output dir (default: <this port>/build-android)
#   PY               Python >= 3.11 for build_macos.sh's generators (default: $PS3_ENGINE_ROOT/.venv/bin/python,
#                    else ../ps3recomp/.venv/bin/python)
# Last line on success: GOW2_ANDROID_APK=<path>
set -euo pipefail
AH="$(cd "$(dirname "$0")" && pwd)"; PORTD="$(cd "$AH/.." && pwd)"
[ -f "$AH/local.env" ] && . "$AH/local.env"
if [ -f "$PORTD/../../CMakeLists.txt" ] && [ -d "$PORTD/../../runtime" ]; then PS3="${PS3_ENGINE_ROOT:-$(cd "$PORTD/../.." && pwd)}"
else PS3="${PS3_ENGINE_ROOT:-$(cd "$PORTD/../ps3recomp" && pwd)}"; fi
G="${GOW2_WORK:-$(cd "$PS3/../gow2-recomp" 2>/dev/null && pwd || true)}"
B="${GOW2_ANDROID_BUILD:-$PORTD/build-android}"; mkdir -p "$B"; B="$(cd "$B" && pwd)"
PROBE_ONLY=0; [ "${1:-}" = --probe-only ] && PROBE_ONLY=1
. "$PS3/tools/android/android_env.sh"; android_env_resolve; android_env_check_ndk; android_env_check_sdk
PYBIN="${PY:-$PS3/.venv/bin/python}"; [ -x "$PYBIN" ] || PYBIN="$PS3/../ps3recomp/.venv/bin/python"
TRANSPORT="${GOW2_TRANSPORT_FILE:-$PS3/tools/android/device_transport.env}"
for f in boot_macos.cpp gow2_boot.h recomp_mid_v2/gow2_spu_register.c; do   # the monorepo copy must match
    [ -f "$PS3/games/gow2/$f" ] && ! cmp -s "$PORTD/$f" "$PS3/games/gow2/$f" && { echo "$f differs between $PORTD and $PS3/games/gow2: resync (cp+cmp)" >&2; exit 1; }
done
bash "$PS3/tools/icons/make_icons.sh" "$B/icons" | tail -1   # launcher icons (the user's local game icon when present)
"$PS3/tools/android/build_sdl2_android.sh" "$B/sdl-root" | tail -1
"$PS3/tools/android/build_ffmpeg_android.sh" "$B/ffmpeg-android" | tail -1
CC=("$NDK_BIN/clang" --target=aarch64-linux-android$MIN_SDK -fPIC -D_GNU_SOURCE -O2 -std=c11 -Wall -Werror=implicit-function-declaration
    -I "$AH" -I "$PORTD/ios/Sources" -I "$PORTD" -I "$B/sdl-root/sdl/include" -I "$PS3/include" -I "$PS3/runtime/memory"
    -I "$PS3/runtime/spu" -I "$PS3/libs/spurs" -I "$PS3/libs/video" -I "$PS3/libs/input")
HOST_SRC=(gow2_android_main.c gow2_android_config.c gow2_android_probe.c gow2_android_log.c gow2_android_perf.c)
SHARED_SRC=("$PORTD/ios/Sources/gow2_env_file.c" "$PORTD/ios/Sources/gow2_ios_install_manifest.c" "$PORTD/ios/Sources/gow2_sha256.c"
            "$PORTD/ios/Sources/gow2_ios_ui_policy.c")   # ui_policy: the home screen's last-save time
LDF=(-shared -Wl,-z,max-page-size=16384 -Wl,--no-undefined -Wl,--build-id=sha1 -llog -landroid -lm)

# ---- probe APK: host shell + probe routines only (no lift, no runtime) ----
mkdir -p "$B/obj-probe"
PO=(); for s in "${HOST_SRC[@]}"; do "${CC[@]}" -DGOW2_ANDROID_PROBE_ONLY -c "$AH/$s" -o "$B/obj-probe/${s%.c}.o"; PO+=("$B/obj-probe/${s%.c}.o"); done
for s in "${SHARED_SRC[@]}"; do n="$(basename "$s" .c)"; "${CC[@]}" -c "$s" -o "$B/obj-probe/$n.o"; PO+=("$B/obj-probe/$n.o"); done
"$NDK_BIN/clang" --target=aarch64-linux-android$MIN_SDK "${PO[@]}" "$B/sdl-root/sdl/lib/libSDL2.so" "${LDF[@]}" -o "$B/libmain-probe.so"
bash "$PORTD/android/bake_android_env.sh" "${G:-$PORTD}/env_gow2.sh" > "$B/gow2-probe.env"
bash "$PS3/tools/android/build_apk.sh" --probe --app "$AH" --port "$PORTD" --libmain "$B/libmain-probe.so" --sdl "$B/sdl-root" \
    --ffmpeg "$B/ffmpeg-android" --env "$B/gow2-probe.env" --icons "$B/icons" --out "$B/gow2-probe.apk" | tail -2
[ "$PROBE_ONLY" = 1 ] && { echo "GOW2_ANDROID_APK=$B/gow2-probe.apk"; exit 0; }

# ---- game APK ----
[ -n "$G" ] && [ -d "$G/recomp_macos_e435" ] && [ -d "$G/spu_lifted" ] || { echo "set GOW2_WORK (the gow2-recomp checkout with recomp_macos_e435/ and spu_lifted/)" >&2; exit 1; }
[ -f "$G/recomp_macos_e435/.spu_build_flags" ] || { echo "run '$G/build_macos.sh recomp_macos_e435' once on the Mac first (it patches and verifies the SPU lifts)" >&2; exit 1; }
[ -f "$TRANSPORT" ] || { echo "no $TRANSPORT: run tools/android/probe_transport.sh on the phone first (the game APK bakes the proven data/save roots)" >&2; exit 1; }
"$PS3/tools/android/build_shaderc_android.sh" "$B/shaderc" | tail -1
"$PS3/tools/android/build_runtime_android.sh" "$B/rt" "$B/sdl-root/sdl" "$B/ffmpeg-android" "$B/shaderc" | tail -1
( cd "$PORTD" && SPU_OBSERVED_PATCHES=0 PY="$PYBIN" PS3_ENGINE_ROOT="$PS3" GOW2_TARGET=android OBJ="$B/obj-game" \
    OUT="$B/libgow2_game.a" SPU_LIFTED_DIR="$G/spu_lifted" ./build_macos.sh "$G/recomp_macos_e435" ) > "$B/game_build.log" 2>&1 \
    || { tail -30 "$B/game_build.log" >&2; exit 1; }
nspu="$(sed -n 's/.*archived (GOW2_TARGET=android, \([0-9]*\) SPU objects).*/\1/p' "$B/game_build.log")"
[ "${nspu:-0}" -ge 2 ] || { echo "the game archive has ${nspu:-0} SPU objects: spu_lifted missing (the intro would not pass)" >&2; exit 1; }
mkdir -p "$B/obj-host"
# game-only host sources (they reference the runtime, so never in the probe APK's --no-undefined link):
# the guest thread, SIGTEST, and the home screen (overlay + Vulkan backend)
HO=(); for s in "${HOST_SRC[@]}" gow2_android_host.c gow2_android_sigtest.c gow2_android_home.c gow2_android_home_status.c; do "${CC[@]}" -c "$AH/$s" -o "$B/obj-host/${s%.c}.o"; HO+=("$B/obj-host/${s%.c}.o"); done
for s in "${SHARED_SRC[@]}"; do n="$(basename "$s" .c)"; "${CC[@]}" -c "$s" -o "$B/obj-host/$n.o"; HO+=("$B/obj-host/$n.o"); done
"$NDK_BIN/clang++" --target=aarch64-linux-android$MIN_SDK "${HO[@]}" \
    -Wl,--whole-archive "$B/libgow2_game.a" "$B/rt/libps3recomp_runtime.a" -Wl,--no-whole-archive \
    "$B/shaderc/lib/libshaderc_combined.a" "$B/sdl-root/sdl/lib/libSDL2.so" \
    "$B/ffmpeg-android/lib/libavcodec.so" "$B/ffmpeg-android/lib/libavutil.so" -lvulkan "${LDF[@]}" -o "$B/libmain.so" \
    > "$B/link.log" 2>&1 || { grep -E "error|undefined" "$B/link.log" | head -30 >&2; exit 1; }
bash "$PORTD/android/bake_android_env.sh" "$G/env_gow2.sh" "$TRANSPORT" > "$B/gow2.env"
bash "$PS3/tools/android/build_apk.sh" --app "$AH" --port "$PORTD" --libmain "$B/libmain.so" --sdl "$B/sdl-root" \
    --ffmpeg "$B/ffmpeg-android" --env "$B/gow2.env" --vm-bands "$PS3/tools/android/vm_bands.txt" --icons "$B/icons" --out "$B/gow2.apk" | tail -3
echo "GOW2_ANDROID_APK=$B/gow2.apk"
