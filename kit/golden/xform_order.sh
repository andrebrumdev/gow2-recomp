#!/usr/bin/env bash
# kit/golden/xform_order.sh -- MAINTAINER (Kit sem Python, Phase 2b): the ORDER candidate
# for kit/ppu_xforms, in <scratch>: names from ./apply_all_patches.sh --print-order, and
# 'noop <name>' for every name the committed golden hash chain shows without effect on
# the pinned lift (Ruling 2b Q3). Reads committed data only (patch order, golden hashes).
#
#   kit/golden/xform_order.sh <scratch>
#
# Writes <scratch>/ORDER.new and <scratch>/noops.txt; prints
# XFORM-ORDER names=<n> noop=<k> -> <scratch>/ORDER.new. rc 2 on a refusal.
# Env: PS3_ENGINE_ROOT, PY (default kit_pick_python), KIT_GOLDEN (test-only).
set -uo pipefail
usage() { sed -n '2,11p' "$0"; exit 2; }
[ $# = 1 ] || usage
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
GOLDEN="${KIT_GOLDEN:-$HERE/kit/golden/stages.tsv}"
. "$HERE/kit/lib/xform_order.sh"; . "$HERE/kit/lib/pick_python.sh"
refuse() { echo "xform_order.sh: $*" >&2; exit 2; }
S=$1; case "$S" in /*) ;; *) S="$PWD/$S" ;; esac
case "$S/" in */./*|*/../*) refuse "scratch $1: a '.' or '..' component" ;; esac
a=$S; while [ ! -d "$a" ]; do a=${a%/*}; [ -n "$a" ] || a=/; done
git -C "$a" rev-parse --show-toplevel >/dev/null 2>&1 && refuse "scratch $1: inside a git work tree"
[ -f "$GOLDEN" ] || refuse "no golden $GOLDEN"
PY="${PY:-$(kit_pick_python "$HERE")}" || refuse "no Python >= 3.11 for order_patches.py"
mkdir -p "$S" || refuse "cannot create $S"
(cd "$HERE" && PS3_PATCH_PYTHON="$PY" ./apply_all_patches.sh --print-order) > "$S/names.txt" || refuse "--print-order failed"
kit_order_noops "$GOLDEN" "$S/names.txt" > "$S/noops.txt" || refuse "the golden hash chain could not be walked"
{
  echo "# kit/ppu_xforms/ORDER -- the kit's PPU patch layer in application order (Kit sem Python, Phase 2)."
  echo "# One recomp_mid_v2 patch file name per line, in the order ./apply_all_patches.sh --print-order"
  echo "# computes from lift_baseline/PATCH_DEPS.tsv. 'noop <name>': the per-patch golden hash chain"
  echo "# shows the patch leaves the pinned lift unchanged -- apply-xforms runs nothing for it (Ruling 2b Q3)."
  echo "# A name with <stem>.xform here is applied by 'ps3kit apply-xforms'; any other runs as residual Python."
  echo "# Names and the noop marker only: no status, no lifted text (Controller ruling 1)."
  awk -v nf="$S/noops.txt" 'BEGIN { while ((getline l < nf) > 0) noop[l] = 1 } { print (($0 in noop) ? "noop " : "") $0 }' "$S/names.txt"
} > "$S/ORDER.new"
echo "XFORM-ORDER names=$(wc -l < "$S/names.txt" | tr -d ' ') noop=$(wc -l < "$S/noops.txt" | tr -d ' ') -> $S/ORDER.new"
