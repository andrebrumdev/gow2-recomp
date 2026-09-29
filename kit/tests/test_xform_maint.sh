#!/usr/bin/env bash
# Maintainer drivers of Phase 2b (kit/golden/xform_check.sh, xform_convert.sh) on a
# synthetic repo: a fake ps3kit for the orchestration/compare logic, the real one (only
# when PS3KIT is set) for one converter round trip. Invented widget_* text only.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R0="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd)"   # normalise (TMPDIR may end in '/'): the drivers print paths via pwd
FILES="ppu_recomp.h ppu_recomp_000.cpp ppu_recomp_001.cpp ppu_recomp_002.cpp ppu_recomp_003.cpp ppu_recomp_004.cpp ppu_recomp_005.cpp ppu_recomp_006.cpp"
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
R="$T/repo"; RAW="$T/raw"
mkdir -p "$R/kit/golden" "$R/kit/lib" "$R/kit/ppu_xforms" "$R/recomp_mid_v2" "$RAW"
cp "$R0/kit/golden/xform_check.sh" "$R0/kit/golden/xform_convert.sh" "$R/kit/golden/"
cp "$R0/kit/lib/stages.sh" "$R0/kit/lib/pick_python.sh" "$R0/kit/lib/xform_maint.sh" "$R/kit/lib/"
for f in $FILES; do printf '// %s\n' "$f" > "$RAW/$f"; done
printf 'void func_00001000(unit_t* u) {\n    widget_a(u, 1);\n    widget_b(u);\n}\n' > "$RAW/ppu_recomp_000.cpp"
# residual "patches" are bash scripts run with PY=/bin/bash
printf 'sed -i "" "s/widget_a(u, 1);/widget_a(u, 1); widget_z(u);/" "$1/ppu_recomp_000.cpp"\n' > "$R/recomp_mid_v2/patch_a.py"
cat > "$R/recomp_mid_v2/patch_b.py" <<'RES'
f="$1/ppu_recomp_000.cpp"
awk '{ if ($0 == "    widget_b(u);") print "    probe_counter_b(u); /* ours */"; print }' "$f" > "$f.t" && mv "$f.t" "$f"
RES
# a `noop` entry (Ruling 2b Q3): its script would leave a sentinel if it ever ran
printf 'touch "%s/noop_ran"\n' "$T" > "$R/recomp_mid_v2/patch_n.py"
printf 'patch_a.py\nnoop patch_n.py\npatch_b.py\n' > "$R/kit/ppu_xforms/ORDER"
# golden: ppu_raw of RAW, ppu_after for the 3 names (hash of RAW is enough for the fake), kit_delta
G="$T/golden.tsv"
{ for f in $FILES; do printf 'ppu_raw\t%s\t%s\n' "$f" "$(sha "$RAW/$f")"; done
  for n in patch_a.py patch_n.py patch_b.py kit_delta; do for f in $FILES; do printf 'ppu_after/%s\t%s\t%s\n' "$n" "$f" "$(sha "$RAW/$f")"; done; done; } > "$G"
grep '^ppu_after/patch_' "$G" > "$T/records.tsv"
mkdir -p "$T/bin"; cat > "$T/bin/ps3kit" <<'FAKE'
#!/bin/bash
echo "$*" >> "$FAKE_LOG"
case "$1" in
  apply-xforms) [ -n "${KIT_STAGE_DIR:-}" ] && { mkdir -p "$KIT_STAGE_DIR"; cat "$FAKE_RECORDS" >> "$KIT_STAGE_DIR/stages.tsv"; }
                echo "RESIDUAL patch_a.py rc=0"; echo "NOOP patch_n.py"; echo "XFORM patch_b.py"; exit "${FAKE_RC:-0}" ;;
  *) exit 0 ;;
esac
FAKE
chmod +x "$T/bin/ps3kit"
chk() { env KIT_GOLDEN="$G" PY=/bin/bash FAKE_LOG="$T/fake.log" FAKE_RECORDS="${REC:-$T/records.tsv}" "$@" \
          bash "$R/kit/golden/xform_check.sh" "$RAW" "$SC" > "$T/out" 2>&1; }

