#!/usr/bin/env bash
# kit/golden/xform_check.sh -- MAINTAINER acceptance of kit/ppu_xforms (Kit sem Python,
# Phase 2b/2c): apply ORDER (xforms + residual Python patches) with ps3kit to a COPY of the
# pinned raw lift, in scratch, and compare every ppu_after/<name> with the golden.
#
#   kit/golden/xform_check.sh <ppu_raw_dir> <scratch> [<xforms_dir>]
#
# Env: PS3KIT (a built ps3kit, required), PY (Python >= 3.11 for the residual patches;
# default kit_pick_python), KIT_GOLDEN (test-only; default kit/golden/stages.tsv).
# Prints XFORM-CHECK OK identical=<n> (rc 0) or the non-IDENTICAL records and
# XFORM-CHECK FAIL (rc 1); rc 2 on a refusal. Writes only inside <scratch>.
set -uo pipefail
usage() { sed -n '2,11p' "$0"; exit 2; }
[ $# -ge 2 ] && [ $# -le 3 ] || usage
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
RAW=$1; X="${3:-$HERE/kit/ppu_xforms}"
GOLDEN="${KIT_GOLDEN:-$HERE/kit/golden/stages.tsv}"
. "$HERE/kit/lib/stages.sh"; . "$HERE/kit/lib/xform_maint.sh"; . "$HERE/kit/lib/pick_python.sh"
refuse() { echo "xform_check.sh: $*" >&2; exit 2; }
[ -n "${PS3KIT:-}" ] && [ -x "$PS3KIT" ] || refuse "PS3KIT must point to a built ps3kit"
[ -f "$X/ORDER" ] || refuse "no ORDER in $X"
[ -f "$GOLDEN" ] || refuse "no golden $GOLDEN"
kit_check_raw "$RAW" "$GOLDEN" || refuse "$RAW is not the pinned raw lift (ppu_raw hashes differ)"
S="$(kit_scratch_dir "$2" .kit_xform_scratch)" || exit 2
PY="${PY:-$(kit_pick_python "$HERE")}" || refuse "no Python >= 3.11 for the residual patches"
export PY
rm -rf "$S/lift" "$S/stages"; mkdir -p "$S/lift"
for f in $KIT_PPU_FILES; do cp "$RAW/$f" "$S/lift/$f"; done
rm -f "$S/residual.log"   # residual patches' own output (may quote the lift): scratch only
KIT_RESIDUAL_LOG="$S/residual.log" KIT_STAGE_DIR="$S/stages" "$PS3KIT" apply-xforms "$X" "$S/lift" --patch-dir "$HERE/recomp_mid_v2" > "$S/apply.log" 2>&1
rc=$?
if [ "$rc" != 0 ]; then
    tail -5 "$S/apply.log" >&2
    echo "XFORM-CHECK FAIL (apply-xforms rc=$rc, log $S/apply.log)"; exit 1
fi
grep '^ppu_after/' "$GOLDEN" | grep -v '^ppu_after/kit_delta	' > "$S/golden_after.tsv"
stage_compare "$S/golden_after.tsv" "$S/stages/stages.tsv" > "$S/compare.txt"; crc=$?
echo "   xforms=$(grep -c '^XFORM ' "$S/apply.log") noop=$(grep -c '^NOOP ' "$S/apply.log") residual=$(grep -c '^RESIDUAL ' "$S/apply.log")"
if [ "$crc" = 0 ]; then echo "XFORM-CHECK OK identical=$(grep -c '^IDENTICAL' "$S/compare.txt")"; exit 0; fi
grep -v '^IDENTICAL' "$S/compare.txt" | head -40
echo "XFORM-CHECK FAIL"; exit 1
