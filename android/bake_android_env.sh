#!/bin/bash
# bake_android_env.sh ENV_RECIPE [TRANSPORT_ENV] > gow2.env
# The Android app's bundled recipe: the iOS bake (ios/bake_env.sh: env_gow2.sh + the
# jogar_g2.sh play overrides, sorted KEY=VALUE, container paths not baked) with the Android
# overlay: PS3_RSX_BACKEND=vulkan (replacing the Mac's metal), and -- from the device's
# proven transports (tools/android/device_transport.env) -- GOW2_ANDROID_DATA_ROOT and
# GOW2_ANDROID_SAVE_ROOT. (cellVdec's software MPEG-2 is a compile-time choice on Android,
# PS3_VDEC_SW in the runtime's CMake, not an env var.) Probes stay unbaked (OFF).
set -euo pipefail
RECIPE="${1:?usage: bake_android_env.sh path/to/env_gow2.sh [device_transport.env]}"
TRANSPORT="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
{
    bash "$HERE/../ios/bake_env.sh" "$RECIPE" | grep -v '^PS3_RSX_BACKEND='
    echo "PS3_RSX_BACKEND=vulkan"
    if [ -n "$TRANSPORT" ]; then
        dr="$(sed -n 's/^DATA_ROOT=//p' "$TRANSPORT")"; sr="$(sed -n 's/^SAVE_ROOT=//p' "$TRANSPORT")"
        case "$dr" in external|internal) ;; *) echo "bake_android_env: no proven data transport in $TRANSPORT" >&2; exit 1 ;; esac
        case "$sr" in external|internal) ;; *) echo "bake_android_env: no proven save transport in $TRANSPORT" >&2; exit 1 ;; esac
        echo "GOW2_ANDROID_DATA_ROOT=$dr"
        echo "GOW2_ANDROID_SAVE_ROOT=$sr"
    fi
} | LC_ALL=C sort
