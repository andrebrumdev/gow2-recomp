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
# Kit folder (plan 2026-09-28, Phase 6): the NID step uses the kit's ps3kit and the
# remaining Python tools the Python kit/setup.sh would pick (PY -> kit-built -> system).
# KIT_TOOLS=py keeps the Python NID tool, like setup.sh. A dev tree has no .kit_tools.
if [ "${KIT_TOOLS:-cpp}" = py ]; then
    unset PS3KIT
elif [ -z "${PS3KIT:-}" ] && [ -x "$G/.kit_tools/ps3kit/ps3kit" ]; then
    export PS3KIT="$G/.kit_tools/ps3kit/ps3kit"
fi
# Only a kit folder (it has .kit_tools): every checkout ships pick_python.sh, and a dev
# tree must keep build_macos.sh's own choice (the engine .venv).
if [ -d "$G/.kit_tools" ] && [ -f "$G/kit/lib/pick_python.sh" ]; then
    . "$G/kit/lib/pick_python.sh"
    if _kit_py="$(kit_pick_python "$G" 2>/dev/null)"; then export PY="$_kit_py"; fi
    unset _kit_py
fi
