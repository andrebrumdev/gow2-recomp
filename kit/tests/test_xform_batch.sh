#!/usr/bin/env bash
# kit/golden/xform_batch.sh on a synthetic git repo (invented widget_* text; the "patches" are
# bash scripts run with PY=/bin/bash). Refusals need no ps3kit; the draft -> stage -> accept
# round trip needs the real one (PS3KIT). Without it the round trip prints a skip line that the
# task acceptance requires to be ABSENT.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R0="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
FILES="ppu_recomp.h ppu_recomp_000.cpp ppu_recomp_001.cpp ppu_recomp_002.cpp ppu_recomp_003.cpp ppu_recomp_004.cpp ppu_recomp_005.cpp ppu_recomp_006.cpp"
R="$T/repo"; mkdir -p "$R/kit/lib" "$R/kit/golden" "$R/kit/tests" "$R/kit/ppu_xforms" "$R/recomp_mid_v2"
cp "$R0/kit/lib/stages.sh" "$R0/kit/lib/xform_maint.sh" "$R0/kit/lib/xform_order.sh" "$R0/kit/lib/pick_python.sh" "$R/kit/lib/"
cp "$R0/kit/golden/xform_convert.sh" "$R0/kit/golden/xform_check.sh" "$R0/kit/golden/xform_batch.sh" "$R/kit/golden/"
cp "$R0/kit/tests/assert.sh" "$R0/kit/tests/test_ppu_xforms_dir.sh" "$R/kit/tests/"
RAW="$T/raw"; mkdir -p "$RAW"
for f in $FILES; do printf '// %s\n' "$f" > "$RAW/$f"; done
printf '// synthetic\nvoid func_00001000(unit_t* u) {\n    widget_a(u, 1);\n    widget_b(u);\n}\n' > "$RAW/ppu_recomp_000.cpp"
cat > "$R/recomp_mid_v2/patch_a.py" <<'EOF'
# synthetic patch a: our probe before widget_b
f="$1/ppu_recomp_000.cpp"
awk '{ if ($0 == "    widget_b(u);") print "    probe_counter_a(u); /* ours */"; print }' "$f" > "$f.t" && mv "$f.t" "$f"
EOF
printf '# synthetic patch b (stays residual)\nprintf "    widget_r(u);\\n" >> "$1/ppu_recomp_001.cpp"\n' > "$R/recomp_mid_v2/patch_b.py"
printf 'patch_a.py\npatch_b.py\n' > "$R/kit/ppu_xforms/ORDER"
printf 'patch_a.py\tpending: Phase 2c conversion\npatch_b.py\tpending: Phase 2c conversion\n' > "$R/kit/ppu_xforms/RESIDUAL"
GOLD="$R/kit/golden/stages.tsv"; L1="$T/l1"; cp -R "$RAW" "$L1"
h() { shasum -a 256 < "$1" | cut -d' ' -f1; }
{ for f in $FILES; do printf 'ppu_raw\t%s\t%s\n' "$f" "$(h "$RAW/$f")"; done
  bash "$R/recomp_mid_v2/patch_a.py" "$L1"; for f in $FILES; do printf 'ppu_after/patch_a.py\t%s\t%s\n' "$f" "$(h "$L1/$f")"; done
  bash "$R/recomp_mid_v2/patch_b.py" "$L1"; for f in $FILES; do printf 'ppu_after/patch_b.py\t%s\t%s\n' "$f" "$(h "$L1/$f")"; done; } > "$GOLD"
git -C "$R" init -q && git -C "$R" add kit recomp_mid_v2 && git -C "$R" -c user.name=t -c user.email=t@t commit -qm init
LIST="$T/list"; printf 'patch_a.py\n' > "$LIST"
LED="$T/ledger.md"; : > "$LED"
drv() { env PY=/bin/bash KIT_GOLDEN="$GOLD" "$@"; }

echo "== refusals"
drv env -u PS3KIT bash "$R/kit/golden/xform_batch.sh" draft "$RAW" "$T/s0" "$LIST" > "$T/out" 2>&1; t_eq 2 $? "no PS3KIT: rc 2"
printf 'patch_zz.py\n' > "$T/badlist"
drv PS3KIT=/usr/bin/true bash "$R/kit/golden/xform_batch.sh" draft "$RAW" "$T/s0" "$T/badlist" > "$T/out" 2>&1; t_eq 2 $? "a name that is not an effective ORDER entry: rc 2"
drv PS3KIT=/usr/bin/true bash "$R/kit/golden/xform_batch.sh" draft "$RAW" "$R/scr" "$LIST" > "$T/out" 2>&1; t_eq 2 $? "scratch inside a git work tree: rc 2"
drv PS3KIT=/usr/bin/true bash "$R/kit/golden/xform_batch.sh" bogus "$RAW" "$T/s0" "$LIST" > "$T/out" 2>&1; t_eq 2 $? "unknown subcommand: rc 2"

