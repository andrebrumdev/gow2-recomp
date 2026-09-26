#!/bin/bash
# P3 Task 6: the scripts the Mac launcher drives. print_config.sh prints what
# ios_env.sh resolved; build_ios.sh --sign-only refuses without a full build
# and, with one, runs only the bake + xcodegen + xcodebuild steps (never the
# game, runtime or SDL builds); install_ios.sh --data points to the manifest.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
F() { echo "FAIL: $*"; fail=1; }
P="$T/a/port"; W="$T/work"; E="$T/ps3"; B="$T/build"
mkdir -p "$P/ios" "$P/recomp_mid_v2" "$W/recomp_mid_v2" "$W/recomp_macos_e435" "$E/runtime" "$E/tools/ios" "$T/bin"
for s in ios_env.sh print_config.sh build_ios.sh bake_env.sh install_ios.sh; do cp "$PORT/ios/$s" "$P/ios/"; done
for f in boot_macos.cpp gow2_boot.h recomp_mid_v2/gow2_spu_register.c; do echo "same $f" > "$P/$f"; cp "$P/$f" "$W/$f"; done
touch "$W/recomp_macos_e435/.spu_build_flags" "$E/CMakeLists.txt"
echo 'export PS3_RSX_BACKEND=metal' > "$W/env_gow2.sh"
printf '#!/bin/bash\ntouch "%s/GAME_BUILT"; exit 1\n' "$T" > "$W/build_macos.sh"
printf '#!/bin/bash\ntouch "%s/RT_BUILT"; exit 1\n' "$T" > "$E/tools/ios/build_runtime_ios.sh"
printf '#!/bin/bash\ntouch "%s/SDL_BUILT"; exit 1\n' "$T" > "$E/tools/ios/build_sdl2_ios.sh"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/xcodegen"
printf '#!/bin/bash\necho "$@" > "%s/XCODEBUILD_ARGS"; exit 0\n' "$T" > "$T/bin/xcodebuild"
chmod +x "$W/build_macos.sh" "$E"/tools/ios/*.sh "$T"/bin/*
cat > "$P/ios/local.env" <<EOF
GOW2_IOS_TEAM=ABCDE12345                # personal team
GOW2_IOS_DEVICE=dev-1
GOW2_WORK=$W
PS3_ENGINE_ROOT=$E
GOW2_IOS_BUILD=$B
EOF
APP="$B/dd/Build/Products/Release-iphoneos/GoW2.app"

OUT="$("$P/ios/print_config.sh")" || F "print_config.sh exited $?"
for l in "GOW2_IOS_TEAM=ABCDE12345" "GOW2_IOS_DEVICE=dev-1" "GOW2_IOS_BUNDLE=com.abcde12345.gow2recomp" "GOW2_IOS_APP=$APP"; do
    grep -qx "$l" <<< "$OUT" || F "print_config.sh must print $l, got: $OUT"
done

ERR="$(PATH="$T/bin:$PATH" "$P/ios/build_ios.sh" --sign-only 2>&1)"; rc=$?
[ "$rc" = 1 ] || F "--sign-only without a full build must exit 1 (got $rc)"
grep -q -- "--sign-only" <<< "$ERR" || F "the --sign-only refusal must say why: $ERR"
for m in GAME_BUILT RT_BUILT SDL_BUILT; do [ -e "$T/$m" ] && F "--sign-only ran the $m step (refusal case)"; done

mkdir -p "$B/rt" "$B/sdl-root/sdl/lib"
touch "$B/libgow2_game.a" "$B/rt/libps3recomp_runtime.a" "$B/sdl-root/sdl/lib/libSDL2.a" "$B/sdl-root/sdl/lib/libSDL2main.a"
OUT="$(PATH="$T/bin:$PATH" "$P/ios/build_ios.sh" --sign-only 2>&1)"; rc=$?
[ "$rc" = 0 ] || F "--sign-only with a full build must exit 0 (got $rc): $OUT"
[ "$(tail -1 <<< "$OUT")" = "GOW2_IOS_APP=$APP" ] || F "last line must be GOW2_IOS_APP=$APP: $OUT"
for m in GAME_BUILT RT_BUILT SDL_BUILT; do [ -e "$T/$m" ] && F "--sign-only ran the $m step"; done
grep -q -- "-allowProvisioningUpdates" "$T/XCODEBUILD_ARGS" 2>/dev/null || F "xcodebuild must sign with -allowProvisioningUpdates"
grep -q "gow2-install.manifest" "$P/ios/install_ios.sh" || F "install_ios.sh --data must point to the launcher's manifest"

[ "$fail" = 0 ] && echo "test_ios_scripts_p3: PASS"
exit "$fail"