echo "== xform_check.sh: refusals"
SC="$T/scr1"
chk env -u PS3KIT; t_eq 2 $? "no PS3KIT: rc 2"
chk PS3KIT="$T/bin/ps3kit"; t_eq 0 $? "baseline run: rc 0"
SC="$T/scr1/../repo/x"; chk PS3KIT="$T/bin/ps3kit"; t_eq 2 $? "a scratch path with '..': rc 2"
t_true "  says why" grep -q "'.' or '..'" "$T/out"
git init -q "$T/gitwt"; SC="$T/gitwt/scr"; chk PS3KIT="$T/bin/ps3kit"; t_eq 2 $? "scratch inside a git work tree: rc 2"
t_true "  says why" grep -q 'inside a git work tree' "$T/out"
t_true "  nothing created there" test ! -e "$T/gitwt/scr"
mkdir -p "$T/busy"; : > "$T/busy/x"; SC="$T/busy"; chk PS3KIT="$T/bin/ps3kit"; t_eq 2 $? "non-empty scratch without marker: rc 2"
cp "$RAW/ppu_recomp_000.cpp" "$T/000.keep"; printf '// changed\n' >> "$RAW/ppu_recomp_000.cpp"
SC="$T/scr1"; chk PS3KIT="$T/bin/ps3kit"; t_eq 2 $? "raw lift that is not the pinned one: rc 2"
t_true "  says why" grep -q 'not the pinned raw lift' "$T/out"
cp "$T/000.keep" "$RAW/ppu_recomp_000.cpp"

echo "== xform_check.sh: compare"
SC="$T/scr1"; : > "$T/fake.log"; chk PS3KIT="$T/bin/ps3kit"; rc=$?
t_eq 0 "$rc" "all ppu_after records identical: rc 0 (kit_delta is not compared)"
t_true "  summary (3 entries x 8 files, the noop entry included)" grep -q '^XFORM-CHECK OK identical=24$' "$T/out"
t_true "  counts per kind" grep -q '^   xforms=1 noop=1 residual=1$' "$T/out"
t_true "  apply-xforms ran on the scratch copy with the repo's patch dir" \
    grep -qF "apply-xforms $R/kit/ppu_xforms $(cd "$T/scr1" && pwd -P)/lift --patch-dir $R/recomp_mid_v2" "$T/fake.log"
t_eq "$(sha "$T/000.keep")" "$(sha "$RAW/ppu_recomp_000.cpp")" "  the raw lift is never written"
sed '$ s/[0-9a-f]\{64\}$/0000000000000000000000000000000000000000000000000000000000000000/' "$T/records.tsv" > "$T/records_bad.tsv"
REC="$T/records_bad.tsv" chk PS3KIT="$T/bin/ps3kit"; t_eq 1 $? "one different hash: rc 1"
t_true "  names the record" grep -q '^DIFF      ppu_after/patch_b.py	ppu_recomp_006.cpp$' "$T/out"
t_true "  summary" grep -q '^XFORM-CHECK FAIL$' "$T/out"
chk PS3KIT="$T/bin/ps3kit" FAKE_RC=2; t_eq 1 $? "apply-xforms failing: rc 1"
t_true "  says so" grep -q 'apply-xforms rc=2' "$T/out"

echo "== xform_convert.sh: refusals"
cvt() { env KIT_GOLDEN="$G" PY=/bin/bash "$@" bash "$R/kit/golden/xform_convert.sh" "$RAW" "$SC" patch_b.py > "$T/out" 2>&1; }
SC="$T/scr2"
cvt env -u PS3KIT; t_eq 2 $? "no PS3KIT: rc 2"
SC="$T/gitwt/scr2"; cvt PS3KIT="$T/bin/ps3kit"; t_eq 2 $? "scratch inside a git work tree: rc 2"
SC="$T/scr2"; env KIT_GOLDEN="$G" PY=/bin/bash PS3KIT="$T/bin/ps3kit" bash "$R/kit/golden/xform_convert.sh" "$RAW" "$SC" patch_zz.py > "$T/out" 2>&1
t_eq 2 $? "a patch that is not in ORDER: rc 2"
env KIT_GOLDEN="$G" PY=/bin/bash PS3KIT="$T/bin/ps3kit" bash "$R/kit/golden/xform_convert.sh" "$RAW" "$SC" patch_n.py > "$T/out" 2>&1
t_eq 2 $? "a noop target: rc 2 (nothing to draft)"
t_true "  says why" grep -q "is 'noop' in ORDER" "$T/out"

