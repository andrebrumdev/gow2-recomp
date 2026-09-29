#!/usr/bin/env bash
# setup.sh step 1 refuses early, in pt-BR, when a Homebrew tool the Mac build needs is
# missing: the link (build_macos.sh) runs `pkg-config --libs sdl2`, so without
# pkg-config or SDL2 the kit used to fail only at step 6, after the whole lift.
# PY=/nonexistent stops setup.sh right after the tool checks (rc 2 from pick_python).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/eng" "$T/game" "$T/bin"
for t in cmake ninja; do printf '#!/bin/sh\nexit 0\n' > "$T/bin/$t"; chmod +x "$T/bin/$t"; done
run() { env -u KIT_TOOLS -u PS3KIT PS3_ENGINE_ROOT="$T/eng" PY=/nonexistent PATH="$T/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
            bash "$R/kit/setup.sh" "$T/game" > "$T/out" 2>&1; }

run; t_eq 1 $? "no pkg-config: setup.sh stops"
t_true "no pkg-config: says what to install" grep -q 'falta o pkg-config: brew install pkgconf' "$T/out"

printf '#!/bin/sh\nexit 1\n' > "$T/bin/pkg-config"; chmod +x "$T/bin/pkg-config"   # pkg-config without sdl2
run; t_eq 1 $? "no SDL2: setup.sh stops"
t_true "no SDL2: says what to install" grep -q 'falta o SDL2: brew install sdl2' "$T/out"

printf '#!/bin/sh\nexit 0\n' > "$T/bin/pkg-config"                                   # both present
run; t_true "tools present: setup.sh goes on to Python" grep -q 'PY nao e' "$T/out"
t_false "tools present: no tool refusal" grep -q 'falta o' "$T/out"
t_done
