#!/usr/bin/env bash
# kit/golden/per_patch_check.sh on synthetic goldens (one broken rule each), in its
# hash-only mode (golden.tsv alone -- what kit/tests/run_all.sh and CI run against the
# committed kit/golden/stages.tsv) and its full mode (+ the scratch ppu_status.tsv --
# order and status NEVER live in the committed golden, Codex review BLOCKER,
# 2026-09-28), and on the committed golden itself once it carries the per-patch stages.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
CHK="$R/kit/golden/per_patch_check.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
FILES="ppu_recomp.h ppu_recomp_000.cpp ppu_recomp_001.cpp ppu_recomp_002.cpp ppu_recomp_003.cpp ppu_recomp_004.cpp ppu_recomp_005.cpp ppu_recomp_006.cpp"
# A consistent 3-patch golden: a APPLIED (changes 000), b FAILED, c UNVERIFIED; the
# kit delta changes 001. Values are stand-ins for hashes. Hashes and status/order are
# two SEPARATE files, exactly like stages.tsv / ppu_status.tsv on a real run.
good() {
    echo "# synthetic"
    for f in $FILES; do printf 'ppu_raw\t%s\tr_%s\n' "$f" "$f"; done
    for p in a b c; do
        for f in $FILES; do v="r_$f"; [ "$f" = ppu_recomp_000.cpp ] && v=a0; printf 'ppu_after/patch_%s.py\t%s\t%s\n' "$p" "$f" "$v"; done
    done
    for f in $FILES; do v="r_$f"; [ "$f" = ppu_recomp_000.cpp ] && v=a0; printf 'ppu_patched\t%s\t%s\n' "$f" "$v"; done
    for s in ppu_after/kit_delta ppu_final; do
        for f in $FILES; do v="r_$f"; [ "$f" = ppu_recomp_000.cpp ] && v=a0; [ "$f" = ppu_recomp_001.cpp ] && v=d1; printf '%s\t%s\t%s\n' "$s" "$f" "$v"; done
    done
}
good_status() { printf 'ppu_status\tpatch_a.py\t001:APPLIED\nppu_status\tpatch_b.py\t002:FAILED\nppu_status\tpatch_c.py\t003:UNVERIFIED\n'; }
# set <stage> <relpath> <value>: rewrite one record of the good golden
set_rec() { good | awk -F'\t' -v OFS='\t' -v s="$1" -v k="$2" -v v="$3" '$1==s && $2==k {$3=v} {print}'; }
# set_status <patch> <NNN:STATUS>: rewrite one record of the good status file
set_status() { good_status | awk -F'\t' -v OFS='\t' -v k="$1" -v v="$2" '$2==k {$3=v} {print}'; }
bad_case() { # bad_case <message> <expected BAD substring> <golden> [status]
    local out rc msg="$1" want="$2" g="$3" st="${4:-}"
    if [ -n "$st" ]; then out="$(bash "$CHK" "$g" "$st" 2>&1)"; else out="$(bash "$CHK" "$g" 2>&1)"; fi
    rc=$?
    t_eq 1 "$rc" "$msg: rc 1"
    t_true "$msg: says '$want'" grep -qF -- "$want" <<< "$out"
}
good > "$T/good.tsv"; good_status > "$T/good_status.tsv"

echo "== hash-only mode (golden.tsv alone -- the committed-golden mode)"
t_eq "PER-PATCH OK (hashes only) n=3 kit_delta_files=1" "$(bash "$CHK" "$T/good.tsv")" "consistent golden, no status file"
good | grep -v -F "ppu_after/patch_b.py	ppu_recomp.h	" > "$T/hole.tsv"
bad_case "snapshot missing a file" "ppu_after/patch_b.py does not have the 8 PPU files" "$T/hole.tsv"
set_rec ppu_final ppu_recomp_001.cpp other > "$T/kd.tsv"
bad_case "kit delta vs final (hash-only)" "ppu_after/kit_delta != ppu_final" "$T/kd.tsv"
bash "$CHK" "$T/absent.tsv" > /dev/null 2>&1; t_eq 2 $? "missing golden -> rc 2"

