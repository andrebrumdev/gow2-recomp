#!/usr/bin/env bash
# apply_all_patches.sh per-patch capture (kit Phase 2a): gated by KIT_STAGE_DIR,
# hashes only (never a copy of the lift), loud on failure, and the default run is
# unchanged. Runs the real script under /bin/bash (3.2 on macOS) in a throwaway repo
# with three fake patches; no Python, no game data.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
. "$HERE/assert.sh"
T=$(t_tmp); trap 'rm -rf "$T"' EXIT
FILES="ppu_recomp.h ppu_recomp_000.cpp ppu_recomp_001.cpp ppu_recomp_002.cpp ppu_recomp_003.cpp ppu_recomp_004.cpp ppu_recomp_005.cpp ppu_recomp_006.cpp"
mkdir -p "$T/repo/kit/lib" "$T/repo/recomp_mid_v2" "$T/eng/games/gow2/lift_baseline"
cp "$R/apply_all_patches.sh" "$T/repo/"
cp "$R/kit/lib/stages.sh" "$T/repo/kit/lib/"
# Fake "python": a patch is a bash script; the inline marker checks (stdin) pass.
cat > "$T/py" <<'EOF'
#!/bin/bash
if [ "${1:-}" = - ]; then cat > /dev/null; echo "CHECKS: todos passaram"; exit 0; fi
exec /bin/bash "$@"
EOF
chmod +x "$T/py"
# The file names inside the scripts are what apply_all_patches.sh watches (TRACKED).
printf '#!/bin/bash\n# edits ppu_recomp_000.cpp\necho "/* a */" >> "$1/ppu_recomp_000.cpp"\n' > "$T/repo/recomp_mid_v2/patch_a_edit.py"
printf '#!/bin/bash\n# needle in ppu_recomp_001.cpp not found\nexit 1\n' > "$T/repo/recomp_mid_v2/patch_b_fail.py"
printf '#!/bin/bash\n# ppu_recomp_002.cpp already has it\nexit 0\n' > "$T/repo/recomp_mid_v2/patch_c_noop.py"
printf '#!/bin/bash\nexit 2\n' > "$T/eng/games/gow2/lift_baseline/check_contracts.py"   # no contract -> UNVERIFIED
fresh_lift() { rm -rf "$T/repo/lift"; mkdir -p "$T/repo/lift"; for f in $FILES; do echo "// $f" > "$T/repo/lift/$f"; done; }
lift_sums() { (cd "$T/repo/lift" && shasum -a 256 $FILES); }
run() { # run <log> [VAR=value...]: the real script, bash 3.2, fake engine root and python
    local log=$1; shift
    (cd "$T/repo" && env -u KIT_STAGE_DIR -u KIT_STAGE_KEEP -u PS3_PATCH_SKIP_LIST PS3_ENGINE_ROOT="$T/eng" PS3_PATCH_PYTHON="$T/py" \
        PS3_PATCH_DEPS="$T/no_deps.tsv" "$@" /bin/bash ./apply_all_patches.sh lift > "$log" 2>&1)
}
sha() { shasum -a 256 | cut -d' ' -f1; }
val() { awk -F'\t' -v s="$1" -v k="$2" '$1==s && $2==k {print $3}' "$3"; }

# default: no stage dir, no ERRO, and the same output/rc/lift as a capturing run
fresh_lift; run "$T/off.log"; OFF_RC=$?; lift_sums > "$T/off.sums"
t_true "default run creates no stage dir" test ! -e "$T/stages"
t_false "default run prints no ERRO" grep -q '^ERRO' "$T/off.log"
fresh_lift; run "$T/on.log" KIT_STAGE_DIR="$T/stages"; ON_RC=$?; lift_sums > "$T/on.sums"
t_eq "$OFF_RC" "$ON_RC" "same exit code with and without capture"
t_true "same output with and without capture" cmp -s "$T/off.log" "$T/on.log"
t_true "same lift with and without capture" cmp -s "$T/off.sums" "$T/on.sums"
# Optional: the pre-change script as a baseline (Task 2 Step 6 sets KIT_APPLY_BASELINE;
# run_all does not).
if [ -n "${KIT_APPLY_BASELINE:-}" ]; then
    cp "$KIT_APPLY_BASELINE" "$T/repo/apply_all_patches.sh"
    fresh_lift; run "$T/base.log"; BASE_RC=$?; lift_sums > "$T/base.sums"
    t_eq "$OFF_RC" "$BASE_RC" "baseline script: same exit code"
    t_true "baseline script: same output" cmp -s "$T/off.log" "$T/base.log"
    t_true "baseline script: same lift" cmp -s "$T/off.sums" "$T/base.sums"
    cp "$R/apply_all_patches.sh" "$T/repo/"
fi

# records: 8 hashes per patch in stages.tsv (the file that becomes the committed
# golden); order + status per patch in the SEPARATE ppu_status.tsv (Task 1's
# stage_record target -- Codex review BLOCKER, 2026-09-28: nothing but hashes may
# ever reach stages.tsv).
S="$T/stages/stages.tsv"; ST="$T/stages/ppu_status.tsv"
t_eq 24 "$(grep -c '^ppu_after/' "$S")" "8 hashes after each of the 3 patches"
t_false "stages.tsv (the future committed golden) never has a status word" grep -q '^ppu_status' "$S"
t_eq "001:APPLIED"    "$(val ppu_status patch_a_edit.py "$ST")" "patch a: order 1, APPLIED"
t_eq "002:FAILED"     "$(val ppu_status patch_b_fail.py "$ST")" "patch b: order 2, FAILED"
t_eq "003:UNVERIFIED" "$(val ppu_status patch_c_noop.py "$ST")" "patch c: order 3, UNVERIFIED"
t_eq "$(printf '// ppu_recomp_001.cpp\n' | sha)" "$(val ppu_after/patch_a_edit.py ppu_recomp_001.cpp "$S")" "an untouched file keeps its raw hash"
t_eq "$(sha < "$T/repo/lift/ppu_recomp_000.cpp")" "$(val ppu_after/patch_a_edit.py ppu_recomp_000.cpp "$S")" "patch a's edit is in its snapshot"
t_eq "$(val ppu_after/patch_a_edit.py ppu_recomp_000.cpp "$S")" "$(val ppu_after/patch_c_noop.py ppu_recomp_000.cpp "$S")" "later patches keep it"

