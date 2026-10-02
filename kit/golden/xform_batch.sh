#!/usr/bin/env bash
# kit/golden/xform_batch.sh -- MAINTAINER driver of one Phase-2c conversion batch (never run
# by the kit). Everything lifted stays in <scratch>; only reviewed .xform files reach the repo.
#
#   kit/golden/xform_batch.sh draft   <ppu_raw> <scratch> <list>
#   kit/golden/xform_batch.sh stage   <ppu_raw> <scratch> <list>
#   kit/golden/xform_batch.sh accept  <ppu_raw> <scratch> <list> <ledger>
#   kit/golden/xform_batch.sh unstage <ppu_raw> <scratch> <list>
#
# <list>: one patch name per line (effective ORDER entries).
# draft  : xform_convert.sh into <scratch>/conv (XFORM_DRAFT_FLAGS, default "--collapse"),
#          one SUMMARY line per patch (MASS when ops > XFORM_MASS_OPS, default 2000).
# stage  : per name: draft present, RESIDUAL line 'pending:', no .xform yet; the two '# DRAFT'
#          lines become the provenance comments (XFORM_REVIEWER required); copied into
#          kit/ppu_xforms/, RESIDUAL line removed; then the structural test, xform-audit on
#          <ppu_raw>, and staged fragments == reviewed rows of <scratch>/conv/fragments.tsv.
# accept : ledger gate (Provenance: + Fragment-review: ... rejected=0; ... reviewer), staged ==
#          reviewed again, xform_check.sh: every record IDENTICAL, 8 per listed name.
# unstage: removes the listed .xform files that git does not track and restores RESIDUAL.
# Env: PS3KIT (required), PY, KIT_GOLDEN (test-only), XFORM_REVIEWER, XFORM_DRAFT_FLAGS, XFORM_MASS_OPS.
set -uo pipefail
usage() { sed -n '2,20p' "$0"; exit 2; }
[ $# -ge 4 ] || usage
CMD=$1; RAW=$2; SARG=$3; LIST=$4
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
X="$HERE/kit/ppu_xforms"
GOLDEN="${KIT_GOLDEN:-$HERE/kit/golden/stages.tsv}"
. "$HERE/kit/lib/stages.sh"; . "$HERE/kit/lib/xform_maint.sh"; . "$HERE/kit/lib/xform_order.sh"
refuse() { echo "xform_batch.sh: $*" >&2; exit 2; }
case "$CMD" in draft|stage|accept|unstage) ;; *) usage ;; esac
[ -n "${PS3KIT:-}" ] && [ -x "$PS3KIT" ] || refuse "PS3KIT must point to a built ps3kit"
[ -s "$LIST" ] || refuse "empty or missing list $LIST"
NAMES="$(grep -v -e '^#' -e '^[[:space:]]*$' "$LIST")"
for n in $NAMES; do
    case "$n" in *[!A-Za-z0-9_.-]*) refuse "bad name '$n' in $LIST" ;; esac
    grep -qx -- "$n" "$X/ORDER" || refuse "$n is not an effective entry of $X/ORDER"