echo "== draft -> stage -> accept with the real ps3kit"
if [ -n "${PS3KIT:-}" ] && [ -x "$PS3KIT" ]; then
    S="$T/scr"
    drv PS3KIT="$PS3KIT" bash "$R/kit/golden/xform_batch.sh" draft "$RAW" "$S" "$LIST" > "$T/out" 2>&1; t_eq 0 $? "draft: rc 0"
    t_true "  one SUMMARY line for patch_a" grep -qE '^SUMMARY patch_a\.py files=1 ops=1 each=0 audit-hits=0 rows=1 distinct=1 not-in-script=0 positional=0$' "$T/out"
    t_true "  the draft stays in scratch" test -f "$S/conv/drafts/patch_a.xform"
    drv PS3KIT="$PS3KIT" bash "$R/kit/golden/xform_batch.sh" stage "$RAW" "$S" "$LIST" > "$T/out" 2>&1; t_eq 2 $? "stage without XFORM_REVIEWER: rc 2"
    t_true "  nothing staged" test ! -e "$R/kit/ppu_xforms/patch_a.xform"
    drv PS3KIT="$PS3KIT" XFORM_REVIEWER=tester bash "$R/kit/golden/xform_batch.sh" stage "$RAW" "$S" "$LIST" > "$T/out" 2>&1; t_eq 0 $? "stage: rc 0"
    t_true "  STAGED-EQUALS-DRAFT" grep -q '^STAGED-EQUALS-DRAFT patch_a\.py$' "$T/out"
    t_true "  FRAGMENTS SAME AS REVIEWED" grep -q '^FRAGMENTS SAME AS REVIEWED$' "$T/out"
    t_true "  the xform is in kit/ppu_xforms" test -f "$R/kit/ppu_xforms/patch_a.xform"
    t_eq "# Converted $(date +%Y-%m-%d) by kit/golden/xform_convert.sh from recomp_mid_v2/patch_a.py." "$(sed -n 4p "$R/kit/ppu_xforms/patch_a.xform")" "  header line 4"
    t_eq "# Fragment review: every authored fragment checked against the patch script by tester (2c ledger)." "$(sed -n 5p "$R/kit/ppu_xforms/patch_a.xform")" "  header line 5"
    t_false "  its RESIDUAL line is gone" grep -q '^patch_a\.py	' "$R/kit/ppu_xforms/RESIDUAL"
    t_true "  the other RESIDUAL line stays" grep -q '^patch_b\.py	pending:' "$R/kit/ppu_xforms/RESIDUAL"
    drv PS3KIT="$PS3KIT" bash "$R/kit/golden/xform_batch.sh" accept "$RAW" "$S" "$LIST" "$LED" > "$T/out" 2>&1; t_eq 2 $? "accept without the ledger gate lines: rc 2"
    t_true "  says which line is missing" grep -q 'no Fragment-review line for patch_a.py' "$T/out"
    printf 'Provenance: kit/ppu_xforms/patch_a.xform <- recomp_mid_v2/patch_a.py@x; ours; reviewer tester; d\n' >> "$LED"
    printf 'Fragment-review: kit/ppu_xforms/patch_a.xform fragments=1 in-script=1 not-in-script=0 () positional=0 needle-only=0 rejected=0; fragments.tsv sha256=x; reviewer tester; d\n' >> "$LED"
    drv PS3KIT="$PS3KIT" bash "$R/kit/golden/xform_batch.sh" accept "$RAW" "$S" "$LIST" "$LED" > "$T/out" 2>&1; t_eq 0 $? "accept: rc 0"
    t_true "  BATCH-ACCEPT OK names=1 records=8 identical=16" grep -q '^BATCH-ACCEPT OK names=1 records=8 identical=16$' "$T/out"
    sed -i '' 's/probe_counter_a(u); \/\* ours \*\//probe_counter_a(u); \/* ours! *\//' "$R/kit/ppu_xforms/patch_a.xform"
    drv PS3KIT="$PS3KIT" bash "$R/kit/golden/xform_batch.sh" accept "$RAW" "$S" "$LIST" "$LED" > "$T/out" 2>&1; t_eq 1 $? "accept after the staged file was edited: rc 1"
    t_true "  names the mismatch" grep -q 'FRAGMENTS DIFFER' "$T/out"
    drv PS3KIT="$PS3KIT" bash "$R/kit/golden/xform_batch.sh" unstage "$RAW" "$S" "$LIST" > "$T/out" 2>&1; t_eq 0 $? "unstage: rc 0"
    t_true "  the xform is removed" test ! -e "$R/kit/ppu_xforms/patch_a.xform"
    t_true "  RESIDUAL back to the committed one" git -C "$R" diff --quiet -- kit/ppu_xforms/RESIDUAL
else  # PS3KIT unset
    echo "  skip (PS3KIT unset: the round trip needs a built ps3kit)"
fi
t_done
