#!/usr/bin/env bash
# kit/lib/xform_order.sh + kit/golden/xform_order.sh (Kit sem Python, Phase 2b, Ruling 2b
# Q3): ORDER names and the golden hash chain that decides the `noop` entries, on a
# synthetic golden (invented hashes, no lift, no Python).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
. "$R/kit/lib/xform_order.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
FILES="ppu_recomp.h ppu_recomp_000.cpp ppu_recomp_001.cpp ppu_recomp_002.cpp ppu_recomp_003.cpp ppu_recomp_004.cpp ppu_recomp_005.cpp ppu_recomp_006.cpp"
hx() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
rec() { # rec <stage> <tag>: 8 records; the tag decides every file's hash
    local f; for f in $FILES; do printf '%s\t%s\t%s\n' "$1" "$f" "$(hx "$2 $f")"; done
}
{ rec ppu_raw r0; rec ppu_after/patch_a.py r0; rec ppu_after/patch_b.py r1; rec ppu_after/patch_c.py r1
  rec ppu_after/patch_d.py r1; rec ppu_after/patch_e.py r2; rec ppu_after/kit_delta r3; } | sort > "$T/golden.tsv"
printf '# header\npatch_a.py\n\npatch_b.py\n  noop patch_c.py\npatch_d.py\npatch_e.py\n' > "$T/ORDER"
t_eq "patch_a.py patch_b.py patch_c.py patch_d.py patch_e.py" "$(kit_order_names "$T/ORDER" | paste -sd' ' -)" "names in order, noop marker dropped"
kit_order_names "$T/ORDER" > "$T/names"
t_eq "patch_a.py patch_c.py patch_d.py" "$(kit_order_noops "$T/golden.tsv" "$T/names" | paste -sd' ' -)" \
     "noop = 8 hashes equal to the previous entry's (ppu_raw for the first), whatever the golden's sort order"
# one file changed is enough to make an entry effective
awk -F'\t' 'BEGIN{OFS="\t"} $1=="ppu_after/patch_d.py" && $2=="ppu_recomp_004.cpp" {$3="0000000000000000000000000000000000000000000000000000000000000000"} {print}' \
    "$T/golden.tsv" > "$T/g2.tsv"
t_eq "patch_a.py patch_c.py" "$(kit_order_noops "$T/g2.tsv" "$T/names" | paste -sd' ' -)" "one differing file of 8 = not noop (and the next entry compares against it)"
grep -v '^ppu_after/patch_b.py	ppu_recomp_003.cpp' "$T/golden.tsv" > "$T/g3.tsv"
kit_order_noops "$T/g3.tsv" "$T/names" > /dev/null 2> "$T/err"; t_eq 1 $? "a name with 7 records: rc 1"
t_true "  says which" grep -q 'ppu_after/patch_b.py has 7 records' "$T/err"
printf 'patch_zz.py\n' > "$T/names_missing"
kit_order_noops "$T/golden.tsv" "$T/names_missing" > /dev/null 2>&1; t_eq 1 $? "a name absent from the golden: rc 1"

echo "== kit/golden/xform_order.sh refuses a scratch inside a git work tree or with '..'"
git init -q "$T/wt"
KIT_GOLDEN="$T/golden.tsv" bash "$R/kit/golden/xform_order.sh" "$T/wt/scr" > "$T/out" 2>&1; t_eq 2 $? "inside a git work tree: rc 2"
t_true "  nothing created there" test ! -e "$T/wt/scr"
KIT_GOLDEN="$T/golden.tsv" bash "$R/kit/golden/xform_order.sh" "$T/a/../b" > "$T/out" 2>&1; t_eq 2 $? "a '..' component: rc 2"
t_done
