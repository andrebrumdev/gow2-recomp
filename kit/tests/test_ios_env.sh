#!/usr/bin/env bash
# ios/ios_env.sh in a kit folder: the NID step gets the kit's ps3kit, the Python tools
# the kit's Python choice; KIT_TOOLS=py and caller values win; a dev tree is unchanged.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
T=$(cd "$(t_tmp)" && pwd); trap 'rm -rf "$T"' EXIT
mk() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\nexit 0\n' > "$1"; chmod +x "$1"; }
# kit folder: gow2-recomp with .kit_tools, next to ps3recomp
mkdir -p "$T/kit/gow2-recomp/ios" "$T/kit/gow2-recomp/kit/lib" "$T/kit/ps3recomp"
cp "$R/ios/ios_env.sh" "$T/kit/gow2-recomp/ios/"; cp "$R/kit/lib/pick_python.sh" "$T/kit/gow2-recomp/kit/lib/"
: > "$T/kit/ps3recomp/CMakeLists.txt"
mk "$T/kit/gow2-recomp/.kit_tools/ps3kit/ps3kit"; mk "$T/kit/gow2-recomp/.kit_tools/python/bin/python3"
# dev tree: no .kit_tools, no kit/lib
mkdir -p "$T/dev/gow2-recomp/ios" "$T/dev/ps3recomp"
cp "$R/ios/ios_env.sh" "$T/dev/gow2-recomp/ios/"; : > "$T/dev/ps3recomp/CMakeLists.txt"
probe() { # probe <tree> [VAR=value...] -> "PS3KIT=<v> PY=<v>"
    local tree=$1; shift
    env -u PS3KIT -u PY -u KIT_TOOLS -u GOW2_WORK -u PS3_ENGINE_ROOT KIT_PY_CANDIDATES=none-such "$@" \
        /bin/bash -c '. "$1/gow2-recomp/ios/ios_env.sh"; printf "PS3KIT=%s PY=%s\n" "${PS3KIT:-}" "${PY:-}"' _ "$tree"
}
K="$T/kit/gow2-recomp"
t_eq "PS3KIT=$K/.kit_tools/ps3kit/ps3kit PY=$K/.kit_tools/python/bin/python3" "$(probe "$T/kit")" "kit folder: kit ps3kit and kit Python"
t_eq "PS3KIT= PY=$K/.kit_tools/python/bin/python3" "$(probe "$T/kit" KIT_TOOLS=py PS3KIT=/inherited/ps3kit)" "KIT_TOOLS=py drops an inherited PS3KIT"
t_eq "PS3KIT=/mine/ps3kit PY=$K/.kit_tools/python/bin/python3" "$(probe "$T/kit" PS3KIT=/mine/ps3kit)" "caller PS3KIT wins"
mk "$T/bin/mypy"
t_eq "PS3KIT=$K/.kit_tools/ps3kit/ps3kit PY=$T/bin/mypy" "$(probe "$T/kit" PY="$T/bin/mypy")" "caller PY wins"
t_eq "PS3KIT= PY=" "$(probe "$T/dev")" "dev tree: nothing set"
t_eq "PS3KIT= PY=/dev/py" "$(probe "$T/dev" PY=/dev/py)" "dev tree: caller PY untouched"
t_done
