#!/bin/bash
# bake_env.sh turns the real env_gow2.sh into the play recipe the iOS bundle ships.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# The caller's environment must never leak into the baked recipe: PS3_TRACE_FPS,
# PS3_PAD_AUTOSTART, PS3_FULLSCREEN and PS3_METAL_VSYNC are all things jogar_g2.sh
# unsets, and PS3_MUTE=1 here must still bake as PS3_MUTE=0 (env -i wipes the
# caller, then the jogar_g2.sh overrides apply unconditionally).
OUT="$(PS3_TRACE_FPS=1 PS3_PAD_AUTOSTART=1 PS3_FULLSCREEN=1 PS3_METAL_VSYNC=1 PS3_MUTE=1 "$HERE/../ios/bake_env.sh" "$HERE/../env_gow2.sh")" || { echo "FAIL: bake_env.sh exited $?"; exit 1; }
fail=0
must() { grep -qx "$1" <<< "$OUT" || { echo "FAIL: missing $1"; fail=1; }; }
mustnot() { grep -qE "$1" <<< "$OUT" && { echo "FAIL: must not contain $1"; fail=1; }; }
must 'PS3_RSX_BACKEND=metal'
must 'PS3_SPU1=1'
must 'PS3_SPU6=1'
must 'PS3_VDEC_ASYNC=1'
must 'PS3_MOVIE_DONE_MS=auto'
must 'PS3_MUTE=0'
mustnot '^PS3_PAD_AUTOSTART='
mustnot '^PS3_VFS_ROOT='
mustnot '^PS3_MOVIE_CACHE='
mustnot '^PS3_TRACE_'
mustnot '^PS3_FULLSCREEN='
mustnot '^PS3_METAL_VSYNC='
# unset == baked value in libs/video/rsx_depth_debug.c and rsx_metal_backend.m
# for all three (verified 2026-09-24 fix round 1) -- baking them is pure noise.
mustnot '^PS3_METAL_DEBUG_'
bad="$(grep -vE '^PS3_[A-Z0-9_]+=[^[:cntrl:]]*$' <<< "$OUT")"
[ -z "$bad" ] || { echo "FAIL: malformed lines: $bad"; fail=1; }
[ "$OUT" = "$(LC_ALL=C sort <<< "$OUT")" ] || { echo "FAIL: output not sorted"; fail=1; }
[ "$fail" = 0 ] && echo "PASS"
exit "$fail"
