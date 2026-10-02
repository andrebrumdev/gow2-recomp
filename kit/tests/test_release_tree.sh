#!/usr/bin/env bash
# The committed trees make_release.sh packs must pass its own guards: a tracked
# file that looks like game data (e.g. a synthetic test archive named *.psarc)
# aborts every release. Checks HEAD of this repo and of the engine
# (PS3_ENGINE_ROOT, else ../ps3recomp, like make_release.sh), engine without games/.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
. "$HERE/../lib/release_guards.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/gow2-recomp" "$T/ps3recomp"
git -C "$R" archive HEAD | tar -x -C "$T/gow2-recomp"
t_false "gow2-recomp HEAD: no game-looking file" kit_find_game_files "$T/gow2-recomp"
t_false "gow2-recomp HEAD: no Mach-O" kit_find_macho "$T/gow2-recomp"
ENGINE="${PS3_ENGINE_ROOT:-$R/../ps3recomp}"
if git -C "$ENGINE" rev-parse HEAD >/dev/null 2>&1; then
    git -C "$ENGINE" archive HEAD | tar -x -C "$T/ps3recomp"
    mv "$T/ps3recomp/games/gow2/lift_baseline" "$T/lift_baseline" 2>/dev/null || true
    rm -rf "$T/ps3recomp/games"
    [ -d "$T/lift_baseline" ] && mkdir -p "$T/ps3recomp/games/gow2" && mv "$T/lift_baseline" "$T/ps3recomp/games/gow2/"
    t_false "engine HEAD (games/ como no zip): no game-looking file" kit_find_game_files "$T/ps3recomp"
    t_false "engine HEAD (games/ como no zip): no Mach-O" kit_find_macho "$T/ps3recomp"
else
    echo "  skip engine not found at $ENGINE"
fi
t_done
