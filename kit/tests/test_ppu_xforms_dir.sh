#!/usr/bin/env bash
# kit/ppu_xforms (Kit sem Python, Phase 2b): structure only -- no Python, no ps3kit, no
# lift. ORDER lists every recomp_mid_v2/patch_*.py exactly once, as '<name>' or
# 'noop <name>'; the noop entries are exactly the committed golden hash chain's no-effect
# entries (Ruling 2b Q3); every .xform belongs to a non-noop ORDER name and names it in its
# header; AUDIT_ALLOW.tsv lines carry hash, reason and reviewer; nothing else lives in the
# directory.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
. "$R/kit/lib/xform_order.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
X="$R/kit/ppu_xforms"
t_true "kit/ppu_xforms/ORDER exists" test -f "$X/ORDER"
lines() { grep -v -e '^#' -e '^[[:space:]]*$' "$X/ORDER" 2>/dev/null; }
t_eq "" "$(lines | grep -Ev '^(noop )?[A-Za-z0-9_.-]+$')" "every ORDER line is '<name>' or 'noop <name>'"
kit_order_names "$X/ORDER" > "$T/names" 2>/dev/null
t_eq "" "$(sort "$T/names" | uniq -d)" "ORDER names are unique"
t_eq "$(cd "$R/recomp_mid_v2" && ls patch_*.py | LC_ALL=C sort)" "$(LC_ALL=C sort "$T/names")" \
     "ORDER lists every recomp_mid_v2/patch_*.py (a new patch must be added to ORDER)"
t_eq "$(kit_order_noops "$R/kit/golden/stages.tsv" "$T/names" 2>&1)" "$(lines | awk '$1=="noop" {print $2}')" \
     "the noop entries are exactly the golden hash chain's no-effect entries, in ORDER order"
for x in "$X"/*.xform; do
    [ -e "$x" ] || continue
    b="$(basename "$x" .xform)"
    t_true "$b.xform belongs to the (non-noop) ORDER entry $b.py" grep -qx "$b.py" "$X/ORDER"
    t_eq "ps3kit-xform 1" "$(sed -n 1p "$x")" "$b.xform: first line"
    t_eq "xform $b.py" "$(grep -m1 '^xform ' "$x")" "$b.xform: header names its patch"
    t_true "$b.xform: has authored-in <path>@<commit>" grep -qE "^authored-in recomp_mid_v2/$b\.py@[0-9a-f]{7,40}\$" "$x"
    t_true "$b.xform: has a file section (no effect = 'noop' in ORDER)" grep -q '^file ' "$x"
done
if [ -f "$X/AUDIT_ALLOW.tsv" ]; then
    t_eq "" "$(grep -v -e '^#' -e '^$' "$X/AUDIT_ALLOW.tsv" | awk -F'\t' 'NF != 3 || $1 !~ /^[0-9a-f]{64}$/ || $2 ~ /^[[:space:]]*$/ || $3 ~ /^[[:space:]]*$/' )" \
         "AUDIT_ALLOW.tsv: every entry is <sha256> TAB <reason> TAB <reviewer>"
fi
t_eq "" "$(cd "$X" 2>/dev/null && ls -A | grep -v -e '^ORDER$' -e '^README$' -e '^AUDIT_ALLOW\.tsv$' -e '\.xform$')" \
     "only ORDER, README, AUDIT_ALLOW.tsv and *.xform in kit/ppu_xforms"
t_done
