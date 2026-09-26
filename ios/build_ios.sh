#!/bin/bash
# build_ios.sh [--no-sign | --sign-only] -- builds GoW2.app for the iPhone: SDL2 (once), the
# game objects (build_macos.sh GOW2_TARGET=ios), the iOS runtime, the baked
# recipe and the Xcode project (xcodegen). --no-sign: compile and link only.
# --sign-only: re-sign (Mac launcher "Reassinar"): reuse the built game, runtime
# and SDL; only the recipe bake, xcodegen and xcodebuild run.
# Exit 0 and a final "GOW2_IOS_APP=<path>" line on success.
# FORCE_REBUILD_LIFT=1 (passed through to build_macos.sh) recompiles every lift
# chunk: the chunk objects carry no flags stamp, so a tree built with other
# flags (e.g. before -mcpu=apple-a15 reached them) is otherwise reused.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/ios_env.sh"
SIGN=1
SIGN_ONLY=0
case "${1:-}" in
    --no-sign) SIGN=0 ;;
    --sign-only) SIGN_ONLY=1 ;;
esac
[ "$SIGN" = 0 ] || [ -n "$TEAM" ] || { echo "set GOW2_IOS_TEAM in local.env" >&2; exit 1; }
[ -f "$LIFT/.spu_build_flags" ] || { echo "run '$G/build_macos.sh $(basename "$LIFT")' once first (it patches and verifies the SPU lifts)" >&2; exit 1; }
for f in boot_macos.cpp gow2_boot.h recomp_mid_v2/gow2_spu_register.c; do
    cmp -s "$IOS_HERE/../$f" "$G/$f" || { echo "$f differs between $IOS_HERE/.. and $G: resync games/gow2 from gow2-recomp (g2sync)" >&2; exit 1; }
done
mkdir -p "$B/xcode" "$IOS_HERE/Generated"   # xcodegen cannot move the project into a missing dir
if [ "$SIGN_ONLY" = 1 ]; then
    for f in "$B/libgow2_game.a" "$B/rt/libps3recomp_runtime.a" "$B/sdl-root/sdl/lib/libSDL2.a" "$B/sdl-root/sdl/lib/libSDL2main.a"; do
        [ -f "$f" ] || { echo "--sign-only needs a full build first (missing $f): run build_ios.sh" >&2; exit 1; }
    done
else
    [ -f "$B/sdl-root/sdl/lib/libSDL2.a" ] || "$PS3/tools/ios/build_sdl2_ios.sh" "$B/sdl-root"
    ( cd "$G" && GOW2_TARGET=ios OBJ="$B/obj" OUT="$B/libgow2_game.a" PS3_ENGINE_ROOT="$PS3" ./build_macos.sh "$LIFT" ) \
        > "$B/game_build.log" 2>&1 || { tail -30 "$B/game_build.log" >&2; exit 1; }
    "$PS3/tools/ios/build_runtime_ios.sh" "$B/rt" "$B/sdl-root/sdl"
fi
"$IOS_HERE/bake_env.sh" "$G/env_gow2.sh" > "$IOS_HERE/Generated/gow2.env"
FW="Metal MetalFX MetalPerformanceShaders QuartzCore CoreGraphics Foundation UIKit AVFoundation CoreMedia CoreVideo VideoToolbox AudioToolbox CoreAudio GameController CoreHaptics CoreText CoreMotion OpenGLES ImageIO MobileCoreServices CoreBluetooth"
{
    echo "GOW2_IOS_TEAM = $TEAM"
    echo "GOW2_IOS_BUNDLE_ID = $BUNDLE"
    echo "GOW2_IOS_HERE = $IOS_HERE"
    printf 'GOW2_IOS_HEADER_PATHS ='
    for d in "$PS3/include" "$PS3/libs/video" "$PS3/libs/audio" "$PS3/libs/input" "$PS3/runtime/spu" \
             "$IOS_HERE/.." "$IOS_HERE/Sources" "$B/sdl-root/sdl/include"; do printf ' "%s"' "$d"; done
    printf '\n'
    printf 'GOW2_IOS_LDFLAGS = -force_load %s %s %s %s' "$B/libgow2_game.a" "$B/rt/libps3recomp_runtime.a" \
        "$B/sdl-root/sdl/lib/libSDL2main.a" "$B/sdl-root/sdl/lib/libSDL2.a"
    for f in $FW; do printf ' -framework %s' "$f"; done
    printf ' -lc++ -lm\n'
} > "$IOS_HERE/Generated/Gow2.xcconfig"
xcodegen generate --spec "$IOS_HERE/project.yml" --project "$B/xcode" --quiet
EXTRA=(-allowProvisioningUpdates)
[ "$SIGN" = 0 ] && EXTRA=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
xcodebuild -project "$B/xcode/GoW2.xcodeproj" -scheme GoW2 -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$B/dd" \
    "${EXTRA[@]}" build > "$B/xcodebuild.log" 2>&1 || {
    grep -E "error:|Undefined symbols|ld: " "$B/xcodebuild.log" | head -30 >&2
    exit 1
}
echo "GOW2_IOS_APP=$APP"
