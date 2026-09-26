#!/bin/bash
# P3 Task 6: the scripts the Mac launcher drives. print_config.sh prints what
# ios_env.sh resolved; build_ios.sh --sign-only refuses without a full build
# and, with one, runs only the bake + xcodegen + xcodebuild steps (never the
# game, runtime or SDL builds); install_ios.sh --data marks the phone's manifest
# incomplete before copying the game and says what the launcher re-copies.
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
printf '#!/bin/bash\ntouch "%s/FFMPEG_BUILT"; exit 1\n' "$T" > "$E/tools/ios/build_ffmpeg.sh"
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
for m in GAME_BUILT RT_BUILT SDL_BUILT FFMPEG_BUILT; do [ -e "$T/$m" ] && F "--sign-only ran the $m step (refusal case)"; done

mkdir -p "$B/rt" "$B/sdl-root/sdl/lib"
touch "$B/libgow2_game.a" "$B/rt/libps3recomp_runtime.a" "$B/sdl-root/sdl/lib/libSDL2.a" "$B/sdl-root/sdl/lib/libSDL2main.a"
OUT="$(PATH="$T/bin:$PATH" "$P/ios/build_ios.sh" --sign-only 2>&1)"; rc=$?
[ "$rc" = 1 ] && grep -q "ffmpeg-ios" <<< "$OUT" || F "--sign-only after a build without FFmpeg must refuse and name ffmpeg-ios (rc=$rc): $OUT"
mkdir -p "$B/ffmpeg-ios/lib" "$B/ffmpeg-ios/share/licenses"
touch "$B/ffmpeg-ios/lib/libavcodec.a" "$B/ffmpeg-ios/lib/libavutil.a" "$B/ffmpeg-ios/share/licenses/FFmpeg-COPYING.LGPLv2.1.txt"
OUT="$(PATH="$T/bin:$PATH" "$P/ios/build_ios.sh" --sign-only 2>&1)"; rc=$?
[ "$rc" = 0 ] || F "--sign-only with a full build must exit 0 (got $rc): $OUT"
[ "$(tail -1 <<< "$OUT")" = "GOW2_IOS_APP=$APP" ] || F "last line must be GOW2_IOS_APP=$APP: $OUT"
for m in GAME_BUILT RT_BUILT SDL_BUILT FFMPEG_BUILT; do [ -e "$T/$m" ] && F "--sign-only ran the $m step"; done
[ -f "$P/ios/Generated/licenses/FFmpeg-COPYING.LGPLv2.1.txt" ] || F "--sign-only must put FFmpeg's license into Generated/licenses"
grep -q "ffmpeg-ios/lib/libavcodec.a" "$P/ios/Generated/Gow2.xcconfig" || F "the app must link libavcodec.a"
grep -q -- "-allowProvisioningUpdates" "$T/XCODEBUILD_ARGS" 2>/dev/null || F "xcodebuild must sign with -allowProvisioningUpdates"
grep -q "gow2-install.manifest" "$P/ios/install_ios.sh" || F "install_ios.sh --data must point to the launcher's manifest"

# install_ios.sh --data against a fake xcrun (no device): the incomplete marker lands on
# the phone's manifest BEFORE any game file, and the note tells what the launcher re-copies.
mkdir -p "$APP"
cat > "$T/bin/xcrun" <<EOF
#!/bin/bash
echo "\$*" >> "$T/XCRUN_LOG"
src=""; dst=""
while [ \$# -gt 0 ]; do
    case "\$1" in --source) src="\$2"; shift ;; --destination) dst="\$2"; shift ;; esac
    shift
done
[ "\$dst" = "Documents/gow2-install.manifest" ] && /bin/cat "\$src" > "$T/MANIFEST_PUSHED"
exit 0
EOF
chmod +x "$T/bin/xcrun"
OUT="$(PATH="$T/bin:$PATH" "$P/ios/install_ios.sh" --data 2>"$T/DATA_ERR")"; rc=$?
[ "$rc" = 0 ] || F "install_ios.sh --data with a fake xcrun must exit 0 (got $rc): $(cat "$T/DATA_ERR")"
[ "$(tail -1 <<< "$OUT")" = "GOW2_IOS_INSTALL_OK" ] || F "install_ios.sh --data must end with GOW2_IOS_INSTALL_OK: $OUT"
DESTS="$(grep -o -- '--destination [^ ]*' "$T/XCRUN_LOG" 2>/dev/null | cut -d' ' -f2 | tr '\n' ' ')"
[ "$DESTS" = "Documents/gow2-install.manifest Documents/EBOOT.ELF Documents/USRDIR Documents/movie_cache " ] \
    || F "--data must overwrite the manifest first, then copy the game: $DESTS"
head -1 "$T/XCRUN_LOG" | grep -q "device install app" || F "the app is installed before any copy: $(head -1 "$T/XCRUN_LOG")"
[ "$(cat "$T/MANIFEST_PUSHED" 2>/dev/null)" = "$(printf 'gow2-install 1\nincomplete')" ] \
    || F "the manifest pushed by --data must be the incomplete marker: $(cat "$T/MANIFEST_PUSHED" 2>/dev/null)"
grep -q "64 MiB" "$T/DATA_ERR" && grep -q "copied again" "$T/DATA_ERR" \
    || F "--data note must say the launcher re-copies files over 64 MiB without a record: $(cat "$T/DATA_ERR")"
rm -f "$T/XCRUN_LOG"
OUT="$(PATH="$T/bin:$PATH" "$P/ios/install_ios.sh" 2>&1)" || F "install_ios.sh without --data failed: $OUT"
[ "$(grep -c -- '--destination' "$T/XCRUN_LOG")" = 0 ] || F "without --data nothing is copied: $(cat "$T/XCRUN_LOG")"

[ "$fail" = 0 ] && echo "test_ios_scripts_p3: PASS"
exit "$fail"
