#!/usr/bin/env bash
# kit/golden/xform_convert.sh -- MAINTAINER tooling (Kit sem Python, Phase 2b; never run by
# the kit): draft <stem>.xform for the given patches from their effect on the pinned raw
# lift. Every output stays in <scratch>: before-states and diffs ARE lifted code, and a
# draft is committed only after a clean xform-audit AND the fragment review of every row
# of fragments.tsv against the patch script (Controller ruling 1; the audit is detection,
# not proof).
#
#   kit/golden/xform_convert.sh <ppu_raw_dir> <scratch> <patch.py>...
#
# Per patch (in ORDER order): every earlier ORDER entry is replayed on a copy of the raw
# lift by 'ps3kit apply-xforms' with the ORDER lines kept verbatim -- 'noop <name>' stays
# noop (never run as Python, Ruling 2b Q3), a name with a committed .xform uses it, any
# other runs as residual Python -- that state is kept as before/<name>/, the patch runs
# alone, diffs/<name>/<file>.diff = diff -U0, drafts/<stem>.xform = ps3kit xform-draft.
# Then audit.txt = ps3kit xform-audit drafts/ <raw>, and fragments.tsv = every authored
# fragment (any length) of every draft with its status in the patch script.
# Env: PS3KIT (required), PY (default kit_pick_python), KIT_GOLDEN (test-only).
set -uo pipefail
usage() { sed -n '2,19p' "$0"; exit 2; }
[ $# -ge 3 ] || usage
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
RAW=$1; SARG=$2; shift 2
X="$HERE/kit/ppu_xforms"
GOLDEN="${KIT_GOLDEN:-$HERE/kit/golden/stages.tsv}"
. "$HERE/kit/lib/stages.sh"; . "$HERE/kit/lib/xform_maint.sh"; . "$HERE/kit/lib/pick_python.sh"
refuse() { echo "xform_convert.sh: $*" >&2; exit 2; }
[ -n "${PS3KIT:-}" ] && [ -x "$PS3KIT" ] || refuse "PS3KIT must point to a built ps3kit"
[ -f "$X/ORDER" ] || refuse "no ORDER in $X"
for p in "$@"; do
    grep -qx -- "noop $p" "$X/ORDER" && refuse "$p is 'noop' in ORDER (no effect on the pinned lift): nothing to draft"
    grep -qx -- "$p" "$X/ORDER" || refuse "$p is not in $X/ORDER"
done
kit_check_raw "$RAW" "$GOLDEN" || refuse "$RAW is not the pinned raw lift (ppu_raw hashes differ)"
S="$(kit_scratch_dir "$SARG" .kit_xform_scratch)" || exit 2
PY="${PY:-$(kit_pick_python "$HERE")}" || refuse "no Python >= 3.11 for the residual patches"
export PY
rm -rf "$S/work" "$S/seg" "$S/before" "$S/diffs" "$S/drafts" "$S/convert.log" "$S/pending" "$S/one"
mkdir -p "$S/work" "$S/seg" "$S/before" "$S/diffs" "$S/drafts"
for f in $KIT_PPU_FILES; do cp "$RAW/$f" "$S/work/$f"; done
run_seg() { # run_seg <with_xforms 0|1> <file of ORDER lines>: apply these entries to work/
    local use=$1 l
    rm -f "$S/seg/"*
    cp "$2" "$S/seg/ORDER"                           # lines verbatim: 'noop <name>' stays noop
    if [ "$use" = 1 ]; then
        while IFS= read -r l; do
            case "$l" in "noop "*) continue ;; esac  # a noop entry has no .xform and runs nothing
            if [ -f "$X/${l%.py}.xform" ]; then cp "$X/${l%.py}.xform" "$S/seg/"; fi
        done < "$2"
    fi
    "$PS3KIT" apply-xforms "$S/seg" "$S/work" --patch-dir "$HERE/recomp_mid_v2" >> "$S/convert.log" 2>&1 \
        || refuse "apply-xforms failed (log $S/convert.log)"
}
is_target() { local p; for p in $TARGETS; do [ "$p" = "$1" ] && return 0; done; return 1; }
TARGETS="$*"; left=$#; : > "$S/pending"
while IFS= read -r line <&3; do
    case "$line" in ''|'#'*) continue ;; esac
    n=${line##* }                                    # '<name>' or 'noop <name>'
    if ! is_target "$n"; then printf '%s\n' "$line" >> "$S/pending"; continue; fi
    [ ! -s "$S/pending" ] || run_seg 1 "$S/pending"
    : > "$S/pending"
    rm -rf "$S/before/$n"; mkdir -p "$S/before/$n" "$S/diffs/$n"
    for f in $KIT_PPU_FILES; do cp "$S/work/$f" "$S/before/$n/$f"; done
    printf '%s\n' "$n" > "$S/one"; run_seg 0 "$S/one"   # the patch itself, always as Python
    for f in $KIT_PPU_FILES; do /usr/bin/diff -U0 "$S/before/$n/$f" "$S/work/$f" > "$S/diffs/$n/$f.diff"; done
    c="$(git -C "$HERE" log -1 --format=%h -- "recomp_mid_v2/$n" 2>/dev/null)"
    [ -n "$c" ] || { echo "WARN: recomp_mid_v2/$n has no commit: authored-in gets 'uncommitted'" >&2; c=uncommitted; }
    d="$S/drafts/${n%.py}.xform"
    "$PS3KIT" xform-draft --name "$n" --authored-in "recomp_mid_v2/$n@$c" --before "$S/before/$n" --diff-dir "$S/diffs/$n" > "$d" \
        || refuse "xform-draft failed for $n"
    ops=$(grep -c '^op ' "$d")
    [ "$ops" -gt 0 ] || refuse "$n changed nothing on the pinned lift but ORDER does not mark it noop -- ORDER and the golden hash chain disagree (re-run kit/golden/xform_order.sh)"
    echo "DRAFT $n ops=$ops -> $d"
    left=$((left - 1)); [ "$left" -gt 0 ] || break
done 3< "$X/ORDER"
[ -f "$X/AUDIT_ALLOW.tsv" ] && cp "$X/AUDIT_ALLOW.tsv" "$S/drafts/"
"$PS3KIT" xform-audit "$S/drafts" "$RAW" > "$S/audit.txt" 2>&1
tail -1 "$S/audit.txt"
: > "$S/fragments.tsv"
for d in "$S"/drafts/*.xform; do
    [ -e "$d" ] || continue
    b="$(basename "$d")"
    kit_xform_fragments "$d" "$HERE/recomp_mid_v2/${b%.xform}.py" >> "$S/fragments.tsv"
done
echo "   fragments: $(wc -l < "$S/fragments.tsv" | tr -d ' ') (not-in-script $(grep -c '	NOT-IN-SCRIPT	' "$S/fragments.tsv"), positional $(grep -c '	POSITIONAL	' "$S/fragments.tsv")) -> $S/fragments.tsv -- review EVERY row (gate)"
exit 0
