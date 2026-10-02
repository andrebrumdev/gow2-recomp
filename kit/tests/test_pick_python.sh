#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/assert.sh"
. "$HERE/../lib/pick_python.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
mk() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\nexit %s\n' "$2" > "$1"; chmod +x "$1"; }
mk "$T/g2/.kit_tools/python/bin/python3" 0   # kit-built, qualifies
mk "$T/bin/pyold" 1                           # too old
mk "$T/bin/pynew" 0                           # qualifies
export KIT_PY_CANDIDATES="pyold pynew"
PATH="$T/bin:/usr/bin:/bin"
unset PY
t_eq "$T/g2/.kit_tools/python/bin/python3" "$(kit_pick_python "$T/g2")" "kit-built python wins"
t_eq "$T/bin/pynew" "$(kit_pick_python "$T/none")" "falls back to the first qualifying candidate"
t_eq "$T/bin/pynew" "$(PY="$T/bin/pynew" kit_pick_python "$T/g2")" "PY overrides everything"
PY="$T/bin/pyold" kit_pick_python "$T/g2" >/dev/null 2>&1; t_eq 2 $? "a too-old PY is an error, not a fallback"
KIT_PY_CANDIDATES="pyold" kit_pick_python "$T/none" >/dev/null; t_eq 1 $? "nothing qualifies -> rc 1 (setup then builds from source)"
t_done
