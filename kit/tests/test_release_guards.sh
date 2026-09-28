#!/usr/bin/env bash
# make_release.sh's guards must fire under `set -euo pipefail` even when the
# offending file hides among thousands (a `| grep -q` guard failed open there).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/assert.sh"
. "$HERE/../lib/release_guards.sh"
quiet() { "$@" >/dev/null; }
T=$(t_tmp); trap 'rm -rf "$T"' EXIT

mkdir -p "$T/clean/a" "$T/macho/a" "$T/game/a"
for i in $(seq 1 3000); do
    echo "text $i" > "$T/clean/a/f$i.txt"; echo "text $i" > "$T/macho/a/f$i.txt"
    : > "$T/game/a/voice$i.wav"                  # many hits: find outlives a grep -q
done
cp /bin/ls "$T/macho/a/zz_tool"

t_false "clean tree: no Mach-O" quiet kit_find_macho "$T/clean"
t_false "clean tree: no game file" quiet kit_find_game_files "$T/clean"
for run in 1 2 3; do
    t_true "Mach-O among 3000 files is found (run $run)" quiet kit_find_macho "$T/macho"
    t_true "3000 game files are found (run $run)" quiet kit_find_game_files "$T/game"
done
HITS="$(kit_find_macho "$T/macho" || true)"
t_true "the Mach-O hit names the file" grep -q "zz_tool" <<<"$HITS"
t_false "text files are not reported" grep -q "\.txt:" <<<"$HITS"

# Control: the old pattern misses the same planted file (proves the test discriminates).
missed=0
for run in 1 2 3; do
    if find "$T/macho" -type f -print0 | xargs -0 file 2>/dev/null | grep -q 'Mach-O'; then :; else missed=$((missed + 1)); fi
done
echo "  info old '| grep -q' Mach-O guard missed $missed/3 runs"
missed=0
for run in 1 2 3; do
    if find "$T/game" -iname '*.wav' -print | grep -q .; then :; else missed=$((missed + 1)); fi
done
echo "  info old '| grep -q' game-file guard missed $missed/3 runs"
t_done
