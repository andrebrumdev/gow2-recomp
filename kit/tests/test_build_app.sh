#!/usr/bin/env bash
# launcher/macos/build_app.sh builds a launcher that points at this repo (setup.sh step 7).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
APP="$T/GoW2 Recomp.app" bash "$R/launcher/macos/build_app.sh" > "$T/build.log" 2>&1; t_eq 0 $? "build_app.sh succeeds"
t_true "the launcher executable exists" test -x "$T/GoW2 Recomp.app/Contents/MacOS/GoW2Recomp"
t_eq "$R" "$(plutil -extract GoW2RepoPath raw "$T/GoW2 Recomp.app/Contents/Info.plist" 2>/dev/null)" "the app points at this repo"
t_done
