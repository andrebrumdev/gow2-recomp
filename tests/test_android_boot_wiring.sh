#!/bin/bash
# boot_macos.cpp on Android (spec §4.3): compiled with the pinned NDK for android-arm64 with
# -DGOW2_BOOT_NO_MAIN, it references no Metal symbol (the Metal fallback is replaced by the SDL
# null backend), names its host "Android" and carries the loud Vulkan-failure line; the macOS
# compile keeps the Metal path. The lift's ppu_recomp.h is replaced by a stub including
# ps3recomp's runtime/ppu/ppu_context.h (the boot host only needs ppu_context).
# Usage: test_android_boot_wiring.sh [ENGINE_ROOT] [PORT_DIR]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="${2:-$(cd "$HERE/.." && pwd)}"
ENG="${1:-$(cd "$PORT/../.." 2>/dev/null && pwd)}"
[ -f "$ENG/tools/android/android_env.sh" ] || ENG="$(cd "$PORT/../ps3recomp" 2>/dev/null && pwd)"
. "$ENG/tools/android/android_env.sh"; android_env_resolve 2>/dev/null
android_env_check_ndk 2>/dev/null || { echo "SKIP: NDK $NDK_VERSION not installed"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; F() { echo "FAIL: $*"; fail=1; }
printf '#pragma once\n#include "ppu_context.h"\n' > "$T/ppu_recomp.h"
INC=(-I "$T" -I "$ENG/include" -I "$ENG/runtime/ppu" -I "$ENG/runtime/memory" -I "$ENG/runtime/spu"
     -I "$ENG/libs/video" -I "$ENG/libs/audio" -I "$ENG/libs/system" -I "$PORT" -I "$PORT/recomp_mid_v2")
"$NDK_BIN/clang++" --target=aarch64-linux-android$MIN_SDK -fPIC -D_GNU_SOURCE -std=c++20 -O1 -w -DGOW2_BOOT_NO_MAIN \
    "${INC[@]}" -c "$PORT/boot_macos.cpp" -o "$T/boot_android.o" 2> "$T/cc.log" || { F "NDK compile: $(head -5 "$T/cc.log")"; exit 1; }
"$NDK_BIN/llvm-nm" -u "$T/boot_android.o" | grep -q 'rsx_metal_backend' && F "Android object references the Metal backend"
"$NDK_BIN/llvm-nm" -u "$T/boot_android.o" | grep -q 'rsx_vulkan_backend_init' || F "Android object does not reference the Vulkan backend"
strings "$T/boot_android.o" | grep -q 'Android/arm64 host' || F "host name is not Android"
strings "$T/boot_android.o" | grep -q '\[BOOT\] vulkan init failed -> sdl (null backend)' || F "no loud Vulkan-failure fallback line"
if [ "$(uname -s)" = Darwin ]; then
    clang++ -std=c++20 -O1 -w "${INC[@]}" -c "$PORT/boot_macos.cpp" -o "$T/boot_mac.o" 2> "$T/cc2.log" || F "macOS compile: $(head -3 "$T/cc2.log")"
    nm -u "$T/boot_mac.o" | grep -q 'rsx_metal_backend_init' || F "macOS object lost the Metal backend"
    strings "$T/boot_mac.o" | grep -q 'vulkan init failed -> metal (platform default)' || F "macOS fallback changed"
fi
[ "$fail" = 0 ] && echo "test_android_boot_wiring: PASS"
exit $fail