done
S="$(kit_scratch_dir "$SARG" .kit_xform_batch)" || exit 2
C="$S/conv"
TAB="$(printf '\t')"
same_as_reviewed() { # rc 0 iff the staged files' fragments equal the reviewed rows
    local n s
    for n in $NAMES; do s="${n%.py}"; grep "^$s\.xform:" "$C/fragments.tsv"; done > "$S/reviewed.tsv"
    for n in $NAMES; do s="${n%.py}"; kit_xform_fragments "$X/$s.xform" "$HERE/recomp_mid_v2/$n"; done > "$S/staged.tsv"
    if cmp -s "$S/reviewed.tsv" "$S/staged.tsv"; then echo "FRAGMENTS SAME AS REVIEWED"; return 0; fi
    echo "FRAGMENTS DIFFER (staged vs reviewed: $S/staged.tsv $S/reviewed.tsv)"; return 1
}
case "$CMD" in
draft)
    XFORM_DRAFT_FLAGS="${XFORM_DRAFT_FLAGS---collapse}" bash "$HERE/kit/golden/xform_convert.sh" "$RAW" "$C" $NAMES > "$S/draft.log" 2>&1
    rc=$?
    [ "$rc" != 2 ] || { tail -5 "$S/draft.log" >&2; refuse "xform_convert.sh refused (log $S/draft.log)"; }
    grep -E '^(DRAFT|XFORM-AUDIT|XFORM-CONVERT)' "$S/draft.log"
    for n in $NAMES; do
        s="${n%.py}"; d="$C/drafts/$s.xform"
        [ -f "$d" ] || { echo "SUMMARY $n NO-DRAFT"; continue; }
        ops=$(grep -c '^op ' "$d"); files=$(grep -c '^file ' "$d"); each=$(grep -c '^at each ' "$d")
        hits=$(grep -cE "^AUDIT(-JOIN)?-HIT $s\.xform:" "$C/audit.txt")
        grep "^$s\.xform:" "$C/fragments.tsv" > "$S/f.tsv"
        rows=$(grep -c . "$S/f.tsv"); distinct=$(cut -f2- "$S/f.tsv" | sed 's/^IN-SCRIPT:[0-9,]*/IN-SCRIPT/' | sort -u | grep -c .)
        nis=$(grep -c "${TAB}NOT-IN-SCRIPT${TAB}" "$S/f.tsv"); pos=$(grep -c "${TAB}POSITIONAL${TAB}" "$S/f.tsv")
        mass=""; [ "$ops" -gt "${XFORM_MASS_OPS:-2000}" ] && mass=" MASS"
        echo "SUMMARY $n files=$files ops=$ops each=$each audit-hits=$hits rows=$rows distinct=$distinct not-in-script=$nis positional=$pos$mass"
    done
    echo "BATCH-DRAFT convert-rc=$rc -> $C (review EVERY row of $C/fragments.tsv for each draft: the gate)"
    exit 0 ;;
stage)
    [ -n "${XFORM_REVIEWER:-}" ] || refuse "XFORM_REVIEWER (who reviewed the fragments) is required"
    [ -f "$C/fragments.tsv" ] || refuse "no $C/fragments.tsv: run 'draft' first"
    for n in $NAMES; do
        s="${n%.py}"; d="$C/drafts/$s.xform"
        [ -f "$d" ] || refuse "no draft for $n"
        [ ! -e "$X/$s.xform" ] || refuse "$X/$s.xform already exists"
        grep -q "^$n${TAB}pending:" "$X/RESIDUAL" || refuse "$n has no 'pending:' line in $X/RESIDUAL"
        case "$(sed -n 4p "$d")" in "# DRAFT "*) ;; *) refuse "$d: line 4 is not the '# DRAFT' comment" ;; esac
        case "$(sed -n 5p "$d")" in "# then run ps3kit xform-audit"*) ;; *) refuse "$d: line 5 is not the draft's second comment" ;; esac
    done
    day="$(date +%Y-%m-%d)"
    for n in $NAMES; do
        s="${n%.py}"; d="$C/drafts/$s.xform"
        awk -v c1="# Converted $day by kit/golden/xform_convert.sh from recomp_mid_v2/$n." \
            -v c2="# Fragment review: every authored fragment checked against the patch script by $XFORM_REVIEWER (2c ledger)." \
            'NR == 4 { print c1; next } NR == 5 { print c2; next } { print }' "$d" > "$X/$s.xform"
        if /usr/bin/diff <(sed '4,5d' "$d") <(sed '4,5d' "$X/$s.xform") > /dev/null; then echo "STAGED-EQUALS-DRAFT $n"
        else refuse "$X/$s.xform differs from its draft beyond the two header lines"; fi
        awk -F'\t' -v n="$n" '$1 != n' "$X/RESIDUAL" > "$S/RESIDUAL.new" && cat "$S/RESIDUAL.new" > "$X/RESIDUAL"
        echo "STAGED $n"
    done
    bash "$HERE/kit/tests/test_ppu_xforms_dir.sh" > "$S/dirtest.txt" 2>&1 || { cat "$S/dirtest.txt"; echo "BATCH-STAGE FAIL (structure)"; exit 1; }
    "$PS3KIT" xform-audit "$X" "$RAW" > "$S/audit_staged.txt" 2>&1; arc=$?
    tail -1 "$S/audit_staged.txt"
    [ "$arc" = 0 ] || { echo "BATCH-STAGE FAIL (xform-audit rc=$arc, $S/audit_staged.txt)"; exit 1; }
    same_as_reviewed || { echo "BATCH-STAGE FAIL"; exit 1; }
    echo "BATCH-STAGE OK names=$(printf '%s\n' $NAMES | grep -c .)"; exit 0 ;;