# A SKIPPED patch still gets its (unchanged) hash captured and its order/status
# recorded before the loop's `continue` (Codex review MAJOR, 2026-09-28). The shipped
# SKIP_LIST is hardcoded empty and not env-overridable, so this uses a throwaway copy
# of the repo with a test-only PS3_PATCH_SKIP_LIST override, kept OUT of run()'s shared
# env (above) so the off/on/keep/err/nolib comparisons -- and the Step 6 baseline
# equivalence, which predates this override -- are untouched by it.
TS="$T/skiprepo"; mkdir -p "$TS/recomp_mid_v2" "$TS/kit/lib"
cp "$T/repo/apply_all_patches.sh" "$TS/"
cp "$T/repo/kit/lib/stages.sh" "$TS/kit/lib/"
cp "$T/repo/recomp_mid_v2/"patch_*.py "$TS/recomp_mid_v2/"
printf '#!/bin/bash\necho SHOULD-NOT-RUN\nexit 1\n' > "$TS/recomp_mid_v2/patch_d_skip.py"
skiprun() { # skiprun <log> [VAR=value...]: same harness, one extra always-skipped patch
    local log=$1; shift
    (cd "$TS" && env -u KIT_STAGE_DIR -u KIT_STAGE_KEEP PS3_ENGINE_ROOT="$T/eng" PS3_PATCH_PYTHON="$T/py" \
        PS3_PATCH_DEPS="$T/no_deps.tsv" PS3_PATCH_SKIP_LIST=patch_d_skip.py "$@" /bin/bash ./apply_all_patches.sh lift > "$log" 2>&1)
}
rm -rf "$TS/lift"; mkdir -p "$TS/lift"; for f in $FILES; do echo "// $f" > "$TS/lift/$f"; done
skiprun "$T/skip.log" KIT_STAGE_DIR="$T/sts"; SKIP_RC=$?
# The harness run is always rc 1 (patch_b fails by design, no verify_lift.sh, UNVERIFIED
# without a baseline), so "does not fail the run" means: the same rc as the 3-patch
# run without it (and so not the capture's rc 2).
t_eq "$OFF_RC" "$SKIP_RC" "a SKIPPED patch does not fail the run (same rc as the 3-patch run)"
t_true "the run reports it skipped, not run" grep -qE '^SKIPPED[[:space:]]+patch_d_skip\.py' "$T/skip.log"
t_true "the run counts it as SKIPPED, not FAILED" grep -q '^TOTAL: 4 patches .*SKIPPED=1' "$T/skip.log"
SS="$T/sts/stages.tsv"; SST="$T/sts/ppu_status.tsv"
t_eq 32 "$(grep -c '^ppu_after/' "$SS")" "8 hashes captured for each of the 4 patches, including the skipped one"
t_eq "004:SKIPPED" "$(val ppu_status patch_d_skip.py "$SST")" "the skipped patch's order and status are recorded before continue"
t_eq "$(val ppu_after/patch_c_noop.py ppu_recomp_000.cpp "$SS")" "$(val ppu_after/patch_d_skip.py ppu_recomp_000.cpp "$SS")" "a SKIPPED patch changes nothing: same hash as the previous patch's snapshot"

# KIT_STAGE_KEEP=1 never copies a per-patch lift
fresh_lift; run "$T/keep.log" KIT_STAGE_DIR="$T/stk" KIT_STAGE_KEEP=1
t_true "KIT_STAGE_KEEP never copies per-patch lifts" test ! -e "$T/stk/ppu_after"
t_eq 24 "$(grep -c '^ppu_after/' "$T/stk/stages.tsv")" "the hashes are still recorded with KIT_STAGE_KEEP=1"

# a failed capture stops the run loudly (setup.sh dies on ^ERRO)
fresh_lift; rm "$T/repo/lift/ppu_recomp.h"; run "$T/err.log" KIT_STAGE_DIR="$T/ste"; ERR_RC=$?
t_eq 2 "$ERR_RC" "a failed capture stops the run (rc 2)"
t_true "and says ERRO naming the patch" grep -q '^ERRO: stage_capture ppu_after/patch_a_edit.py falhou' "$T/err.log"
t_false "no later patch ran" grep -q 'patch_b_fail.py' "$T/err.log"

# KIT_STAGE_DIR without stages.sh: refuse; the default run does not need it
mv "$T/repo/kit/lib/stages.sh" "$T/stages.sh.bak"
fresh_lift; run "$T/nolib.log" KIT_STAGE_DIR="$T/stn"; NOLIB_RC=$?
t_eq 2 "$NOLIB_RC" "KIT_STAGE_DIR without kit/lib/stages.sh -> rc 2"
t_true "with an ERRO line" grep -q '^ERRO: KIT_STAGE_DIR definido mas kit/lib/stages.sh ausente' "$T/nolib.log"
fresh_lift; run "$T/nolib_off.log"
t_true "without stages.sh the default run still applies every patch" grep -q '^TOTAL: 3 patches' "$T/nolib_off.log"
mv "$T/stages.sh.bak" "$T/repo/kit/lib/stages.sh"
t_done
