# Sourced by the games/gow2/ios scripts: engine and game roots, build dir,
# device, team and bundle id. Values come from local.env (untracked).
IOS_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$IOS_HERE/local.env" ] && . "$IOS_HERE/local.env"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [ -f "$IOS_HERE/../../../CMakeLists.txt" ] && [ -d "$IOS_HERE/../../../runtime" ]; then
    PS3="${PS3_ENGINE_ROOT:-$(cd "$IOS_HERE/../../.." && pwd)}"          # monorepo games/gow2/ios
    G="${GOW2_WORK:-}"
else
    G="${GOW2_WORK:-$(cd "$IOS_HERE/.." && pwd)}"                         # gow2-recomp/ios
    PS3="${PS3_ENGINE_ROOT:-$(cd "$G/../ps3recomp" 2>/dev/null && pwd)}"
fi
[ -n "$G" ] && [ -d "$G" ] || { echo "set GOW2_WORK (the gow2-recomp checkout) in $IOS_HERE/local.env" >&2; exit 1; }
[ -n "$PS3" ] && [ -f "$PS3/CMakeLists.txt" ] || { echo "engine root not found; set PS3_ENGINE_ROOT" >&2; exit 1; }
LIFT="${GOW2_IOS_LIFT:-$G/recomp_macos_e435}"
B="${GOW2_IOS_BUILD:-$G/build-ios}"
TEAM="${GOW2_IOS_TEAM:-}"
DEV="${GOW2_IOS_DEVICE:-}"
BUNDLE="${GOW2_IOS_BUNDLE_ID:-com.$(printf '%s' "$TEAM" | tr 'A-Z' 'a-z').gow2recomp}"
APP="$B/dd/Build/Products/Release-iphoneos/GoW2.app"