accept)
    LED=${5:-}; [ -f "$LED" ] || refuse "accept needs the ledger file as 5th argument"
    miss=0   # every missing ledger gate line is reported before refusing
    for n in $NAMES; do
        s="${n%.py}"
        [ -f "$X/$s.xform" ] || refuse "$n is not staged ($X/$s.xform missing)"
        grep -qE "^Provenance: kit/ppu_xforms/$s\.xform " "$LED" || { echo "xform_batch.sh: no Provenance line for $n in $LED" >&2; miss=1; }
        grep -qE "^Fragment-review: kit/ppu_xforms/$s\.xform fragments=[0-9]+ .*rejected=0; .*reviewer " "$LED" || { echo "xform_batch.sh: no Fragment-review line for $n in $LED" >&2; miss=1; }
    done
    [ "$miss" = 0 ] || refuse "ledger gate lines missing (see above)"
    same_as_reviewed || { echo "BATCH-ACCEPT FAIL"; exit 1; }
    bash "$HERE/kit/golden/xform_check.sh" "$RAW" "$S/check" > "$S/check.txt" 2>&1; crc=$?
    tail -2 "$S/check.txt"
    [ "$crc" = 0 ] || { echo "BATCH-ACCEPT FAIL (xform_check rc=$crc, $S/check.txt)"; exit 1; }
    want=$((8 * $(kit_order_names "$X/ORDER" | grep -c .)))
    got=$(grep -c '^IDENTICAL' "$S/check/compare.txt")
    [ "$got" = "$want" ] || { echo "BATCH-ACCEPT FAIL (identical=$got, expected $want)"; exit 1; }
    recs=0
    for n in $NAMES; do
        k=$(grep -cF "IDENTICAL ppu_after/$n${TAB}" "$S/check/compare.txt")
        [ "$k" = 8 ] || { echo "BATCH-ACCEPT FAIL ($n: $k of 8 records IDENTICAL)"; exit 1; }
        grep -qx "XFORM $n" "$S/check/apply.log" || { echo "BATCH-ACCEPT FAIL ($n did not run as a xform)"; exit 1; }
        recs=$((recs + 8))
    done
    echo "BATCH-ACCEPT OK names=$(printf '%s\n' $NAMES | grep -c .) records=$recs identical=$got"; exit 0 ;;
unstage)
    for n in $NAMES; do
        s="${n%.py}"
        if [ -f "$X/$s.xform" ] && ! git -C "$HERE" ls-files --error-unmatch "kit/ppu_xforms/$s.xform" > /dev/null 2>&1; then
            rm -f "$X/$s.xform"; echo "UNSTAGED $n"
        fi
    done
    git -C "$HERE" checkout -- kit/ppu_xforms/RESIDUAL && echo "RESIDUAL restored"; exit 0 ;;
esac