echo "== full mode (golden.tsv + status.tsv)"
t_eq "PER-PATCH OK n=3 APPLIED=1 UNVERIFIED=1 FAILED=1 kit_delta_files=1" \
    "$(bash "$CHK" "$T/good.tsv" "$T/good_status.tsv")" "consistent golden + status"
set_rec ppu_after/patch_b.py ppu_recomp_002.cpp x > "$T/b.tsv"
bad_case "FAILED patch that changed a file" "patch_b.py is FAILED but changed a file" "$T/b.tsv" "$T/good_status.tsv"
set_rec ppu_after/patch_a.py ppu_recomp_000.cpp r_ppu_recomp_000.cpp > "$T/a.tsv"
bad_case "APPLIED patch that changed nothing" "patch_a.py is APPLIED but changed no file" "$T/a.tsv" "$T/good_status.tsv"
set_status patch_c.py 004:UNVERIFIED > "$T/gap_status.tsv"
bad_case "order gap" "order gap at 003" "$T/good.tsv" "$T/gap_status.tsv"
set_status patch_c.py 002:UNVERIFIED > "$T/dup_status.tsv"
bad_case "order used twice" "order 002 used twice" "$T/good.tsv" "$T/dup_status.tsv"
set_status patch_c.py 003:WHATEVER > "$T/unk_status.tsv"
bad_case "unknown status" "unknown status WHATEVER" "$T/good.tsv" "$T/unk_status.tsv"
set_rec ppu_final ppu_recomp_001.cpp other > "$T/kd.tsv"
bad_case "kit delta vs final (full)" "ppu_after/kit_delta != ppu_final" "$T/kd.tsv" "$T/good_status.tsv"
set_rec ppu_patched ppu_recomp_005.cpp other > "$T/last.tsv"
bad_case "last snapshot vs ppu_patched" "!= ppu_patched" "$T/last.tsv" "$T/good_status.tsv"
good | grep -v -F "ppu_after/patch_b.py	ppu_recomp.h	" > "$T/hole.tsv"
bad_case "snapshot missing a file (full)" "ppu_after/patch_b.py does not have the 8 PPU files" "$T/hole.tsv" "$T/good_status.tsv"
: > "$T/empty_status.tsv"
bad_case "no status records" "no ppu_status records" "$T/good.tsv" "$T/empty_status.tsv"
good | grep -v -F 'ppu_after/patch_c.py' > "$T/drift.tsv"
bad_case "status.tsv names a patch missing from the golden" "has a ppu_status record but no ppu_after/patch_c.py in the golden" "$T/drift.tsv" "$T/good_status.tsv"
good_status | grep -v patch_c.py > "$T/drift_status.tsv"
bad_case "golden has a patch missing from status.tsv" "has no ppu_status record in" "$T/good.tsv" "$T/drift_status.tsv"
bash "$CHK" "$T/good.tsv" "$T/absent_status.tsv" > /dev/null 2>&1; t_eq 2 $? "missing status file -> rc 2"

# The committed golden: hash-only mode is always meaningful (guard removed in Task 5,
# once the golden carries the per-patch stages); it can never carry ppu_status
# (Controller ruling 1 -- see the standalone assertion in Task 5 Step 6).
if grep -q '^ppu_after/' "$R/kit/golden/stages.tsv"; then
    t_true "committed golden is per-patch consistent (hashes only)" bash "$CHK" "$R/kit/golden/stages.tsv"
fi
t_false "the committed golden never holds a patch status word (Controller ruling 1: hashes only)" \
    grep -qE '(APPLIED|FAILED|NO-MATCH|UNVERIFIED|SKIPPED|ALREADY-APPLIED)' "$R/kit/golden/stages.tsv"
t_done