echo "== kit_xform_fragments: every fragment, any length, with its status"
. "$R/kit/lib/xform_maint.sh"
printf 'ps3kit-xform 1\nxform patch_f.py\nauthored-in a@b\nfile ppu_recomp_000.cpp\nscope file\nat line sha256:%s nth 1 of 1\nop insert-after\ntemplate <<END\n    ok_one(u);{{line}} x\nEND\nat line sha256:%s nth 1 of 1\nop edit-line\nregex ^([\\s\\S]{4})([\\s\\S]{2})([\\s\\S]{0})$\nsubst \\1{ zz_not_there(); \\2 }\\3\n' \
    "$(printf '%064d' 0)" "$(printf '%064d' 1)" > "$T/patch_f.xform"
printf 'BLOCK = "    ok_one(u);\\n"\nx = {1}\n' > "$T/patch_f.py"
kit_xform_fragments "$T/patch_f.xform" "$T/patch_f.py" > "$T/frag.tsv"
t_eq "$(printf 'patch_f.xform:9\tIN-SCRIPT:1\tok_one(u);\npatch_f.xform:9\tIN-SCRIPT:2\tx\npatch_f.xform:13\tPOSITIONAL\t-\npatch_f.xform:14\tNOT-IN-SCRIPT\t{ zz_not_there();\npatch_f.xform:14\tIN-SCRIPT:2\t}')" \
     "$(cat "$T/frag.tsv")" "one row per fragment (short ones too), placeholders split, positional regex marked"

echo "== xform_convert.sh: round trip with the real ps3kit"
if [ -n "${PS3KIT:-}" ] && [ -x "$PS3KIT" ]; then
    SC="$T/scr3"; cvt PS3KIT="$PS3KIT"; t_eq 0 $? "converter rc 0"
    D="$T/scr3/drafts/patch_b.xform"
    t_true "  draft written" test -s "$D"
    t_true "  before-state kept in scratch" test -f "$T/scr3/before/patch_b.py/ppu_recomp_000.cpp"
    t_true "  the before-state has patch_a applied (earlier ORDER entries ran)" grep -q 'widget_z' "$T/scr3/before/patch_b.py/ppu_recomp_000.cpp"
    t_true "  audit clean" grep -q '^XFORM-AUDIT OK' "$T/scr3/audit.txt"
    t_true "  the draft names its patch" grep -qx 'xform patch_b.py' "$D"
    t_true "  the noop entry was never run while replaying the earlier entries" test ! -e "$T/noop_ran"
    t_true "  fragment list written" test -s "$T/scr3/fragments.tsv"
    t_true "  the inserted probe line is a fragment found in the patch script" \
        grep -qE '^patch_b\.xform:[0-9]+	IN-SCRIPT:[0-9,]+	probe_counter_b\(u\); /\* ours \*/$' "$T/scr3/fragments.tsv"
    t_eq 0 "$(grep -c '	NOT-IN-SCRIPT	' "$T/scr3/fragments.tsv")" "  no fragment outside the patch script"
    # the draft, applied after patch_a, reproduces the Python run
    mkdir -p "$T/x3"; cp "$D" "$T/x3/"; cp "$R/kit/ppu_xforms/ORDER" "$T/x3/"
    mkdir -p "$T/l3"; for f in $FILES; do cp "$RAW/$f" "$T/l3/$f"; done
    PY=/bin/bash "$PS3KIT" apply-xforms "$T/x3" "$T/l3" --patch-dir "$R/recomp_mid_v2" > /dev/null 2>&1
    mkdir -p "$T/l4"; for f in $FILES; do cp "$RAW/$f" "$T/l4/$f"; done
    /bin/bash "$R/recomp_mid_v2/patch_a.py" "$T/l4"; /bin/bash "$R/recomp_mid_v2/patch_b.py" "$T/l4"
    t_true "  xform result == residual result" cmp -s "$T/l3/ppu_recomp_000.cpp" "$T/l4/ppu_recomp_000.cpp"
    t_true "  apply-xforms skipped the noop entry too" test ! -e "$T/noop_ran"
else
    # run_all.sh has no ps3kit; the task's acceptance (Step 4) and Task 10 run this file
    # with PS3KIT set and require this line to be ABSENT -- the fake alone proves nothing
    # about the applier.
    echo "  skip (PS3KIT unset: the round trip needs a built ps3kit)"
fi
t_done
