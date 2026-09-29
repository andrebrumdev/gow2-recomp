#!/bin/bash
# android/bake_android_env.sh: exactly one PS3_RSX_BACKEND (vulkan), the iOS play overrides
# kept, the transport roots baked when given and refused when unproven, no probe gate baked.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; B="$HERE/../android/bake_android_env.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; F() { echo "FAIL: $*"; fail=1; }
cat > "$T/env.sh" <<'X'
: "${PS3_RSX_BACKEND:=metal}"; export PS3_RSX_BACKEND
: "${PS3_MOVIE_EOS:=1}"; export PS3_MOVIE_EOS
: "${PS3_MUTE:=1}"; export PS3_MUTE
X
out="$(bash "$B" "$T/env.sh")" || F "bake failed"
[ "$(printf '%s\n' "$out" | grep -c '^PS3_RSX_BACKEND=')" = 1 ] || F "PS3_RSX_BACKEND not unique: $out"
printf '%s\n' "$out" | grep -qx 'PS3_RSX_BACKEND=vulkan' || F "not vulkan"
printf '%s\n' "$out" | grep -qx 'PS3_MUTE=0' || F "play override PS3_MUTE=0 lost"
printf '%s\n' "$out" | grep -q '^PS3_ANDROID_\|^PS3_VM_COMMIT_LOG\|^PS3_VFS_LOG_ENOENT' && F "a probe gate was baked"
printf 'DATA_ROOT=external\nSAVE_ROOT=internal\n' > "$T/tr.env"
out="$(bash "$B" "$T/env.sh" "$T/tr.env")" || F "bake with transport failed"
printf '%s\n' "$out" | grep -qx 'GOW2_ANDROID_DATA_ROOT=external' && printf '%s\n' "$out" | grep -qx 'GOW2_ANDROID_SAVE_ROOT=internal' || F "roots: $out"
[ "$(printf '%s\n' "$out" | LC_ALL=C sort)" = "$out" ] || F "not sorted"
printf 'DATA_ROOT=none\nSAVE_ROOT=external\n' > "$T/bad.env"
bash "$B" "$T/env.sh" "$T/bad.env" >/dev/null 2>&1 && F "unproven data transport accepted"
[ "$fail" = 0 ] && echo "test_android_bake_env: PASS"
exit $fail
